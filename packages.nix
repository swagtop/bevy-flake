{
  pkgs,
  config,
  applyIfFunction,
  reconfigure,
}:
let
  inherit (builtins)
    mapAttrs
    warn
    ;

  hostSystem = pkgs.stdenv.hostPlatform.system;

  applyConfig = import ./apply.nix { inherit pkgs; };

  appliedConfig = applyConfig config;

  wrapExecutable = import ./wrapper.nix appliedConfig {
    inherit pkgs applyIfFunction;
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
mapAttrs
  (
    name: value:
    value
    // {
      configure = newConfig: (reconfigure newConfig).packages.${hostSystem}.${name};
    }
  )
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

    targets = import ./build/targets.nix config {
      inherit
        pkgs
        appliedConfig
        wrapped-rust-toolchain
        ;
    };

    web = import ./build/web.nix config {
      inherit
        pkgs
        appliedConfig
        wrapped-rust-toolchain
        wrapped-bevy-cli
        ;
    };

    # Useful tools can be reached through this package.
    tools =
      pkgs.writeShellScriptBin "tools" ''
        echo
        echo "This package contains some tools to be run, and a function to "
        echo "wrap your own programs with the bevy-flake wrapper script."
        echo
        echo "In Nix, use 'tools.wrapExecutable { /* ... */ }' to wrap programs."
        echo
        echo "In your shell, run 'nix run github:swagtop/bevy-flake#tools.<tool>' to use the following tools:"
        echo
        echo "package-macos-sdk:"
        printf "  Call with the first argument being the 'Xcode.app' you want "
        printf "to package the MacOS SDK from.\n  Get more info about this "
        printf "from the bevy-flake docs.\n"
        echo
        echo "package-windows-sdk:"
        printf "  Call with no arguments to fetch the Windows MSVC SDK found "
        printf "in configured 'pkgs'.\n"
        echo
      ''
      // {
        inherit wrapExecutable;
        package-macos-sdk = pkgs.callPackage (import ./tools/package-macos-sdk.nix) { };
        package-windows-sdk = pkgs.callPackage (import ./tools/package-windows-sdk.nix) { };
      };
  }
