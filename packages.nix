{
  pkgs,
  rawConfig,
  applyIfFunction,
  reconfigure,
}:
let
  inherit (builtins)
    mapAttrs
    warn
    ;

  hostSystem = pkgs.stdenv.hostPlatform.system;

  appliedConfig = import ./apply.nix rawConfig { inherit pkgs; };

  wrapExecutable = import ./wrapper.nix appliedConfig {
    inherit pkgs rawConfig applyIfFunction;
  };

  wrapped-rust-toolchain = wrapExecutable {
    name = "cargo";

    executable = "${appliedConfig.rustToolchain}/bin/cargo";

    symlinkPackage = appliedConfig.rustToolchain;

    passthru = {
      wrapExecutable = warn (
        "The 'rust-toolchain.wrapExecutable' attribute has moved to "
        + "'tools.wrapExecutable'. It will be removed from 'rust-toolchain' "
        + "at the date '2027-01-01'."
      ) wrapExecutable;

      unwrapped = appliedConfig.rustToolchain;

      # Attributes needed for 'makeRustPlatform' compatibility.
      targetPlatforms = appliedConfig.systems;
      badTargetPlatforms = [ ];
    };
  };

  wrapped-bevy-cli =
    let
      # For now we build 'bevy-cli' from source, as it is not in nixpkgs yet.
      bevy-cli-package = pkgs.rustPlatform.buildRustPackage (finalAttrs: {
        pname = "bevy-cli";
        version = "0.1.0-alpha.2";

        src = pkgs.fetchzip {
          url = "https://github.com/TheBevyFlock/bevy_cli/archive/refs/tags/cli-v${finalAttrs.version}.tar.gz";
          sha256 = "sha256:02p2c3fzxi9cs5y2fn4dfcyca1z8l5d8i09jia9h5b50ym82cr8l";
        };

        cargoLock.lockFile = "${finalAttrs.src}/Cargo.lock";

        doCheck = false;

        nativeBuildInputs = [
          pkgs.openssl.dev
          pkgs.pkg-config
        ];

        env.PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";

        meta.mainProgram = "bevy-cli";
      });
    in
    wrapExecutable {
      name = "bevy";

      executable = "${bevy-cli-package}/bin/bevy";

      extraRuntimeInputs = [
        pkgs.binaryen # Needed for WASM optimizations.
        pkgs.cargo-generate # Needed for 'bevy-cli' functionality.
      ];

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
      # Let users change the config on each individual package.
      configure = newConfig: (reconfigure newConfig).packages.${hostSystem}.${name};
    }
  )
  {
    rust-toolchain = wrapped-rust-toolchain;

    dioxus-cli = wrapExecutable {
      name = "dx";
      executable = "${pkgs.dioxus-cli}/bin/dx";
      extraRuntimeInputs = [
        # Need 'lld' for hot-reloading.
        pkgs.llvmPackages.bintools
      ];
    };

    bevy-cli = wrapped-bevy-cli;

    targets = import ./build/targets.nix appliedConfig {
      inherit pkgs wrapped-rust-toolchain;
    };

    web = import ./build/web.nix appliedConfig {
      inherit pkgs wrapped-rust-toolchain wrapped-bevy-cli;
    };

    # Useful tools can be reached through this package.
    tools =
      pkgs.writeShellScriptBin "tools" ''
        printf "\n${''
          This package contains some tools to be run, and a function to 
          wrap your own programs with the bevy-flake wrapper script.

          In Nix, use 'tools.wrapExecutable { /* ... */ }' to wrap programs.

          In your shell, run 'nix run github:swagtop/bevy-flake#tools.<tool>' to use the following tools:

          package-macos-sdk:
            Call with the first argument being the 'Xcode.app' you want to package the MacOS SDK from.
            Get more info about this from the bevy-flake docs.

          package-windows-sdk:
            Call with no arguments to fetch the Windows MSVC SDK found in configured 'pkgs'.
        ''}\n"
      ''
      // {
        inherit wrapExecutable appliedConfig;
        package-macos-sdk = pkgs.callPackage (import ./tools/package-macos-sdk.nix) { };
        package-windows-sdk = pkgs.callPackage (import ./tools/package-windows-sdk.nix) { };
      };
  }
