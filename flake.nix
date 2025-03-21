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
        "aarch64-unknown-linux-gnu"
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

    compileTimePackages = (with pkgs; [
      alsa-lib.dev
      clang
      libxkbcommon
      llvm
      pkg-config
      udev.dev
      wayland
    ]
    ++ (with pkgsCross.mingwW64; [
      # Windows packages.
      stdenv.cc
      windows.mingw_w64_pthreads
    ])
    );

    # Packages specifically for compiling to aarch64-unknown-linux-gnu.
    aarch64 = with pkgs.pkgsCross.aarch64-multiplatform; [
      alsa-lib.dev
      udev.dev
    ];

    # Wrapping 'cargo' in a function to prevent easy-to-make mistakes.
    cargoWrapper = pkgs.writeShellScriptBin "cargo" ''
      for arg in "$@"; do
        case $arg in

          # Targets using `cargo-zigbuild`
          *-unknown-linux-gnu|*-windows-gnullvm|*-apple-darwin)
            if [ "$1" = 'build' ]; then
              echo "bevy-flake: Aliasing 'build' to 'zigbuild'" >&2 
              shift
              set -- "zigbuild" "$@"
            fi
            if [ "$arg" = 'aarch64-unknown-linux-gnu' ]; then
              PKG_CONFIG_PATH=${lib.makeSearchPath "lib/pkgconfig" aarch64}
            fi
            BEVY_FLAKE_PROFILE=cross;;

          # Targets using `cargo-xwin`
          *-windows-msvc)
            if [ "$1" = 'build' ]; then
              echo "bevy-flake: Aliasing 'build' to 'xwin build'" >&2 
              set -- "xwin" "$@"
            fi
            BEVY_FLAKE_PROFILE=cross;;

          # Targets just using cargo.
          x86_64-pc-windows-gnu|wasm32-unknown-unknown)
            BEVY_FLAKE_PROFILE=cross;;

          --no-wrapper)
            # Remove '-no-wrapper' from prompt.
            set -- "$(printf '%s\n' "$@" | grep -vx -- '--no-wrapper')"
            # Run 'cargo' with no checks.
            ${rustToolchain}/bin/cargo "$@"
            exit $?;;

        esac
      done
      case $BEVY_FLAKE_PROFILE in

        "") # Target is NixOS if $PROFILE is unset.
          if [ "$1" = 'zigbuild' ] || [ "$1" = 'xwin' ]; then
            echo "bevy-flake: Cannot use 'cargo $1' without a '--target'"
            exit 1
          elif [ "$1" = 'run' ] || [ "$1" = 'build' ]; then
            BEVY_FLAKE_FLAGS="${localFlags}"
          fi;;

        cross)
          if [ "$1" = 'run' ]; then
            echo "bevy-flake: Cannot use 'cargo run' with a '--target'"
            exit 1
          fi
          BEVY_FLAKE_FLAGS="${crossFlags}";;

      esac
      RUSTFLAGS="$BEVY_FLAKE_FLAGS $RUSTFLAGS" ${rustToolchain}/bin/cargo "$@"
      exit $?
    '';
  in {
    devShells.${system}.default = pkgs.mkShell {
      name = "bevy-flake";

      packages = [ cargoWrapper ] ++ shellPackages;
      nativeBuildInputs = compileTimePackages;

      env = {
        # Stops blake3 from acting up.
        CARGO_FEATURE_PURE = "1";

      } // lib.optionalAttrs (inputs ? mac-sdk) rec {
        # Set up MacOS compilation environment, if SDK is available.
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
    };
  };
}
