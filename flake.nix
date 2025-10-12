{
  description =
    "A flake for development and distribution of Bevy projects.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };
  
  outputs = { nixpkgs, ... }:
  let
    inherit (builtins)
      attrNames concatStringsSep warn;
    inherit (nixpkgs.lib)
      genAttrs mapAttrsToList
      optionals optionalString
      makeSearchPath makeOverridable;

    config = {
      inherit rustToolchainFor runtimeInputsFor headerInputsFor stdEnvFor;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

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
        # You will not be able to cross-compile to MacOS targets without an SDK.
        sdk = "";
      };

      localDevRustflags = [ ];

      crossPlatformRustflags = [
        "--remap-path-prefix \${HOME}=/build"
      ];

      # Base environment for every target to build on.
      sharedEnvironment = {
        # Stops blake3 from messing builds up every once in a while.
        CARGO_FEATURE_PURE = "1";
      };

      # Environment variables set for individual targets.
      # The target names, and bodies should use Bash syntax.
      targetSpecificEnvironment =
        let
          macos =
          let
            frameworks = "$BF_MACOS_SDK_PATH/System/Library/Frameworks";
          in {
            SDKROOT = "$BF_MACOS_SDK_PATH";
            COREAUDIO_SDK_PATH = "${frameworks}/CoreAudio.framework/Headers";
            BINDGEN_EXTRA_CLANG_ARGS = concatStringsSep " " [
              "--sysroot=$BF_MACOS_SDK_PATH"
              "-F ${frameworks}"
              "-I$BF_MACOS_SDK_PATH/usr/include"
              "$BINDGEN_EXTRA_CLANG_ARGS"
            ];
            RUSTFLAGS = concatStringsSep " " [
              "-L $BF_MACOS_SDK_PATH/usr/lib"
              "-L framework=${frameworks}"
              "$RUSTFLAGS"
            ];
          };
        in {
          "x86_64-apple-darwin" = macos;
          "aarch64-apple-darwin" = macos;
          "x86_64-unknown-linux-gnu" = {
            PKG_CONFIG_PATH = "${
              makeSearchPath "lib/pkgconfig" (headerInputsFor "x86_64-linux")
            }:$PKG_CONFIG_PATH";
          };
          "aarch64-unknown-linux-gnu" = {
            PKG_CONFIG_PATH = "${
              makeSearchPath "lib/pkgconfig" (headerInputsFor "aarch64-linux")
            }:$PKG_CONFIG_PATH";
          };
          "wasm32-unknown-unknown" = {
            RUSTFLAGS =  concatStringsSep " " [
              ''--cfg getrandom_backend=\"wasm_js\"''
              "$RUSTFLAGS"
            ];
          };
          # No environment setup needed for Windows targets.
          "x86_64-pc-windows-msvc" = { };
          "aarch64-pc-windows-msvc" = { };
        };

      extraScript = "";
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

    runtimeInputsFor = (system:
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

    headerInputsFor = (system:
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

    stdEnvFor = system: nixpkgs.legacyPackages.${system}.stdenv;
  in
    makeOverridable (config:
    let
      eachSystem = genAttrs config.systems;

      packages = eachSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        exportEnv = env: "${concatStringsSep "\n"
          (mapAttrsToList (name: val: "export ${name}=\"${val}\"") env)
        }";

        rust-toolchain = config.rustToolchainFor system;
        runtimeInputsBase = config.runtimeInputsFor system;
        stdenv = config.stdEnvFor system;
          
        wrapInEnvironmentAdapter = { name, extraRuntimeInputs, execPath }:
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = runtimeInputsBase
              ++ extraRuntimeInputs ++ [ stdenv.cc rust-toolchain ];
            bashOptions = [ "errexit" "pipefail" ];
            text = ''
              # Check if cargo is being run with '--target', or '--no-wrapper'.
              BF_ARG_COUNT=0
              for arg in "$@"; do
                BF_ARG_COUNT=$((BF_ARG_COUNT + 1))
                case $arg in
                  "--target")
                    # Save next arg as target.
                    eval "BF_TARGET=\$$((BF_ARG_COUNT + 1))"; export BF_TARGET
                  ;;
                  "--no-wrapper")
                    # Remove '--no-wrapper' from args, then run unwrapped exec.
                    set -- "''${@:1:$((BF_ARG_COUNT - 1))}" \
                           "''${@:$((BF_ARG_COUNT + 1))}"
                    export BF_NO_WRAPPER="1"
                    exec ${execPath} "$@"
                  ;;
                esac
              done

              # Set up MacOS SDK if provided through config.
              export BF_MACOS_SDK_PATH="${config.macos.sdk}"

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
              export LIBCLANG_PATH="${pkgs.libclang.lib}/lib";
              export LIBRARY_PATH="${pkgs.libiconv}/lib";
              ${exportEnv config.sharedEnvironment}

              case $BF_TARGET in
                "")
                  export PKG_CONFIG_PATH="${
                    makeSearchPath "lib/pkgconfig" (headerInputsFor system)
                  }:$PKG_CONFIG_PATH"
                  export RUSTFLAGS="${concatStringsSep " " [
                    (optionalString (pkgs.stdenv.isLinux)
                      "-C link-args=-Wl,-rpath,${
                        makeSearchPath "lib"
                          (runtimeInputsBase ++ extraRuntimeInputs)}
                      ")
                    "${concatStringsSep " " config.localDevRustflags}"
                    "$RUSTFLAGS"
                  ]}"
                ;;

                ${concatStringsSep "\n"
                  (mapAttrsToList
                    (target: env: ''
                      ${target}*)
                      ${exportEnv env}
                      export RUSTFLAGS="${
                        concatStringsSep " " config.crossPlatformRustflags
                      } $RUSTFLAGS"
                      ;;
                    '')
                  config.targetSpecificEnvironment)}
              esac

              ${config.extraScript}

              exec ${execPath} "$@"
            '';
        };
      in {
        inherit wrapInEnvironmentAdapter;
        
        rust-toolchain = pkgs.symlinkJoin {
          name = "bevy-flake-rust-toolchain";
          ignoreCollisions = true;
          paths = [
            (wrapInEnvironmentAdapter {
              name = "cargo";
              extraRuntimeInputs = with pkgs; [
                cargo-zigbuild
                cargo-xwin
              ];
              execPath = pkgs.writeShellScript "cargo" ''
                if [[ $BF_NO_WRAPPER = "1" ]]; then
                  exec ${rust-toolchain}/bin/cargo "$@"
                fi

                case $BF_TARGET in
                  *-unknown-linux-gnu*)
                    args=("$@")
                    if [[ $BF_TARGET =~ "x86_64" ]]; then
                      args[$((BF_ARG_COUNT-1))]=${
                        "x86_64-unknown-linux-gnu.${config.linux.glibcVersion}"
                      }
                    elif [[ $BF_TARGET =~ "aarch64" ]]; then
                      args[$((BF_ARG_COUNT-1))]=${
                        "aarch64-unknown-linux-gnu.${config.linux.glibcVersion}"
                      }
                    fi
                    set -- "''${args[@]}"
                    BF_USE_ZIGBUILD=1
                  ;;
                  *-apple-darwin)
                    if [ "$BF_MACOS_SDK_PATH" = "" ]; then
                      printf "%s%s\n" \
                        "bevy-flake: Building to MacOS target without SDK, " \
                        "compilation will most likely fail." 1>&2
                    fi
                    BF_USE_ZIGBUILD=1
                  ;;
                  "wasm32-unknown-unknown") BF_USE_ZIGBUILD=1;;
                  *-pc-windows-msvc) BF_USE_XWIN=1;;
                esac

                if [[ $BF_USE_ZIGBUILD == 1 && "$1" == 'build' ]]; then
                  echo "bevy-flake: Aliasing 'build' to 'zigbuild'" 1>&2 
                  shift
                  set -- "zigbuild" "$@"
                elif [[ $BF_USE_XWIN == 1 && ("$1" = 'build' || "$1" = 'run') ]]; then
                  echo "bevy-flake: Aliasing '$1' to 'xwin $1'" 1>&2 
                  set -- "xwin" "$@"
                fi

                ${optionalString (pkgs.stdenv.isDarwin) "ulimit -n 4096"}
                exec ${rust-toolchain}/bin/cargo "$@"
              '';
            })
            rust-toolchain
          ];
        };

        # For now we have to override the package for hot-reloading.
        dioxus-cli =
        let
          version = "0.7.0-rc.1";
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
                        "sha256-Gri7gJe9b1q0qP+m0fe4eh+xj3wqi2get4Rqz6xL8yA=";
                    };
                    cargoHash =
                      "sha256-+HPWgiFc7pbosHWpRvHcSj7DZHD9sIPOE3S5LTrDb6I=";

                    postPatch = "";
                    checkFlags = [ "--skip" "test_harnesses::run_harness" ];

                    cargoPatches = [ ];
                    buildFeatures = [ ];
                  }
                );
            };
          });
        in
          wrapInEnvironmentAdapter {
            name = "dx";
            extraRuntimeInputs = [ rust-toolchain pkgs.lld ];
            execPath = "${dx}/bin/dx";
          };
      });
    in {
      inherit (config) systems;
      inherit eachSystem packages;

      devShells = eachSystem (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          name = "bevy-flake";
          packages = [
            packages.${system}.rust-toolchain
            # packages.${system}.dioxus-cli
          ];
        };
      });

      targets = attrNames config.targetSpecificEnvironment;

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
  }) config;
}
