{
  description = "A NixOS development flake for Bevy development.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, rust-overlay, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
      };
      lib = pkgs.lib;

      rustToolchain = pkgs.rust-bin.nightly.latest.default.override {
        extensions = [ "rust-src" "rust-analyzer" ];
        targets = [
          # WASM targets.
          "wasm32-unknown-unknown"
        ] ++ [
          # Linux targets.
          "x86_64-unknown-linux-gnu"
        ] ++ [
          # Windows targets.
          "aarch64-pc-windows-gnullvm"
          "aarch64-pc-windows-msvc"
          "x86_64-pc-windows-gnu"
          "x86_64-pc-windows-gnullvm"
          "x86_64-pc-windows-msvc"
        ] ++ lib.optionals (inputs ? mac-sdk) [
          # MacOS targets (...if SDK is available).
          "aarch64-apple-darwin"
          "x86_64-apple-darwin"
        ];
      };

      shellPackages = with pkgs; [
        cargo-xwin
        cargo-zigbuild
        rustToolchain
      ];

      localFlags = lib.concatStringsSep " " [
        "-C link-args=-Wl,-rpath,${lib.makeLibraryPath (with pkgs; [
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
        ++ lib.optionals (!(builtins.getEnv "NO_WAYLAND" == "1")) [ wayland ]
        )}"
      ];

      crossFlags = lib.concatStringsSep " " [
        # "-Zlocation-detail=none"
        # "-Zfmt-debug=none"
      ];

      compileTimePackages = with pkgs; [
        alsa-lib-with-plugins
        clang
        libxkbcommon
        llvm
        pkg-config
        udev
        wayland
      ];
    in {
      devShells.${system}.default = pkgs.mkShell rec {
        name = "bevy-flake";

        packages = [ cargoWrapper ] ++ shellPackages;
        nativeBuildInputs = compileTimePackages;
        flags = localFlags;

        env = {
          # Stops blake3 from acting up.
          CARGO_FEATURE_PURE = "1";

        # Set up MacOS compilation environment, if SDK is available.
        } // lib.optionalAttrs (inputs ? mac-sdk) rec {
          frameworks = "${inputs.mac-sdk}/System/Library/Frameworks";

          SDKROOT = "${inputs.mac-sdk}";
          COREAUDIO_SDK_PATH = "${frameworks}/CoreAudio.framework/Headers";
          LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";

          BINDGEN_EXTRA_CLANG_ARGS = lib.concatStringsSep " " [
            "--sysroot=${inputs.mac-sdk}"
            "-F ${frameworks}"
            "-I${inputs.mac-sdk}/usr/include"
          ];
        };

        # Wrapping 'cargo' in a function to prevent easy-to-make mistakes.
        cargoWrapper = pkgs.writeShellScriptBin "cargo" ''
          for arg in "$@"; do
            case $arg in

              x86_64-unknown-linux-gnu|*-windows-gnu*|*-apple-darwin)
                if [ "$1" = 'build' ]; then
                  echo "bevy-flake: Aliasing 'build' to 'zigbuild'" >&2 
                  shift
                  set -- "zigbuild" "$@"
                fi
                PROFILE=cross;;

              *-windows-msvc)
                if [ "$1" = 'build' ]; then
                  echo "bevy-flake: Aliasing 'build' to 'xwin build'" >&2 
                  set -- "xwin" "$@"
                fi
                PROFILE=cross;;

              wasm32-unknown-unknown)
                PROFILE=cross;;

              --no-wrapper)
                # Remove '-no-wrapper' from prompt.
                set -- $(printf '%s\n' "$@" | grep -vx -- '--no-wrapper')
                # Run 'cargo' with no checks.
                ${rustToolchain}/bin/cargo "$@"
                exit $?;;

            esac
          done
          case $PROFILE in

            "") # Target is NixOS if $PROFILE is unset.
              if [ "$1" = 'zigbuild' -o "$1" = 'xwin' ]; then
                echo "bevy-flake: Cannot use 'cargo $1' without a '--target'"
                exit 1
              elif [ "$1" = 'run' -o "$1" = 'build' ]; then
                PROFILE_FLAGS="${localFlags}"
              fi;;

            cross)
              if [ "$1" = 'run' ]; then
                echo "bevy-flake: Cannot use 'cargo run' with a '--target'"
                exit 1
              fi
              PROFILE_FLAGS="${crossFlags}";;

          esac
          RUSTFLAGS="$PROFILE_FLAGS $RUSTFLAGS" ${rustToolchain}/bin/cargo "$@"
          exit $?
        '';
      };
  };
}
