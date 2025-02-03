{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, flake-utils, rust-overlay, nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system: let
      overlays = [ (import rust-overlay) ];
      pkgs = import nixpkgs { inherit system overlays; };

      rustToolchain = pkgs.rust-bin.stable.latest.default.override {
        extensions = [ "rust-src" "rust-analyzer" ];
        targets = [
          "aarch64-apple-darwin"
          "x86_64-apple-darwin"

          "x86_64-unknown-linux-gnu"

          "x86_64-pc-windows-gnu"

          "wasm32-unknown-unknown"
        ];
      };

      # To compile to Apple targets, provide a link to a MacOSX*.sdk.tar.xz:
      appleSdkUrl = "";
      # ... and the sha-256 hash of said tarball. Just the hash, no 'sha-'.
      appleSdkHash = "";

      # Removes your username from the final binary, changes it to 'user'.
      anonymizeBuild = "--remap-path-prefix=/home/$USER=/home/user";

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

      nativeBuildInputsPackages = (with pkgs; [
        alsa-lib-with-plugins
        lld
        pkg-config
        udev
      ]
      ++ waylandPackages # <--- Keep, even if you're having Wayland issues.
      );

      runtimeLib = "${pkgs.lib.makeLibraryPath (with pkgs; [
        alsa-lib-with-plugins
        libGL
        libxkbcommon
        udev
        vulkan-loader
      ]
      ++ xorgPackages
      ++ waylandPackages # <--- Comment out if you're having Wayland issues.
      )}";
    in {
      devShells = {
        default = pkgs.mkShell {
          name = "bevy";

          packages = [ rustToolchain ];
          nativeBuildInputs = nativeBuildInputsPackages;

          shellHook = ''
            export RUSTFLAGS="${anonymizeBuild}"
            export RUSTFLAGS="-C target-cpu=native $RUSTFLAGS"
            export RUSTFLAGS="-C link-args=-Wl,-rpath,${runtimeLib} $RUSTFLAGS"
          '';
        };

        build = pkgs.mkShell rec {
          name = "bevy-build";

          packages = buildShellPackages;
          nativeBuildInputs = nativeBuildInputsPackages;

          # Try to fetch appleSdk, if URL and hash is provided.
          appleSdk = if appleSdkUrl != "" && appleSdkHash != "" then 
            builtins.fetchTarball { url = appleSdkUrl; sha256 = appleSdkHash; }
            else null;

          # Add appleSdk to env, if available.
          env = if appleSdk != null then rec {
            frameworks = "${appleSdk}/System/Library/Frameworks";

            SDKROOT = appleSdk;
            COREAUDIO_SDK_PATH = "${frameworks}/CoreAudio.framework/Headers";
            LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";

            BINDGEN_EXTRA_CLANG_ARGS = (
              "--sysroot=${appleSdk}"
            + " -F ${frameworks}"
            + " -I${appleSdk}/usr/include"
            );
          } else {};

          # Stops blake3 from acting up.
          CARGO_FEATURE_PURE = "1";

          # Prevents accidental linking to /nix/store items.
          LD_LIBRARY_PATH = "";
          shellHook = ''
            export RUSTFLAGS=${anonymizeBuild}
          '';
        };
      };
    }
  );
}
