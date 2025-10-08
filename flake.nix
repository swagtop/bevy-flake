{
  description =
    "A Nix flake for development and distribution of Bevy projects.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };
  
  outputs = inputs@{ self, nixpkgs, ... }:
  let
    inherit (builtins)
      concatStringsSep warn;
    inherit (nixpkgs.lib)
      genAttrs mapAttrsToList
      optionals optionalString
      makeSearchPath makeOverridable;

    eachSystem = genAttrs systems;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    targets = [
      "x86_64-unknown-linux-gnu"
      "aarch64-unknown-linux-gnu"
      "x86_64-pc-windows-msvc"
      "aarch64-pc-windows-msvc"
      "x86_64-apple-darwin"
      "aarch64-apple-darwin"
      "wasm32-unknown-unknown"
    ];

    config = {
      inherit rustToolchainFor runtimeBaseFor headersFor; # Defined below.

      linux = {
        glibcVersion = "2.41";
      };

      windows = {
        # Set to false if you don't want bevy-flake to manage cargo-xwin.
        pin = true;
        manifestVersion = "17";
        sdkVersion = "10.0.22621";
        crtVersion = "14.44.17.14";
      };

      macos = {
        # Loads MacOS SDK into here automatically, if added as flake input.
        sdk = inputs.macos-sdk or "";
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
      targetSpecificEnvironment =
        let
          macos = ''
            if [ "$MACOS_SDK_DIR" = "" ]; then
              printf "%s%s\n" \
                "bevy-flake: Building to MacOS target without SDK, " \
                "compilation will most likely fail." 1>&2
            fi
            FRAMEWORKS="$MACOS_SDK_DIR/System/Library/Frameworks";
            export SDKROOT="$MACOS_SDK_DIR"
            export COREAUDIO_SDK_PATH="$FRAMEWORKS/CoreAudio.framework/Headers"
            export BINDGEN_EXTRA_CLANG_ARGS="${concatStringsSep " " [
              "--sysroot=$MACOS_SDK_DIR"
              "-F $FRAMEWORKS"
              "-I$MACOS_SDK_DIR/usr/include"
              "$BINDGEN_EXTRA_CLANG_ARGS"
            ]}"
            RUSTFLAGS="${concatStringsSep " " [
              "-L $MACOS_SDK_DIR/usr/lib"
              "-L framework=$FRAMEWORKS"
              "$RUSTFLAGS"
            ]}"
          '';
        in {
          "x86_64-unknown-linux-gnu" = ''
            export PKG_CONFIG_PATH="${
              makeSearchPath "lib/pkgconfig" (headersFor "x86_64-linux")
            }:$PKG_CONFIG_PATH"
          '';
          "aarch64-unknown-linux-gnu" = ''
            export PKG_CONFIG_PATH="${
              makeSearchPath "lib/pkgconfig" (headersFor "aarch64-linux")
            }:$PKG_CONFIG_THEME"
          '';
          "x86_64-apple-darwin" = macos;
          "aarch64-apple-darwin" = macos;
          "wasm32-unknown-unknown" = ''
            RUSTFLAGS="${concatStringsSep " " [
              ''--cfg getrandom_backend=\"wasm_js\"''
              "$RUSTFLAGS"
            ]}"
          '';
        };
    };

    rustToolchainFor = (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        pkgs.symlinkJoin {
          name = "nixpkgs-rust-toolchain";
          pname = "cargo";
          paths = with pkgs; [
            cargo
            clippy
            rust-analyzer
            rustc
            rustfmt
          ];
        });

    runtimeBaseFor = (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
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
          ])
        );

    headersFor = (system:
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
          ])
        );
  in {
    inherit eachSystem systems targets;

    devShells = eachSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
      default = pkgs.mkShell {
        name = "bevy-flake";
        packages = [
          self.packages.${system}.wrapped-rust-toolchain
          self.packages.${system}.wrapped-dioxus-cli
        ];
      };
    });

    packages = makeOverridable (config: eachSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        rust-toolchain = config.rustToolchainFor system;
        runtimeBase = config.runtimeBaseFor system;

        wrapInEnvironmentAdapter = { name, runtime, execPath }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = runtimeBase ++ runtime ++ [ pkgs.stdenv.cc ];
          bashOptions = [ "errexit" "pipefail" ];
          text = ''
            # Check if cargo is being run with '--target', or '--no-wrapper'.
            BEVY_FLAKE_ARG_COUNT=0
            for arg in "$@"; do
              BEVY_FLAKE_ARG_COUNT=$((BEVY_FLAKE_ARG_COUNT + 1))
              case $arg in
                "--target")
                  # Save next arg as target.
                  eval "BEVY_FLAKE_TARGET=\$$((BEVY_FLAKE_ARG_COUNT + 1))"
                ;;
                "--no-wrapper")
                  # Remove '--no-wrapper' from args, then run unwrapped exec.
                  set -- "''${@:1:$((BEVY_FLAKE_ARG_COUNT - 1))}" \
                         "''${@:$((BEVY_FLAKE_ARG_COUNT + 1))}"
                  export BEVY_FLAKE_NO_WRAPPER="1"
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
            export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"
            export LIBRARY_PATH="${pkgs.libiconv}/lib"
            ${config.sharedEnvironment}

            case $BEVY_FLAKE_TARGET in
              "")
                export PKG_CONFIG_PATH="${
                  makeSearchPath "lib/pkgconfig" (headersFor system)
                }:$PKG_CONFIG_PATH"
                RUSTFLAGS="${concatStringsSep " " [
                  (optionalString (runtime != [])
                    "-C link-args=-Wl,-rpath,${
                      makeSearchPath "lib" (runtimeBase ++ runtime)}
                    ")
                  "${concatStringsSep " " config.localDevRustflags}"
                  "$RUSTFLAGS"
                ]}"
              ;;

            ${builtins.concatStringsSep "\n"
              (mapAttrsToList
                (target: env: ''
                  ${target}*)
                  ${env}
                  RUSTFLAGS="${
                    concatStringsSep " " config.crossPlatformRustflags
                  } $RUSTFLAGS"
                  ;;
                '')
              config.targetSpecificEnvironment)}
            esac

            export RUSTFLAGS="$RUSTFLAGS"
            export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
            export BEVY_FLAKE_ARG_COUNT="$BEVY_FLAKE_ARG_COUNT"
            export BEVY_FLAKE_TARGET="$BEVY_FLAKE_TARGET"

            exec ${execPath} "$@"
          '';
        };
      in {
        wrapped-rust-toolchain = pkgs.symlinkJoin {
          name = "bevy-flake-rust-toolchain";
          ignoreCollisions = true;
          paths = [
            (wrapInEnvironmentAdapter {
              name = "cargo";
              runtime = with pkgs; [
                cargo-zigbuild
                cargo-xwin
                rust-toolchain
              ];
              execPath = pkgs.writeShellScript "cargo" ''
                if [[ $BEVY_FLAKE_NO_WRAPPER = "1" ]]; then
                  exec ${rust-toolchain}/bin/cargo "$@"
                fi
                
                case $BEVY_FLAKE_TARGET in
                  *-unknown-linux-gnu*)
                    args=("$@")
                    if [[ $BEVY_FLAKE_TARGET =~ "x86_64" ]]; then
                      args[$((BEVY_FLAKE_ARG_COUNT-1))]=${
                        "x86_64-unknown-linux-gnu.${config.linux.glibcVersion}"
                      }
                    elif [[ $BEVY_FLAKE_TARGET =~ "aarch64" ]]; then
                      args[$((BEVY_FLAKE_ARG_COUNT-1))]=${
                        "aarch64-unknown-linux-gnu.${config.linux.glibcVersion}"
                      }
                    fi
                    set -- "''${args[@]}"
                  ;&
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
            })
            rust-toolchain
          ];
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
            wrapInEnvironmentAdapter {
              name = "dx";
              runtime = [ rust-toolchain pkgs.lld ];
              execPath = "${dx}/bin/dx";
            };
      })
    ) config;

    templates = {
      nixpkgs = warn "This template does not support any cross-compilation." {
        path = ./templates/nixpkgs;
        description = "Get the rust toolchain from nixpkgs.";
      };
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
