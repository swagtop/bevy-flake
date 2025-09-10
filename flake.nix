{
  description =
    "A Nix flake for development and distribution of Bevy projects.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    macos-sdk = { follows = ""; flake = false; };
    ios-sdk = { follows = ""; flake = false; };
  };
  
  outputs = inputs@{ self, nixpkgs, ... }:
  let
    inherit (nixpkgs.lib)
      optionals optionalString 
      makeSearchPath makeOverridable recursiveUpdate
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
        # Set to false if you don't want bevy-flake to manage cargo-xwin.
        pin = true;
        manifestVersion = "17";
        sdkVersion = "10.0.22621";
        crtVersion = "14.44.17.14";
      };

      macos = {
        # Loads MacOS SDK into here automatically, if added as flake input.
        sdk = optionalString (inputs.macos-sdk != self) inputs.macos-sdk;
      };

      ios = {
        sdk = optionalString (inputs.ios-sdk != self) inputs.ios-sdk;
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

    packages = eachSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in rec {
        default = wrapped-rust-toolchain;

        wrapped-rust-toolchain = makeOverridable self.wrapToolchain {
          inherit (self) config;
          runtime = [ runtime-bundle ];
          rust-toolchain = 
            pkgs.symlinkJoin {
              name = "bevy-flake-default-toolchain";
              pname = "cargo";
              paths = with pkgs; [
                cargo
                clippy
                rust-analyzer
                rustc
                rustfmt
              ];
            };
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
              inherit system;
              inherit (self) config;
              runtime = [ runtime-bundle ];
              execPath = "${dx}/bin/dx";
              name = "dx";
            };

        runtime-bundle = pkgs.symlinkJoin {
          name = "bevy-flake-runtime-bundle";
          paths =
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
        };
    });

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

    wrapInEnvironmentAdapter = {
      system,
      execPath,
      name,
      runtime,
      config ? self.config
    }:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = runtime ++ (with pkgs; [
          pkg-config
          stdenv.cc
        ]);
        bashOptions = [ "errexit" "pipefail" ];
        text = ''
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
                set -- "''${@:1:$((ARG_COUNT - 1))}" "''${@:$((ARG_COUNT + 1))}"
                exec ${execPath} "$@"
              ;;
            esac
          done

          # Set up MacOS SDK if provided through config.
          MACOS_SDK_DIR="${config.macos.sdk}"
          IOS_SDK_DIR="${config.ios.sdk}"

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
          export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"
          export LIBRARY_PATH="${pkgs.libiconv}/lib"
          ${config.sharedEnvironment}

          case $BEVY_FLAKE_TARGET in
            "")
              export PKG_CONFIG_PATH="${
                makeSearchPath "lib/pkgconfig"
                  (self.lib.headersFor system)
              }:$PKG_CONFIG_PATH"
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
              (rec {
                "x86_64-unknown-linux-gnu" = ''
                  export PKG_CONFIG_PATH="${
                    makeSearchPath "lib/pkgconfig"
                      (self.lib.headersFor "x86_64-linux")
                  }:$PKG_CONFIG_PATH"
                '';
                "aarch64-unknown-linux-gnu" = ''
                  export PKG_CONFIG_PATH="${
                    makeSearchPath "lib/pkgconfig"
                      (self.lib.headersFor "aarch64-linux")
                  }:$PKG_CONFIG_THEME"
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
                    "$BINDGEN_EXTRA_CLANG_ARGS"
                  ]}"
                  RUSTFLAGS="${concatWithSpace [
                    "-L $MACOS_SDK_DIR/usr/lib"
                    "-L framework=$FRAMEWORKS"
                    "$RUSTFLAGS"
                  ]}"
                '';
                "aarch64-apple-darwin" = x86_64-apple-darwin;
                "aarch64-apple-ios" = ''
                  if [ "$IOS_SDK_DIR" = "" ]; then
                    printf "%s%s\n" \
                      "bevy-flake: Building to iOS target without SDK, " \
                      "compilation will most likely fail." 1>&2
                  fi
                  FRAMEWORKS="$IOS_SDK_DIR/System/Library/Frameworks";
                  export SDKROOT="$IOS_SDK_DIR"
                  export COREAUDIO_SDK_PATH="$FRAMEWORKS/CoreAudio.framework/Headers"
                  export BINDGEN_EXTRA_CLANG_ARGS="${concatWithSpace [
                    "--sysroot=$IOS_SDK_DIR"
                    "-I$MACOS_SDK_DIR/usr/include"
                    "$BINDGEN_EXTRA_CLANG_ARGS"
                  ]}"
                '';
                "wasm32-unknown-unknown" = ''
                  RUSTFLAGS="${concatWithSpace [
                    ''--cfg getrandom_backend=\"wasm_js\"''
                    "$RUSTFLAGS"
                  ]}"
                '';
              })
            ]
          ))}
          esac

          export RUSTFLAGS="$RUSTFLAGS"
          export BEVY_FLAKE_TARGET="$BEVY_FLAKE_TARGET"

          exec ${execPath} "$@"
        '';
      };

    wrapToolchain = {
      rust-toolchain,
      runtime,
      config ? self.config,
    }:
      let
        system = rust-toolchain.system;
        pkgs = nixpkgs.legacyPackages.${system};
        linker-adapter = pkgs.writeShellApplication {
          name = "cargo";
          runtimeInputs = runtime ++ (with pkgs; [
            cargo-zigbuild
            cargo-xwin
            rust-toolchain
          ]);
          bashOptions = [ "errexit" "pipefail" ];
          text =  ''
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

            ${optionalString (pkgs.stdenv.isDarwin) "ulimit -n 4096"}
            exec ${rust-toolchain}/bin/cargo "$@"
          '';
        };
        linker-adapter-wrapped = 
          self.wrapInEnvironmentAdapter {
            inherit config runtime;
            system = rust-toolchain.system;
            execPath = "${linker-adapter}/bin/cargo";
            name = "cargo";
          };
      in
        pkgs.symlinkJoin {
          name = "bevy-flake-wrapped-toolchain";
          pname = "cargo";
          ignoreCollisions = true;
          paths = [ linker-adapter-wrapped rust-toolchain ];
        };

    lib = {
      headersFor = system: 
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
          optionals (pkgs.stdenv.isLinux)
            (with pkgs; [
              alsa-lib-with-plugins.dev
              libxkbcommon.dev
              openssl.dev
              udev.dev
              wayland.dev
            ]);

      editDefaultConfig = changes: recursiveUpdate self.config changes;
    };

    templates = {
      rust-overlay = {
        path = ./templates/rust-overlay;
        description = "Get the rust toolchain through oxalica's rust-overlay.";
      };
      fenix = {
        path = ./templates/fenix;
        description = "Get the rust toolchain through nix-community's fenix.";
      };
    };
  };
}
