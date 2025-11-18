{
  pkgs,

  systems,

  linux,
  windows,
  macos,

  crossPlatformRustflags,

  sharedEnvironment,
  devEnvironment,
  targetEnvironments,
  prePostScript,

  mkRustToolchain,
  mkRuntimeInputs,
  mkStdenv,

  src,
}:
let
  inherit (builtins)
    attrNames
    concatStringsSep
    isFunction
    ;
  inherit (pkgs.lib)
    makeSearchPath
    mapAttrsToList
    optionalString
    optionalAttrs
    importJSON
    ;

  exportEnv =
    env: concatStringsSep "\n" (mapAttrsToList (name: val: "export ${name}=\"${val}\"") env);

  targets = (attrNames targetEnvironments);
  # Users need to reference 'pkgs' in the following 4 configs:
  windowsSdk = windows.mkSdk;
  input-rust-toolchain = mkRustToolchain targets;
  runtimeInputsBase = mkRuntimeInputs;
  stdenv = mkStdenv;

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
in
{
  name,
  executable,
  symlinkPackage ? null,
  argParser ? (default: default),
  postScript ? "",
  extraRuntimeInputs ? [ ],
}:
let
  runtimeInputs =
    runtimeInputsBase
    ++ extraRuntimeInputs
    ++ [
      stdenv.cc
      input-rust-toolchain
      pkgs.pkg-config
      pkgs.lld
      (pkgs.wasm-bindgen-cli_0_2_105 or (pkgs.buildWasmBindgenCli (
        let
          pname = "wasm-bindgen-cli";
          version = "0.2.105";
          src = pkgs.fetchCrate {
            inherit pname version;
            hash = "sha256-zLPFFgnqAWq5R2KkaTGAYqVQswfBEYm9x3OPjx8DJRY=";
          };
        in
        {
          inherit src;
          cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
            inherit src pname version;
            hash = "sha256-a2X9bzwnMWNt0fTf30qAiJ4noal/ET1jEtf5fBFj5OU=";
          };
        }
      ))
      )
      (pkgs.writeShellScriptBin "clang-unwrapped" ''
        exec ${pkgs.clangStdenv.cc.cc}/bin/clang "$@"
      '')
    ];
  argParser' = if (isFunction argParser) then argParser defaultArgParser else argParser;
  wrapped = pkgs.writeShellApplication {
    inherit name runtimeInputs;
    bashOptions = [
      "errexit"
      "pipefail"
    ];
    text = ''
      ${argParser'}

      if [[ $BF_NO_WRAPPER == "1" ]]; then
        exec ${executable} "$@"
      fi

      # Set up MacOS SDK environment variables, if configured.
      ${exportEnv (
        optionalAttrs (macos.sdk != null) (
          let
            versions = (importJSON (macos.sdk + "/SDKSettings.json")).SupportedTargets.macosx;
          in
          {
            BF_MACOS_SDK_PATH = macos.sdk;
            BF_MACOS_SDK_MINIMUM_VERSION = versions.MinimumDeploymentTarget;
            BF_MACOS_SDK_DEFAULT_VERSION = versions.DefaultDeploymentTarget;
          }
        )
      )}

      # Set up Windows SDK, based on 'windows.mkSdk' builder.
      export BF_WINDOWS_SDK_PATH="${windowsSdk}"

      # Base environment for all targets.
      export PKG_CONFIG_ALLOW_CROSS="1"
      export LIBCLANG_PATH="${pkgs.libclang.lib}/lib";
      export LIBRARY_PATH="${pkgs.libiconv}/lib";
      ${exportEnv sharedEnvironment}

      case $BF_TARGET in
        "")
          ${exportEnv (
            devEnvironment
            // {
              PKG_CONFIG_PATH =
                (devEnvironment.PKG_CONFIG_PATH or "")
                + makeSearchPath "lib/pkgconfig" (map (p: p.dev or null) (runtimeInputsBase ++ extraRuntimeInputs));
              RUSTFLAGS =
                (devEnvironment.RUSTFLAGS or "")
                + optionalString (pkgs.stdenv.isLinux) "-C link-args=-Wl,-rpath,${
                  makeSearchPath "lib" (runtimeInputsBase ++ extraRuntimeInputs)
                }";
            }
          )}
        ;;

        ${concatStringsSep "\n" (
          mapAttrsToList (target: env: ''
            ${target}*)
            ${exportEnv (
              env
              // {
                RUSTFLAGS =
                  (env.RUSTFLAGS or "")
                  + optionalString (crossPlatformRustflags != [ ]) (
                    " " + (concatStringsSep " " crossPlatformRustflags)
                  );
              }
            )}
            ;;
          '') targetEnvironments
        )}
      esac

      ${prePostScript}

      ${postScript}

      exec ${executable} "$@"
    '';
  };
in
(
  if (symlinkPackage == null) then
    wrapped
  else
    pkgs.symlinkJoin {
      inherit name;
      ignoreCollisions = true;
      paths = [
        wrapped
        symlinkPackage
      ];
    }
)
// {
  inherit runtimeInputs;
  meta = {
    mainProgram = name;
    platforms = systems;
  };
}
