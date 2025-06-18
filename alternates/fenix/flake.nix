{
  description = "A flake for Bevy development on NixOS.";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, fenix, nixpkgs, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    lib = pkgs.lib;
    fx = fenix.packages.${system};

    rust-toolchain = fx.combine ([
      fx.complete.toolchain
    ] ++ map (target: fx.targets.${target}.latest.rust-std) ([
      "wasm32-unknown-unknown"
      "aarch64-unknown-linux-gnu"
      "x86_64-unknown-linux-gnu"
      "aarch64-pc-windows-msvc"
      "x86_64-pc-windows-msvc"
    ] ++ lib.optionals (inputs ? mac-sdk) [
      "aarch64-apple-darwin"
      "x86_64-apple-darwin"
    ]));

    shellPackages = with pkgs; [
      # mold
    ];

    localFlags = lib.concatStringsSep " " [
      "-C link-args=-Wl,-rpath,${lib.makeLibraryPath
        (with pkgs; [
          # Audio
          alsa-lib-with-plugins
          # Graphics libraries
          libGL
          vulkan-loader
          # IO
          libxkbcommon
          udev
          # Xorg
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
      alsa-lib-with-plugins.dev
      libxkbcommon.dev
      udev.dev
      wayland.dev
    ];

    # Headers for aarch64-unknown-linux-gnu.
    aarch64LinuxHeaders = (lib.makeSearchPath "lib/pkgconfig"
      (with (import nixpkgs { system = "aarch64-linux"; }); [
        alsa-lib-with-plugins.dev
        udev.dev
        wayland.dev
      ])
    );

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

      # Make sure first argument of 'cargo' is correct for target.
      case $BEVY_FLAKE_TARGET in
        *-unknown-linux-gnu*);&
        *-apple-darwin);&
        wasm32-unknown-unknown)
          if [ "$1" = 'build' ]; then
            echo "bevy-flake: Aliasing 'build' to 'zigbuild'" 1>&2 
            shift
            set -- "zigbuild" "$@"
          fi
        ;;
        *-pc-windows-msvc)
          if [ "$1" = 'build' ] || [ "$1" = 'run' ]; then
            echo "bevy-flake: Aliasing '$1' to 'xwin $1'" 1>&2 
            set -- "xwin" "$@"
          fi
        ;;
      esac

      # Environment variables for all targets.
      ## Stops 'blake3' from messing up.
      export CARGO_FEATURE_PURE=1
      ## Needed for MacOS target, and many non-bevy crates.
      export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"

      # Set final environment variables based on target.
      case $BEVY_FLAKE_TARGET in
        # No target means local system, sets localFlags if running or building.
        "")
          if [ "$1" = 'zigbuild' ] || [ "$1 $2" = 'xwin build' ]; then
            echo "bevy-flake: Cannot use 'cargo $@' without a '--target'"
            exit 1
          elif [ "$1" = 'run' ] || [ "$1" = 'build' ]; then
            RUSTFLAGS="${localFlags} $RUSTFLAGS"
          fi
        ;;

        aarch64-unknown-linux-gnu*)
          PKG_CONFIG_PATH="${aarch64LinuxHeaders}:$PKG_CONFIG_PATH"
          RUSTFLAGS="${crossFlags} $RUSTFLAGS"
        ;;
        x86_64-unknown-linux-gnu*|*-pc-windows-msvc)
          RUSTFLAGS="${crossFlags} $RUSTFLAGS"
        ;;
        wasm32-unknown-unknown)
          # Allows for 'rand' to be compiled.
          RUSTFLAGS="--cfg getrandom_backend=\"wasm_js\" $RUSTFLAGS"
          RUSTFLAGS="${crossFlags} $RUSTFLAGS"
        ;;
        *-apple-darwin)
          # Set up MacOS cross-compilation environment if SDK is in inputs.
          ${if (inputs ? mac-sdk) then macEnvironment else "# None found."}
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
