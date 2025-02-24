{
  description = "A NixOS development flake for Bevy development.";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, flake-utils, rust-overlay, nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system: let
      overlays = [ (import rust-overlay) ];
      pkgs = import nixpkgs { inherit system overlays; };
      lib = pkgs.lib;

      rustToolchain = pkgs.rust-bin.nightly.latest.default.override {
        extensions = [ "rust-src" "rust-analyzer" ];
        targets = [
          "aarch64-apple-darwin" "x86_64-apple-darwin"

          "x86_64-unknown-linux-gnu"

          "x86_64-pc-windows-gnu" "x86_64-pc-windows-gnullvm"

          "wasm32-unknown-unknown"
        ];
      };

      # To compile to MacOS, provide a URL to a MacOSX*.sdk.tar.xz:
      macSdkUrl = "";
      # ... and the sha-256 hash of said tarball. Just the hash, no 'sha-'.
      macSdkHash = "";

      developShellPackages = [
        rustToolchain
      ];

      buildShellPackages = with pkgs; [
        cargo-zigbuild
        clang
        rustToolchain
      ];

      xorgPackages = with pkgs; [
        xorg.libX11
        xorg.libXcursor
        xorg.libXi
        xorg.libXrandr
      ];

      waylandPackages = with pkgs; [
        libxkbcommon
        wayland
      ];

      compileTimePackages = (with pkgs; [
        alsa-lib-with-plugins
        pkg-config
        udev
      ]
      ++ waylandPackages # <--- Keep, even if you're having Wayland issues.
      );

      runtimePackages = (with pkgs; [
        alsa-lib-with-plugins
        libGL
        libxkbcommon
        udev
        vulkan-loader
      ]
      ++ xorgPackages
      ++ waylandPackages # <--- Comment out if you're having Wayland issues.
      );

      # Make '/path/to/lib:/path/to/another/lib' string from runtimePackages.
      rpathLibrary = "${lib.makeLibraryPath runtimePackages}";

      # Removes your username from the final binary, changes it to 'user'.
      removeUsername = "--remap-path-prefix=/home/$USER=/home/user";
    in rec {
      devShells = {
        default = devShells.develop;
        develop = pkgs.mkShell {
          name = "bevy-develop";

          packages = developShellPackages;
          nativeBuildInputs = compileTimePackages;
          buildInputs = runtimePackages;

          # Wrapping 'cargo' in a function to prevent easy-to-make mistakes.
          shellHook = ''
            cargo () {
              for arg in "$@"; do
                if [ "$arg" = '--target' ]; then
                  printf "bevy-flake: "
                  printf "Switch to the build shell to compile for target: "
                  echo "'nix develop .#build'"
                  return 1
                fi
              done
              command cargo "$@"
            }
            export LD_LIBRARY_PATH="${rpathLibrary}"
          '';
        };

        build = pkgs.mkShell rec {
          name = "bevy-build";

          packages = buildShellPackages;
          nativeBuildInputs = compileTimePackages;

          # Try to fetch appleSdk, if URL and hash is provided.
          macSdk = if macSdkUrl != "" && macSdkHash != "" then 
            builtins.fetchTarball { url = macSdkUrl; sha256 = macSdkHash; }
            else null;

          # Add appleSdk to env, if available.
          env = if macSdk != null then rec {
            frameworks = "${macSdk}/System/Library/Frameworks";

            SDKROOT = macSdk;
            COREAUDIO_SDK_PATH = "${frameworks}/CoreAudio.framework/Headers";
            LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";

            BINDGEN_EXTRA_CLANG_ARGS = (
              "--sysroot=${macSdk}"
            + " -F ${frameworks}"
            + " -I${macSdk}/usr/include"
            );
          } else {};

          # Stops blake3 from acting up.
          CARGO_FEATURE_PURE = "1";

          # Resets LD_LIBRARY_PATH, should it have been set elsewhere.
          LD_LIBRARY_PATH = "";

          # Wrapping 'cargo' in a function to prevent easy-to-make mistakes.
          shellHook = ''
            cargo () {
              for arg in "$@"; do
                if [ "$arg" = '--target' ]; then
                  COMPILING_TO_TARGET=1
                fi
              done
              case $1 in
                run)
                  printf "bevy-flake: Switch to the develop shell to run: "
                  echo "'nix develop'"
                  return 1;;
                build|zigbuild|xwin)
                  if [ "$COMPILING_TO_TARGET" != 1 ]; then
                    printf "bevy-flake: "
                    echo "Cannot compile in the build shell without a target"
                    return 1
                  fi
                  if [ "$1" = 'build' ]; then
                    echo "bevy-flake: Aliasing 'build' to 'zigbuild'" >&2 
                    shift
                    set -- "zigbuild" "$@"
                  fi;;
              esac
              command cargo "$@"
            }
            export RUSTFLAGS=${removeUsername}
          '';
        };
      };
    }
  );
}
