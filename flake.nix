{
  description =
    "A Nix flake for development and distribution of Bevy projects.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  
  outputs = inputs@{ self, rust-overlay, nixpkgs, ... }:
  let
    inherit (nixpkgs.lib)
      optionals optionalString
      makeSearchPath makeOverridable
      genAttrs mapAttrsToList zipAttrsWith;

    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    targets = [
      "wasm32-unknown-unknown"
      "aarch64-unknown-linux-gnu"
      "x86_64-unknown-linux-gnu"
      "aarch64-pc-windows-msvc"
      "x86_64-pc-windows-msvc"
      "aarch64-apple-darwin"
      "x86_64-apple-darwin"
    ];

    eachSystem = genAttrs systems;
    concatWithSpace = list: builtins.concatStringsSep " " list;
  in {
    inherit systems targets eachSystem;

    config = {
      linux = { };

      windows = {
        # If you don't want bevy-flake to manage the Windows SDK and CRT, set
        # this to false.
        pin = true;
        # Run `xwin list` to list latest versions (not cargo-xwin, but xwin).
        manifestVersion = "17";
        sdkVersion = "10.0.22621";
        crtVersion = "14.44.17.14";
      };

      macos = {
        # Loads MacOS SDK into here automatically, if added as flake input.
        sdk = optionalString (inputs ? macos-sdk) inputs.macos-sdk;
      };

      localDevRustflags = [ ];

      crossPlatformRustflags = [
        "--remap-path-prefix \${HOME}=/build"
      ];

      # Base environment for every target to build on.
      sharedEnvironment = ''
        # Stops 'blake3' crate from messing up.
        export CARGO_FEATURE_PURE=1
      '';

      # Environment variables set for individual targets.
      # The target names, and bodies should use Bash syntax.
      targetSpecificEnvironment = { };
    };

    devShells = eachSystem (system: {
      default =
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        pkgs.mkShell {
          name = "bevy-flake";
          packages = [
            self.packages.${system}.wrapped-rust-toolchain
            self.packages.${system}.wrapped-dioxus-cli
          ];
        };
    });

    packages = eachSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
        runtime =
          optionals (pkgs.stdenv.isLinux)
            (with pkgs; [
              alsa-lib-with-plugins
              libxkbcommon
              udev
              vulkan-loader
              libGL
              wayland
              xorg.libX11
              xorg.libXcursor
              xorg.libXi
              xorg.libXrandr
            ]);
      in rec {
        default = wrapped-rust-toolchain;

        wrapped-rust-toolchain = makeOverridable self.wrapToolchain {
          inherit runtime;
          inherit (self) config;
          rust-toolchain = 
            pkgs.rust-bin.stable.latest.default.override (old: {
              inherit targets;
              extensions = [ "rust-src" "rust-analyzer" ];
            });
        };

        wrapped-dioxus-cli =
        let
          version = "0.7.0-rc.0";
          dx = nixpkgs.legacyPackages.${system}.dioxus-cli.override (old: {
            rustPlatform = old.rustPlatform // {
              buildRustPackage = args:
                old.rustPlatform.buildRustPackage (
                  args // {
                    inherit version;
                    src = old.fetchCrate {
                      inherit version;
                      pname = "dioxus-cli";
                      hash =
                        "sha256-xt/DJhcZz3TZLodfJTaFE2cBX3hedo+typHM5UezS94=";
                    };
                    cargoHash =
                      "sha256-UVt4vZyh+w+8Z1Bp1emFOJqPXU1zzy7FzNcA5oQsM8U=";
                    cargoPatches = [ ];
                    buildFeatures = [ ];
                  }
                );
            };
          });
        in
          makeOverridable self.wrapInEnvironmentAdapter {
            inherit system runtime;
            inherit (self) config;
            execPath = "${dx}/bin/dx";
            name = "dx";
          };
    });

    wrapInEnvironmentAdapter = {
      system,
      execPath,
      name,
      runtime,
      config,
    }:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      headers = self.lib.headersFor system;
      dependencies = with pkgs; [
        pkg-config
        stdenv.cc
      ]
      ++ optionals (pkgs.stdenv.isDarwin) [ pkgs.libiconv ];
      environment-adapter = pkgs.writeShellScriptBin "${name}" ''
        # Check if cargo is being run with '--target', or '--no-wrapper'.
        ARG_COUNT=0
        for arg in "$@"; do
          ARG_COUNT=$((ARG_COUNT + 1))
          case $arg in
            "--target")
              # Save next arg as target.
              eval "BEVY_FLAKE_TARGET=\$$((ARG_COUNT + 1))"
            ;;
            "--no-wrapper")
              # Remove '--no-wrapper' from args, then run unwrapped cargo.
              set -- "''${@:1:$((ARG_COUNT-1))}" "''${@:$((ARG_COUNT+1))}"
              exec ${execPath} "$@"
            ;;
          esac
        done

        # Set up MacOS SDK if provided through config.
        MACOS_SDK_DIR="${config.macos.sdk}"

        # Set up Windows SDK and CRT if pinning is enabled.
        ${optionalString (config.windows.pin) ''
            export XWIN_CACHE_DIR="${(
              if (pkgs.stdenv.isDarwin)
                then "$HOME/Library/Caches/"
                else "\${XDG_CACHE_HOME:-$HOME/.cache}/"
              )
              + "bevy-flake/xwin/"
              + "manifest${config.windows.manifestVersion}"
              + "-sdk${config.windows.sdkVersion}"
              + "-crt${config.windows.crtVersion}"
            }"
            export XWIN_VERSION="${config.windows.manifestVersion}"
            export XWIN_SDK_VERSION="${config.windows.sdkVersion}"
            export XWIN_CRT_VERSION="${config.windows.crtVersion}"
        ''}

        # Base environment for all targets.
        export PKG_CONFIG_ALLOW_CROSS="1"
        export LIBRARY_PATH="${
          optionalString (pkgs.stdenv.isDarwin) "${pkgs.libiconv}/lib"
        }:$LIBRARY_PATH"
        export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"
        ${config.sharedEnvironment}

        case $BEVY_FLAKE_TARGET in
          "")
            export PKG_CONFIG_PATH="${headers}:$PKG_CONFIG_PATH"
            RUSTFLAGS="${concatWithSpace [
              (optionalString (runtime != [])
                "-C link-args=-Wl,-rpath,${makeSearchPath "lib" runtime}")
              "${concatWithSpace config.localDevRustflags}"
              "$RUSTFLAGS"
            ]}"
          ;;

          ${builtins.concatStringsSep "\n" (mapAttrsToList (target: env: ''
            ${target}*)
            ${env}
            RUSTFLAGS="${
              concatWithSpace config.crossPlatformRustflags
            } $RUSTFLAGS"
            ;;
          '') (zipAttrsWith (name: values:
            builtins.concatStringsSep "\n" values) [
              config.targetSpecificEnvironment
              self.baseTargetSpecificEnvironment
            ]
          ))}
        esac

        export RUSTFLAGS="$RUSTFLAGS"
        export BEVY_FLAKE_TARGET="$BEVY_FLAKE_TARGET"

        exec ${execPath} "$@"
      '';
    in
      pkgs.symlinkJoin {
        name = "${name}-environment-adapter";
        pname = "${name}";
        ignoreCollisions = true;
        paths = [ environment-adapter ] ++ dependencies;
        buildInputs = [ environment-adapter pkgs.libclang.lib ] ++ dependencies;
      };

    wrapToolchain = {
      rust-toolchain,
      runtime,
      config,
    }:
    let
      pkgs = nixpkgs.legacyPackages.${rust-toolchain.system};
      dependencies = (with pkgs; [
        cargo-zigbuild
        cargo-xwin
        rust-toolchain
      ]);
      linker-adapter = pkgs.writeShellScriptBin "cargo" ''
        case $BEVY_FLAKE_TARGET in
          *-unknown-linux-gnu*);&
          *-apple-darwin);&
          "wasm32-unknown-unknown")
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

        exec ${rust-toolchain}/bin/cargo "$@"
      '';
      linker-adapter-wrapped = 
        self.wrapInEnvironmentAdapter {
          inherit runtime config;
          system = rust-toolchain.system;
          execPath = "${linker-adapter}/bin/cargo";
          name = "cargo";
        };
    in
      pkgs.symlinkJoin {
        name = "bevy-flake-wrapped-toolchain";
        pname = "cargo";
        ignoreCollisions = true;
        paths = [ linker-adapter-wrapped ] ++ dependencies;
        buildInputs =
          [ linker-adapter linker-adapter-wrapped ]
          ++ dependencies
          ++ runtime;
      };

    lib = {
      headersFor = system: 
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        makeSearchPath "lib/pkgconfig" (
          optionals (pkgs.stdenv.isLinux)
            (with pkgs; [
              alsa-lib-with-plugins.dev
              libxkbcommon.dev
              openssl.dev
              udev.dev
              wayland.dev
            ])
        );
    };

    baseTargetSpecificEnvironment = rec {
      "x86_64-unknown-linux-gnu" = ''
        export PKG_CONFIG_PATH="${self.lib.headersFor "x86_64-linux"}"
      '';
      "aarch64-unknown-linux-gnu" = ''
        export PKG_CONFIG_PATH="${self.lib.headersFor "aarch64-linux"}"
      '';
      "x86_64-apple-darwin" = ''
        if [ "$MACOS_SDK_DIR" = "" ]; then
          printf "%s%s\n" \
            "bevy-flake: Building to MacOS target without SDK, " \
            "compilation will most likely fail." 1>&2
        fi
        FRAMEWORKS="$MACOS_SDK_DIR/System/Library/Frameworks";
        export SDKROOT="$MACOS_SDK_DIR"
        export COREAUDIO_SDK_PATH="$FRAMEWORKS/CoreAudio.framework/Headers"
        export BINDGEN_EXTRA_CLANG_ARGS="${concatWithSpace [
          "--sysroot=$MACOS_SDK_DIR"
          "-F $FRAMEWORKS"
          "-I$MACOS_SDK_DIR/usr/include"
        ]}"
        RUSTFLAGS="${concatWithSpace [
          "-L $MACOS_SDK_DIR/usr/lib"
          "-L framework=$FRAMEWORKS"
          "$RUSTFLAGS"
        ]}"
      '';
      "aarch64-apple-darwin" = x86_64-apple-darwin;
      "wasm32-unknown-unknown" = ''
        RUSTFLAGS="${concatWithSpace [
          "--cfg getrandom_backend=\\\"wasm_js\\\""
          "$RUSTFLAGS"
        ]}"
      '';
    };
  };
}
