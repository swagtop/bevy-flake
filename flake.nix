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
      # "-Zfmt-debug=none"
    ];

    compileTimePackages = with pkgs; [
      alsa-lib.dev
      clang
      libxkbcommon
      llvm
      pkg-config
      udev.dev
      wayland
    ];

    # Packages specifically for compiling to aarch64-unknown-linux-gnu.
    aarch64 = with pkgs.pkgsCross.aarch64-multiplatform; [
      alsa-lib.dev
      udev.dev
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
      # Set up MacOS cross-compilation environment if SDK is in inputs.
      ${if (inputs ? mac-sdk) then macCrossCompilationEnvironment else ""}

      # Stops 'blake3' from messing up.
      export CARGO_FEATURE_PURE=1 

      # Check if cargo is being run with '--target', or '--no-wrapper'.
      ARG_COUNT=0
      for arg in "$@"; do
        ARG_COUNT=$(expr "$ARG_COUNT" + 1)

        # If run with --target, save the arg number of the arch specified.
        if [ "$arg" = '--target' ]; then
          TARGET_ARCH_ARG_COUNT=$(expr "$ARG_COUNT" + 1)

        elif [ "$arg" = '--no-wrapper' ]; then
          # Remove '-no-wrapper' from prompt.
          set -- $(printf '%s\n' "$@" | grep -vx -- '--no-wrapper')
          # Run 'cargo' with no checks.
          exec ${rust-toolchain}/bin/cargo "$@"
        fi
      done

      # Change environment based on target, if one is supplied.
      if [ "$TARGET_ARCH_ARG_COUNT" != "" ]; then
        TARGET_ARCH=''${!TARGET_ARCH_ARG_COUNT}
        case $TARGET_ARCH in

          # Targets using `cargo-zigbuild`
          *-unknown-linux-gnu|*pc--windows-gnu*|*-apple-darwin|wasm32-*)
            if [ "$1" = 'build' ]; then
              echo "bevy-flake: Aliasing 'build' to 'zigbuild'" >&2 
              shift
              set -- "zigbuild" "$@"
            fi
            if [ "$arg" = 'aarch64-unknown-linux-gnu' ]; then
              PKG_CONFIG_PATH="${lib.makeSearchPath "lib/pkgconfig" aarch64}"
            elif [ "$arg" = 'x86_64-pc-windows-gnu' ]; then
              PATH="${pkgs.pkgsCross.mingwW64.stdenv.cc}/bin:$PATH"
            fi;;

          # Targets using `cargo-xwin`
          *-pc-windows-msvc)
            if [ "$1" = 'build' ]; then
              echo "bevy-flake: Aliasing 'build' to 'xwin build'" >&2 
              set -- "xwin" "$@"
            fi
            if [ "$arg" = 'x86_64-pc-windows-msvc' ]; then
              RUSTFLAGS="-L ${pkgs.pkgsCross.mingwW64.windows.mingw_w64}/lib $RUSTFLAGS"
            fi;;

        esac

        # Prevent that 'cargo run' from running with a target.
        if [ "$1" = 'run' ]; then
          echo "bevy-flake: Cannot use 'cargo run' with a '--target'"
          exit 1
        fi

        # Add 'crossFlags' to environment
        RUSTFLAGS="${crossFlags} $RUSTFLAGS"

      # If no target is supplied, add 'localFlags' to environment.
      else
        if [ "$1" = 'zigbuild' ] || [ "$1" = 'xwin' ]; then
          echo "bevy-flake: Cannot use 'cargo $1' without a '--target'"
          exit 1
        elif [ "$1" = 'run' ] || [ "$1" = 'build' ]; then
          RUSTFLAGS="${localFlags} $RUSTFLAGS"
        fi
      fi

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
