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
    mingwW64 = pkgs.pkgsCross.mingwW64;
    aarch64-multiplatform = pkgs.pkgsCross.aarch64-multiplatform;

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
      # "-C target-cpu=native"
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

    rustFlags = {
      wasm32 = "${lib.concatStringsSep " " [
        "${crossFlags}"
      ]}";
      x86_64Linux = "${lib.concatStringsSep " " [
        "-C link-args=-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2"
        "${crossFlags}"
      ]}";
      aarch64Linux = "${lib.concatStringsSep " " [
        "-C link-args=-Wl,--dynamic-linker=/lib64/ld-linux-aarch64.so.1"
        "-C linker=${aarch64-multiplatform.stdenv.cc}/bin/aarch64-unknown-linux-gnu-gcc"
        "${crossFlags}"
      ]}";
      x86_64Windows = "${lib.concatStringsSep " " [
        "-L ${mingwW64.windows.mingw_w64}/lib"
        "${crossFlags}"
      ]}";
      aarch64Windows = "${lib.concatStringsSep " " [
        "${crossFlags}"
      ]}";
      mac = "${lib.concatStringsSep " " [
        "-C linker=${pkgs.clangStdenv.cc.cc}/bin/clang"
        "-C link-arg=-fuse-ld=${pkgs.lld}/bin/ld64.lld"
        "-C link-arg=--target=\${BEVY_FLAKE_TARGET}"
        "-C link-args=${lib.concatStringsSep "," [
          "-Wl"
          "-platform_version"
          "macos"
          "${macSdkJson.SupportedTargets.macosx.MinimumDeploymentTarget}"
          "${macSdkJson.SupportedTargets.macosx.DefaultDeploymentTarget}"
        ]}"
        "-C link-arg=-isysroot"
        "-C link-arg=${inputs.mac-sdk}"
        "${crossFlags}"
      ]}";
    };

    compileTimePackages = with pkgs; [
      # The wrapper, linkers, compilers, and pkg-config.
      cargo-wrapper
      cargo-xwin
      rust-toolchain
      pkg-config
      # Headers for x86_64-unknown-linux-gnu.
      alsa-lib.dev
      libxkbcommon.dev
      udev.dev
      wayland.dev
      # Extra compilation tools.
      clang
      llvm
    ] ++ lib.optionals (inputs ? mac-sdk) (with pkgs; [
      # Libclang, needed for MacOS targets.
      libclang.lib
    ]);

    # Headers for aarch64-unknown-linux-gnu.
    aarch64LinuxHeadersPath = (lib.makeSearchPath "lib/pkgconfig"
      (with pkgs.pkgsCross.aarch64-multiplatform; [
        alsa-lib.dev
        udev.dev
        wayland.dev
    ]));

    macSdkJson = lib.importJSON "${inputs.mac-sdk}/SDKSettings.json";
    
    # Wrapping 'cargo', to adapt the environment to context of compilation.
    cargo-wrapper = pkgs.writeShellScriptBin "cargo" ''
      # Check if cargo is being run with '--target', or '--no-wrapper'.
      ARG_COUNT=0
      for arg in "$@"; do
        ARG_COUNT=$((ARG_COUNT + 1))

        if [ "$arg" = '--target' ]; then
          # If run with --target, save the arg number of the arch specified.
          eval "BEVY_FLAKE_TARGET=\$$((ARG_COUNT + 1))"
        elif [ "$arg" = '--no-wrapper' ]; then
          # Remove '-no-wrapper' from prompt.
          set -- $(printf '%s\n' "$@" | grep -vx -- '--no-wrapper')
          # Run 'cargo' with no change to environment.
          exec ${rust-toolchain}/bin/cargo "$@"
        fi
      done

      # Prevents 'cargo run' from being input with a target.
      if [ "$1" = 'run' ] && [ "$BEVY_FLAKE_TARGET" != "" ]; then
        echo "bevy-flake: Cannot use 'cargo run' with a '--target'"
        exit 1
      fi

      # Stops 'blake3' from messing up.
      export CARGO_FEATURE_PURE=1 

      case $BEVY_FLAKE_TARGET in
        # No target means local system, sets localFlags if running or building.
        "")
          if [ "$1 $2" = 'xwin build' ]; then
            echo "bevy-flake: Cannot use '"cargo $@"' without a '--target'"
            exit 1
          elif [ "$1" = 'run' ] || [ "$1" = 'build' ]; then
            RUSTFLAGS="${localFlags} $RUSTFLAGS"
          fi
        ;;

        wasm32-unknown-unknown)
          RUSTFLAGS="${rustFlags.wasm32} $RUSTFLAGS"
        ;;
        x86_64-unknown-linux-gnu)
          RUSTFLAGS="${rustFlags.x86_64Linux} $RUSTFLAGS"
        ;;
        aarch64-unknown-linux-gnu)
          PKG_CONFIG_PATH="${aarch64LinuxHeadersPath}:$PKG_CONFIG_PATH"
          RUSTFLAGS="${rustFlags.aarch64Linux} $RUSFTLAGS"
        ;;
        *-apple-darwin)
        # Add MacOS environment only if SDK can be found in inputs.
        ${lib.optionalString (inputs ? mac-sdk) ''
          export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"
          export BINDGEN_EXTRA_CLANG_ARGS="${lib.concatStringsSep " " [
            "-F ${inputs.mac-sdk}/System/Library/Frameworks"
            "-I${inputs.mac-sdk}/usr/include"
            "$BINDGEN_EXTRA_CLANG_ARGS"
          ]}"
          RUSTFLAGS="${rustFlags.mac} $RUSTFLAGS"
        ''}
        ;;
        x86_64-pc-windows-msvc)
          RUSTFLAGS="${rustFlags.x86_64Windows} $RUSTFLAGS"
          if [ "$1" = 'build' ]; then
            echo "bevy-flake: Aliasing 'build' to 'xwin build'" 1>&2 
            set -- "xwin" "$@"
          fi
        ;;
        aarch64-pc-windows-msvc)
          RUSTFLAGS="${rustFlags.aarch64Windows} $RUSTFLAGS"
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
