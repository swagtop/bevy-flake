{
  description = "A NixOS development flake for Bevy development.";
  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-unstable";
    rust-overlay = {
      url = "git+https://github.com/oxalica/rust-overlay?ref=master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, rust-overlay, nixpkgs, ... }@inputs:
  let
    system = "x86_64-linux";
    overlays = [ (import rust-overlay) ];
    pkgs = import nixpkgs { inherit system overlays; };
    aarch64-pkgs = import nixpkgs {
      inherit overlays;
      system = "aarch64-linux";
    };
    lib = pkgs.lib;

    rust-toolchain = pkgs.rust-bin.nightly.latest.default.override {
      extensions = [ "rust-src" "rust-analyzer" ];
      targets = [
        # WASM target.
        "wasm32-unknown-unknown"
        # Linux targets.
        "aarch64-unknown-linux-gnu"
        "x86_64-unknown-linux-gnu"
        # Windows targets.
        "aarch64-pc-windows-msvc"
        "x86_64-pc-windows-msvc"
      ] ++ lib.optionals (inputs ? mac-sdk) [
        # MacOS targets (...if SDK is available).
        "aarch64-apple-darwin"
        "x86_64-apple-darwin"
      ];
    };

    shellPackages = with pkgs; [
      # mold
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
      # "-C target-cpu=native"
      # "-C link-arg=-fuse-ld=mold"
    ];

    crossFlags = lib.concatStringsSep " " [
      "-Zlinker-features=-lld"
      # "--remap-path-prefix=\${HOME}=/build"
      # "-Zlocation-detail=none"
    ];

    compileTimePackages = with pkgs; [
      # The wrapper, linkers, compilers, and pkg-config.
      cargo-wrapper
      cargo-zigbuild
      cargo-xwin
      rust-toolchain
      pkg-config
      # Headers for x86_64-unknown-linux-gnu.
      alsa-lib.dev
      libxkbcommon.dev
      udev.dev
      wayland.dev
    ];

    # Headers for aarch64-unknown-linux-gnu.
    aarch64LinuxHeaders = (lib.makeSearchPath "lib/pkgconfig"
      (with aarch64-pkgs; [
        alsa-lib.dev
        udev.dev
        wayland.dev
    ]));

    # Environment variables for the MacOS targets.
    macEnvironment =
      let
        frameworks = "${inputs.mac-sdk}/System/Library/Frameworks";
      in ''
        export COREAUDIO_SDK_PATH="${frameworks}/CoreAudio.framework/Headers"
        export BINDGEN_EXTRA_CLANG_ARGS="${lib.concatStringsSep " " [
          "--sysroot=${inputs.mac-sdk}"
          "-F ${frameworks}"
          "-I${inputs.mac-sdk}/usr/include"
        ]}"
        RUSTFLAGS="${lib.concatStringsSep " " [
          "-L ${inputs.mac-sdk}/usr/lib"
          "-L framework=${frameworks}"
          "${crossFlags}"
          "$RUSTFLAGS"
        ]}"
    '';

    # Wrapping 'cargo', to adapt the environment to context of compilation.
    cargo-wrapper = pkgs.writeShellScriptBin "cargo" ''
      # Check if cargo is being run with '--target', or '--no-wrapper'.
      ARG_COUNT=0
      for arg in "$@"; do
        ARG_COUNT=$((ARG_COUNT + 1))
        case $arg in
          --target)
            # Save next arg as target.
            eval "BEVY_FLAKE_TARGET=\$$((ARG_COUNT + 1))"
          ;;
          --no-wrapper)
            # Remove '--no-wrapper' from args, run cargo without changed env.
            set -- $(printf '%s\n' "$@" | grep -vx -- '--no-wrapper')
            exec ${rust-toolchain}/bin/cargo "$@"
          ;;
        esac
      done

      if [ "$1" = 'run' ] && [ "$BEVY_FLAKE_TARGET" != "" ]; then
        echo "bevy-flake: Cannot use 'cargo run' with a '--target'"
        exit 1
      fi

      # Stops 'blake3' from messing up.
      export CARGO_FEATURE_PURE=1 
      # Needed for the MacOS target, and many non-bevy crates.
      export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"

      case $BEVY_FLAKE_TARGET in
        # No target means local system, sets localFlags if running or building.
        "")
          if [ "$1" = 'zigbuild' ] || [ "$1 $2" = 'xwin build' ]; then
            echo "bevy-flake: Cannot use '"cargo $@"' without a '--target'"
            exit 1
          elif [ "$1" = 'run' ] || [ "$1" = 'build' ]; then
            RUSTFLAGS="${localFlags} $RUSTFLAGS"
          fi
        ;;

        # Targets using `cargo-zigbuild`
        aarch64-unknown-linux-gnu*)
          PKG_CONFIG_PATH="${aarch64LinuxHeaders}:$PKG_CONFIG_PATH"
        ;&
        x86_64-unknown-linux-gnu*|wasm32-unknown-unknown)
          RUSTFLAGS="${crossFlags} $RUSTFLAGS"
          if [ "$1" = 'build' ]; then
            echo "bevy-flake: Aliasing 'build' to 'zigbuild'" 1>&2 
            shift
            set -- "zigbuild" "$@"
          fi
        ;;
        *-apple-darwin)
          # Set up MacOS cross-compilation environment if SDK is in inputs.
          ${if (inputs ? mac-sdk) then macEnvironment else "# None found."}
          if [ "$1" = 'build' ]; then
            echo "bevy-flake: Aliasing 'build' to 'zigbuild'" 1>&2 
            shift
            set -- "zigbuild" "$@"
          fi
        ;;

        # Targets using `cargo-xwin`
        *-pc-windows-msvc)
          RUSTFLAGS="${crossFlags} $RUSTFLAGS"
          if [ "$1" = 'build' ]; then
            echo "bevy-flake: Aliasing 'build' to 'xwin build'" 1>&2 
            set -- "xwin" "$@"
          fi
        ;;
      esac

      # Run cargo with relevant RUSTFLAGS.
      RUSTFLAGS=$RUSTFLAGS exec ${rust-toolchain}/bin/cargo "$@"
    '';
  in {
    devShells.${system}.default = pkgs.mkShell {
      name = "bevy-flake";

      packages = shellPackages;
      nativeBuildInputs = compileTimePackages;
    };
  };
}
