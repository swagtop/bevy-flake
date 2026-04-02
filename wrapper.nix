{
  pkgs,

  assembleConfigs,
  applyConfig,
  applyIfFunction,

  rawConfig,
  appliedConfig,
}:

let
  inherit (builtins)
    attrNames
    concatStringsSep
    isFunction
    any
    ;
  inherit (pkgs.lib)
    importJSON
    mapAttrsToList
    optionalAttrs
    ;

  # Just be happy I didn't also add 'AndDevelopable' to this function name.
  makeOverridableAndConfigurable =
    f: i:
    let
      result = f i;
    in
    result
    // {
      override = makeOverridableAndConfigurable (o: if isFunction o then f (i // (o i)) else f (i // o));
      develop = makeOverridableAndConfigurable f (i // { developOnly = true; });
      configure = makeOverridableAndConfigurable (
        c:
        if c ? systems then
          throw "You cannot configure 'systems' on a package level."
        else if c ? withPkgs then
          throw "You cannot configure 'withPkgs' on a package level, as "
          + "not everything can be pinned from here. Configure bevy-flake "
          + "and get the package from there for this type of behaviour."
        else
          f (
            i
            // {
              config = applyConfig (assembleConfigs [ rawConfig c ] pkgs);
            }
          )
      );
    };

  exportEnv =
    env: concatStringsSep "\n" (mapAttrsToList (name: val: "export ${name}=\"${val}\"") env);

  defaultArgParser = ''
    # Check if what the adapter is being run with.
    TARGET_ARG_NO=1
    for arg in "$@"; do
      case $arg in
        "--target")
          # Save next arg as target.
          TARGET_ARG_NO=$((TARGET_ARG_NO + 1))
          eval "BF_TARGET=\$$TARGET_ARG_NO"
          export BF_TARGET="$BF_TARGET"
        ;;
        --target=*)
          # Split arg if using '=' between '--target' and the target.
          IFS='=' read -r -a SPLIT_ARG <<< "$arg"
          export BF_TARGET=''${SPLIT_ARG[1]}
        ;;
        "--no-wrapper")
          set -- "''${@:1:$((TARGET_ARG_NO - 1))}" \
                 "''${@:$((TARGET_ARG_NO + 1))}"
          export BF_NO_WRAPPER="1"
          break
        ;;
      esac
      if [[ $BF_TARGET == "" ]]; then
        TARGET_ARG_NO=$((TARGET_ARG_NO + 1))
      fi
    done
  '';

  wrapExecutable =
    {
      name,
      executable,
      symlinkPackage ? null,
      argParser ? defaultArgParser,
      postExtraScript ? "",
      extraRuntimeInputs ? [ ],
      targets ? null,
      developOnly ? false,
      crossCompileOnly ? false,
      config ? appliedConfig,
      passthru ? { },
    }:
    let
      inherit (config)
        systems
        withPkgs
        rustToolchain
        # linux
        windows
        macos
        web
        # crossPlatformRustflags
        sharedEnvironment
        devEnvironment
        targetEnvironments
        extraScript
        runtimeInputs
        stdenv
        # src
        ;

      pkgs = applyIfFunction withPkgs stdenv.hostPlatform.system;

      runtimeInputs' = runtimeInputs ++ extraRuntimeInputs;
      argParser' = applyIfFunction argParser defaultArgParser;
      targets' = if (targets != null) then targets else attrNames targetEnvironments;
      rustToolchain' = if (targets != null) then rawConfig.rustToolchain targets' else rustToolchain;

      wrapped = pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = runtimeInputs' ++ [
          stdenv.cc
          rustToolchain'
          pkgs.pkg-config
        ];
        bashOptions = [
          "errexit"
          "pipefail"
        ];
        text = ''
          ${argParser'}

          if [[ $BF_NO_WRAPPER == "1" ]]; then
            exec ${executable} "$@"
          fi

          # Set variables need to be set up before 'sharedEnvironment' runs.
          ${exportEnv (
            let
              hasTargets = p: any (i: builtins.elem i targets') p.targets;
            in
            {
              LIBCLANG_PATH = pkgs.libclang.lib + "/lib";
              LIBRARY_PATH = pkgs.libiconv + "/lib";
            }
            # Only add variables relevant to cross-compiliation when not in
            # develop only mode.
            // optionalAttrs (!developOnly) (
              {
                PKG_CONFIG_ALLOW_CROSS = "1";
              }
              // optionalAttrs ((windows.sdk != null) && (hasTargets windows)) {
                # Set up Windows SDK.
                BF_WINDOWS_SDK_PATH = windows.sdk;
              }
              // optionalAttrs ((macos.sdk != null) && (hasTargets macos)) (
                # Set up MacOS SDK, if configured.
                let
                  versions = (importJSON (macos.sdk + "/SDKSettings.json")).SupportedTargets.macosx;
                in
                {
                  BF_MACOS_SDK_PATH = macos.sdk;
                  BF_MACOS_SDK_MINIMUM_VERSION = versions.MinimumDeploymentTarget;
                  BF_MACOS_SDK_DEFAULT_VERSION = versions.DefaultDeploymentTarget;
                }
              )
              // optionalAttrs ((web.wasm-bindgen != null) && (hasTargets web)) {
                BF_WASM_BINDGEN = web.wasm-bindgen;
              }
            )
          )}

          # Base environment for all targets.
          # shellcheck source=/dev/null
          source "${sharedEnvironment}"

          case "$BF_TARGET" in
            "")
              ${
                if (crossCompileOnly && developOnly) then
                  throw "You cannot be in both cross-compilation and develop mode at the same time."
                else if crossCompileOnly then
                  ''
                    echo "bevy-flake: You are using this package in cross-compilation mode."
                    echo "You can therefore only cross-compile for your selected targets."
                    exit 1
                  ''
                else
                  ''
                    # shellcheck source=/dev/null
                    source "${devEnvironment}"
                  ''
              }
            ;;

            ${
              if developOnly then
                ''
                  *)
                    echo "${
                      "bevy-flake: You are using this package develop mode.\n"
                      + "Therefore you cannot cross-compile to any specific "
                      + "target.\n"
                      + "This mode is useful for significantly reducing the "
                      + "amount of dependencies downloaded for when you are "
                      + "only developing.\n"
                      + "Remove the '.develop' suffix of the package you are "
                      + "using to enable cross-compilation, or build for your "
                      + "targets with 'nix build .#targets.<target>'."
                    }"
                    exit 1
                  ;;
                ''
              else
                concatStringsSep "\n" (
                  map (target: ''
                    ${target}*)
                      # shellcheck source=/dev/null
                      source "${targetEnvironments.${target}}"
                    ;;
                  '') targets'
                )
            }
          esac

          ${extraScript}

          ${postExtraScript}

          exec ${executable} "$@"
        '';

        passthru = passthru // {
          inherit runtimeInputs targets;
          appliedConfig = config;
          meta = {
            mainProgram = name;
            platforms = systems;
          };
        };
      };

    in
    if (symlinkPackage == null) then
      wrapped
    else
      pkgs.symlinkJoin {
        inherit name;
        inherit (wrapped) passthru;
        ignoreCollisions = true;
        paths = [
          wrapped
          symlinkPackage
        ];
      };
in
makeOverridableAndConfigurable wrapExecutable
