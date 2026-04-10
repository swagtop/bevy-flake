{
  pkgs,
  config,
  assembleConfigs,
  applyIfFunction,
  reconfigure,
  defaultFlake,
}:
let
  inherit (builtins)
    warn
    ;

  hostSystem = pkgs.stdenv.hostPlatform.system;

  applyConfig = import ./apply.nix { inherit pkgs; };

  appliedConfig = applyConfig config;

  wrapExecutable = import ./wrapper.nix {
    inherit
      pkgs
      applyConfig
      assembleConfigs
      applyIfFunction
      appliedConfig
      ;
    rawConfig = config;
  };

  wrapped-rust-toolchain = wrapExecutable {
    name = "cargo";
    executable = appliedConfig.rustToolchain + "/bin/cargo";
    symlinkPackage = appliedConfig.rustToolchain;
    passthru = {
      wrapExecutable = warn "'wrapExecutable' is being moved to 'tools.wrapExecutable'" wrapExecutable;
      unwrapped = appliedConfig.rustToolchain;

      # Attributes needed for 'makeRustPlatform' compatibility.
      targetPlatforms = appliedConfig.systems;
      badTargetPlatforms = [ ];
    };
  };

  wrapped-bevy-cli =
    let
      bevy-cli-package = pkgs.rustPlatform.buildRustPackage (
        let
          version = "0.1.0-alpha.2";
          src = fetchTarball {
            url = "https://github.com/TheBevyFlock/bevy_cli/archive/refs/tags/cli-v${version}.tar.gz";
            sha256 = "sha256:02p2c3fzxi9cs5y2fn4dfcyca1z8l5d8i09jia9h5b50ym82cr8l";
          };
        in
        {
          inherit version src;
          name = "bevy-cli-${version}";
          nativeBuildInputs = [
            pkgs.openssl.dev
            pkgs.pkg-config
          ];
          PKG_CONFIG_PATH = pkgs.openssl.dev + "/lib/pkgconfig";
          cargoLock.lockFile = src + "/Cargo.lock";
          doCheck = false;
        }
      );
    in
    wrapExecutable {
      name = "bevy";
      extraRuntimeInputs = [
        pkgs.binaryen
        pkgs.cargo-generate
      ];
      executable = bevy-cli-package + "/bin/bevy";
      argParser =
        default:
        default
        + ''
          if [[ $2 == "web" ]]; then
            export BF_TARGET="wasm32-unknown-unknown"
          fi
        '';
    };
in
{
  rust-toolchain = wrapped-rust-toolchain;

  dioxus-cli = wrapExecutable {
    name = "dx";
    executable = pkgs.dioxus-cli + "/bin/dx";
    extraRuntimeInputs = [
      # Need 'lld' for hot-reloading.
      pkgs.llvmPackages.bintools
    ];
  };

  # For now we build 'bevy-cli' from source, as it is not in nixpkgs yet.
  bevy-cli = wrapped-bevy-cli;

  # Useful tools can be reached through this package.
  tools =
    pkgs.writeShellScriptBin "tools" ''
      echo "bevy-flake:"
      echo "Lorem ipsum dolor sit amet"
      echo "Lorem ipsum dolor sit amet"
      echo "Lorem ipsum dolor sit amet"
    ''
    // {
      inherit wrapExecutable;
      package-macos-sdk = pkgs.callPackage (import ./tools/package-macos-sdk.nix) { };
      package-windows-sdk = pkgs.callPackage (import ./tools/package-windows-sdk.nix) { };
    };
}
# If 'src' is defined in config, add the 'targets' package, which builds
# every target defined in 'targetEnvironments'. Individual targets can be built
# from 'targets.<target>', eg. 'targets.wasm32-unknown-unknown'.
// {
  targets = {
    configure = newConfig: (reconfigure newConfig).packages.${hostSystem}.web;
  }
  // import ./build/targets.nix {
    inherit
      pkgs
      appliedConfig
      reconfigure
      wrapped-rust-toolchain
      ;
  } config;

  web = {
    configure = newConfig: (reconfigure newConfig).packages.${hostSystem}.targets;
  }
  // import ./build/web.nix {
    inherit
      pkgs
      appliedConfig
      reconfigure
      wrapped-rust-toolchain
      wrapped-bevy-cli
      ;
  } config;
}
