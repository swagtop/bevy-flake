{
  description = "A NixOS development flake for Bevy development.";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, flake-utils, rust-overlay, nixpkgs, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system: let
      overlays = [ (import rust-overlay) ];
      pkgs = import nixpkgs { inherit system overlays; };
      lib = pkgs.lib;

      rustToolchain = pkgs.rust-bin.nightly.latest.default.override {
        extensions = [ "rust-src" "rust-analyzer" ];
        targets = [
          "aarch64-apple-darwin"
          "x86_64-apple-darwin"
          "x86_64-unknown-linux-gnu"
          "x86_64-pc-windows-gnu"
          "x86_64-pc-windows-gnullvm"
          "wasm32-unknown-unknown"
        ];
      };

      shellPackages = with pkgs; [
        cargo-zigbuild
        clang
        rustToolchain
      ];

      localFlags = lib.concatStringsSep " " [
        "-C link-args=-Wl,-rpath,${lib.makeLibraryPath runtimePackages}"
      ];

      crossFlags = lib.concatStringsSep " " [
        # "-Zlocation-detail=none"
        # "-Zfmt-debug=none"
      ];

      compileTimePackages = with pkgs; [
        alsa-lib-with-plugins
        pkg-config
        udev
        libxkbcommon
        wayland
      ];

      runtimePackages = (with pkgs; [
        alsa-lib-with-plugins
        libGL
        libxkbcommon
        udev
        vulkan-loader
        xorg.libX11
        xorg.libXcursor
        xorg.libXi
        xorg.libXrandr
      ]
      ++ [ wayland ] # <--- Comment out if you're having Wayland issues. 
      );
    in {
      devShells = {
        default = pkgs.mkShell rec {
          name = "bevy-flake";

          packages = [ cargoWrapper ] ++ shellPackages;
          nativeBuildInputs = compileTimePackages;

          # Add macSdk to env, if available.
          env = if inputs ? macSdk then rec {
            frameworks = "${inputs.macSdk}/System/Library/Frameworks";

            SDKROOT = "${inputs.macSdk}";
            COREAUDIO_SDK_PATH = "${frameworks}/CoreAudio.framework/Headers";
            LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";

            BINDGEN_EXTRA_CLANG_ARGS = (
              "--sysroot=${inputs.macSdk}"
            + " -F ${frameworks}"
            + " -I${inputs.macSdk}/usr/include"
            );
          } else {};

          # Stops blake3 from acting up.
          CARGO_FEATURE_PURE = "1";

          # Resets LD_LIBRARY_PATH, should it have been set elsewhere.
          LD_LIBRARY_PATH = "";

          # Wrapping 'cargo' in a function to prevent easy-to-make mistakes.
          cargoWrapper = pkgs.writeShellScriptBin "cargo" ''
            #!/bin/sh
            for arg in "$@"; do
              case $arg in
                "--target")
                  TARGETING=Cross;;
                "--no-wrapper")
                  # Remove '-no-wrapper' from prompt.
                  set -- $(printf '%s\n' "$@" | grep -vx -- '--no-wrapper')
                  # Run 'cargo' with no checks.
                  ${rustToolchain}/bin/cargo "$@"
                  exit $?;;
              esac
            done
            case $TARGETING in
              "") # Local
                if [ "$1" = 'zigbuild' -o "$1" = 'xwin' ]; then
                  echo "bevy-flake: Cannot use 'cargo $1' without a '--target'"
                  exit 1
                elif [ "$1" = 'run' -o "$1" = 'build' ]; then
                  CONTEXT="${localFlags}"
                fi;;
              "Cross")
                if [ "$1" = 'run' ]; then
                  echo "bevy-flake: Cannot use 'cargo run' with a '--target'"
                  exit 1
                elif [ "$1" = 'build' ]; then
                  echo "bevy-flake: Aliasing 'build' to 'zigbuild'" >&2 
                  shift
                  set -- "zigbuild" "$@"
                fi
                CONTEXT="${crossFlags} --remap-path-prefix=$HOME=/bevy";;
            esac
            RUSTFLAGS="$CONTEXT $RUSTFLAGS" ${rustToolchain}/bin/cargo "$@"
            exit $?
          '';
        };
      };
    }
  );
}
