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
    overlays = [ (import rust-overlay) ];
    pkgs = import nixpkgs { inherit system overlays; };
    lib = pkgs.lib;

    rust-toolchain = pkgs.rust-bin.nightly."2025-03-02".default.override {
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
      rust-toolchain
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
      # "--remap-path-prefix=\${HOME}=/build"
      # "-Zlocation-detail=none"
    ];

    compileTimePackages = with pkgs; [
      alsa-lib.dev
      clang
      libxkbcommon.dev
      llvm
      pkg-config
      udev.dev
      wayland.dev
    ];

    # Packages specifically for compiling to aarch64-unknown-linux-gnu.
    aarch64 = with pkgs.pkgsCross.aarch64-multiplatform; [
      alsa-lib.dev
      udev.dev
      wayland.dev
    ];

    # Environment variables for the MacOS targets.
    macCrossCompilationEnvironment =
    let
      frameworks = "${inputs.mac-sdk}/System/Library/Frameworks";
    in ''
      export SDKROOT="${inputs.mac-sdk}"
      export COREAUDIO_SDK_PATH="${frameworks}/CoreAudio.framework/Headers"
      export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"

      export BINDGEN_EXTRA_CLANG_ARGS="${lib.concatStringsSep " " [
        "--sysroot=${inputs.mac-sdk}"
        "-F ${frameworks}"
        "-I${inputs.mac-sdk}/usr/include"
      ]}"
    '';

    # Wrapping 'cargo', to adapt the environment to context of compilation.
    cargo-wrapper = pkgs.writeShellScriptBin "cargo" ''
      # Check if cargo is being run with '--target', or '--no-wrapper'.
      ARG_COUNT=0
      for arg in "$@"; do
        ARG_COUNT=$((ARG_COUNT + 1))

        # If run with --target, save the arg number of the arch specified.
        if [ "$arg" = '--target' ]; then
          eval "BEVY_FLAKE_TARGET_ARCH=\$$((ARG_COUNT + 1))"

        elif [ "$arg" = '--no-wrapper' ]; then
          # Remove '-no-wrapper' from prompt.
          set -- $(printf '%s\n' "$@" | grep -vx -- '--no-wrapper')
          # Run 'cargo' with no checks.
          exec ${rust-toolchain}/bin/cargo "$@"
        fi
      done

      # Stops 'blake3' from messing up.
      export CARGO_FEATURE_PURE=1 

      # Set up MacOS cross-compilation environment if SDK is in inputs.
      ${if (inputs ? mac-sdk) then macCrossCompilationEnvironment else ""}

      if [ "$BEVY_FLAKE_TARGET_ARCH" = "" ]; then
        # If no target is supplied, add 'localFlags' to RUSTFLAGS.
        case $1 in

          zigbuild|xwin)
            echo "bevy-flake: Cannot use 'cargo $1' without a '--target'"
            exit 1;;

          run|build)
            RUSTFLAGS="${localFlags} $RUSTFLAGS";;

        esac
      else
        # If target is supplied, adapt environment to target arch.
        case $BEVY_FLAKE_TARGET_ARCH in

          # Targets using `cargo-zigbuild`
          *-unknown-linux-gnu|*pc-windows-gnu*|*-apple-darwin|wasm32-*)
            if [ "$1" = 'build' ]; then
              echo "bevy-flake: Aliasing 'build' to 'zigbuild'" 1>&2 
              shift
              set -- "zigbuild" "$@"
            fi
            if [ "$BEVY_FLAKE_TARGET_ARCH " = 'aarch64-unknown-linux-gnu' ]; then
              PKG_CONFIG_PATH="${lib.makeSearchPath "lib/pkgconfig" aarch64}"
            elif [ "$BEVY_FLAKE_TARGET_ARCH " = 'x86_64-pc-windows-gnu' ]; then
              PATH="${pkgs.pkgsCross.mingwW64.stdenv.cc}/bin:$PATH"
            fi;;

          # Targets using `cargo-xwin`
          *-pc-windows-msvc)
            if [ "$1" = 'build' ]; then
              echo "bevy-flake: Aliasing 'build' to 'xwin build'" 1>&2 
              set -- "xwin" "$@"
            fi
            if [ "$BEVY_FLAKE_TARGET_ARCH " = 'x86_64-pc-windows-msvc' ]; then
              RUSTFLAGS="-L ${pkgs.pkgsCross.mingwW64.windows.mingw_w64}/lib $RUSTFLAGS"
            fi;;

        esac

        # Prevents 'cargo run' from being input with a target.
        if [ "$1" = 'run' ]; then
          echo "bevy-flake: Cannot use 'cargo run' with a '--target'"
          exit 1
        fi

        # When using target, add 'crossFlags' to RUSTFLAGS
        RUSTFLAGS="${crossFlags} $RUSTFLAGS"
      fi

      # Run cargo with relevant RUSTFLAGS.
      RUSTFLAGS=$RUSTFLAGS exec ${rust-toolchain}/bin/cargo "$@"
    '';
  in {
    devShells.${system}.default = pkgs.mkShell {
      name = "bevy-flake";

      packages = [ cargo-wrapper ] ++ shellPackages;
      nativeBuildInputs = compileTimePackages;
    };
  };
}
