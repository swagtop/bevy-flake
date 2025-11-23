{
  systems,

  linux,
  windows,
  macos,

  crossPlatformRustflags,

  sharedEnvironment,
  devEnvironment,
  targetEnvironments,
  prePostScript,

  rustToolchainFor,
  runtimeInputs,
  stdenv,

  src,
}:

pkgs:

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
  input-rust-toolchain = rustToolchainFor targets;

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
  totalRuntimeInputs =
    runtimeInputs
    ++ extraRuntimeInputs
    ++ [
      stdenv.cc
      input-rust-toolchain
      pkgs.pkg-config
    ];
  argParser' = if (isFunction argParser) then argParser defaultArgParser else argParser;
  wrapped = pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = totalRuntimeInputs;
    bashOptions = [
      "errexit"
      "pipefail"
    ];
    text = ''
      ${argParser'}

      if [[ $BF_NO_WRAPPER == "1" ]]; then
        exec ${executable} "$@"
      fi

      # Base environment for all targets.
      ${exportEnv (
        (
          {
            PKG_CONFIG_ALLOW_CROSS = "1";
            LIBCLANG_PATH = pkgs.libclang.lib + "/lib";
            LIBRARY_PATH = pkgs.libiconv + "/lib";

            # Set up Windows SDK.
            BF_WINDOWS_SDK_PATH = windows.sdk;
          }
          // optionalAttrs (macos.sdk != null) (
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
        )
        // sharedEnvironment
      )}

      case $BF_TARGET in
        "")
          ${exportEnv (
            devEnvironment
            // {
              PKG_CONFIG_PATH =
                (devEnvironment.PKG_CONFIG_PATH or "")
                + makeSearchPath "lib/pkgconfig" (map (p: p.dev or null) (runtimeInputs ++ extraRuntimeInputs));
              RUSTFLAGS =
                (devEnvironment.RUSTFLAGS or "")
                + optionalString (pkgs.stdenv.isLinux) "-C link-args=-Wl,-rpath,${
                  makeSearchPath "lib" (runtimeInputs ++ extraRuntimeInputs)
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
