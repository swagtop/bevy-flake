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

  buildSource,
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
    ;

  exportEnv =
    env: concatStringsSep "\n" (mapAttrsToList (name: val: "export ${name}=\"${val}\"") env);

  optionalPkgs = input: if isFunction input then input pkgs else input;

  # Letting users optionally reference 'pkgs', for the following 5 configs:
  final = {
    crossPlatformRustflags = optionalPkgs crossPlatformRustflags;
    sharedEnvironment = optionalPkgs sharedEnvironment;
    devEnvironment = optionalPkgs devEnvironment;
    targetEnvironments = optionalPkgs targetEnvironments;
    prePostScript = optionalPkgs prePostScript;
  };

  targets = (attrNames final.targetEnvironments);
  # Users need to reference 'pkgs' in the following 3 configs:
  input-rust-toolchain = mkRustToolchain targets pkgs;
  runtimeInputsBase = mkRuntimeInputs pkgs;
  stdenv = mkStdenv pkgs;

  windowsSdk = pkgs.symlinkJoin {
    name = "merged-windows-sdk";
    paths = [
      pkgs.pkgsCross.aarch64-windows.windows.sdk
      pkgs.pkgsCross.x86_64-windows.windows.sdk
    ];
  };

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
  inherit
    input-rust-toolchain
    runtimeInputsBase
    stdenv
    ;
  inherit (final)
    crossPlatformRustflags
    sharedEnvironment
    devEnvironment
    targetEnvironments
    prePostScript
    ;

  __functor =
    _:
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

          # Set up MacOS SDK if configured.
          export BF_MACOS_SDK_PATH="${if (macos.sdk != null) then macos.sdk else ""}"

          export BF_WINDOWS_SDK_PATH="${windowsSdk}"

          # Base environment for all targets.
          export PKG_CONFIG_ALLOW_CROSS="1"
          export LIBCLANG_PATH="${pkgs.libclang.lib}/lib";
          export LIBRARY_PATH="${pkgs.libiconv}/lib";
          ${exportEnv final.sharedEnvironment}

          case $BF_TARGET in
            "")
              ${exportEnv (
                final.devEnvironment
                // {
                  PKG_CONFIG_PATH =
                    (final.devEnvironment.PKG_CONFIG_PATH or "")
                    + makeSearchPath "lib/pkgconfig" (map (p: p.dev or null) (runtimeInputsBase ++ extraRuntimeInputs));
                  RUSTFLAGS =
                    (final.devEnvironment.RUSTFLAGS or "")
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
                      + optionalString (final.crossPlatformRustflags != [ ]) (
                        " " + (concatStringsSep " " final.crossPlatformRustflags)
                      );
                  }
                )}
                ;;
              '') final.targetEnvironments
            )}
          esac

          ${final.prePostScript}

          ${postScript}

          exec ${executable} "$@"
        '';
      };
    in
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
      };
}
