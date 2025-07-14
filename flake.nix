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
    inherit (self.lib)
      makeRpath makeFlagString makePkgconfigPath makeSwitchCases;
    inherit (nixpkgs.lib)
      genAttrs mapAttrsToList optionals optionalString
      makeLibraryPath makeSearchPath makeOverridable makeBinPath;

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
  in {
    devShells = genAttrs systems (system: {
      default = nixpkgs.legacyPackages.${system}.mkShell {
        name = "bevy-flake";
        packages = [
          self.packages.${system}.wrapped-nightly
        ];
        # CARGO = "${self.packages.${system}.wrapped-nightly}/bin/cargo";
      };
    });

    config = {
      linux = {
        # These options do not affect the build, only your dev environment.
        runtime = {
          vulkan.enable = true;
          opengl.enable = true;
          wayland.enable = true && (builtins.getEnv "NO_WAYLAND" != "1");
          xorg.enable = true;
        };
      };

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

      # Flags for local development environment.
      localFlags = [ ];

      # Flags for other platforms, you are cross-compiling to.
      crossFlags = [
        # Remove your username from the final binary (by way of removing $HOME).
        "--remap-path-prefix \${HOME}=/build"
      ];

      # Base environment for every target to build on.
      baseEnvironment = ''
        # Stops 'blake3' crate from messing up.
        export CARGO_FEATURE_PURE=1
      '';

      # Environment variables set for individual targets.
      # The target names, and bodies should use Bash syntax.
      targetEnvironment = rec {
        "x86_64-unknown-linux-gnu*" = "";
        "aarch64-unknown-linux-gnu*" = "";

        "x86_64-pc-windows-msvc" = "";
        "aarch64-pc-windows-msvc" = "";

        "x86_64-apple-darwin" = ''
          FRAMEWORKS="$MACOS_SDK_DIR/System/Library/Frameworks";
          export SDKROOT="$MACOS_SDK_DIR"
          export COREAUDIO_SDK_PATH="$FRAMEWORKS/CoreAudio.framework/Headers"
          export BINDGEN_EXTRA_CLANG_ARGS="${makeFlagString [
            "--sysroot=$MACOS_SDK_DIR"
            "-F $FRAMEWORKS"
            "-I$MACOS_SDK_DIR/usr/include"
          ]}"
          RUSTFLAGS="${makeFlagString [
            "-L $MACOS_SDK_DIR/usr/lib"
            "-L framework=$FRAMEWORKS"
            "$RUSTFLAGS"
          ]}"
        '';
        "aarch64-apple-darwin" = x86_64-apple-darwin;

        "wasm32-unknown-unknown" = ''
          RUSTFLAGS="${makeFlagString [
            # https://docs.rs/getrandom/latest/getrandom/#webassembly-support
            "--cfg getrandom_backend=\\\"wasm_js\\\""
            "$RUSTFLAGS"
          ]}"
        '';
      };
    };

    packages = genAttrs systems (system:
    let
      inherit (self) body;
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
      };
    in rec {
      default = wrapped-nightly;
      
      wrapped-stable = body.${system}.wrappers.wrapToolchain {
        rust-toolchain =
          pkgs.rust-bin.stable.latest.default.override {
            inherit targets;
            extensions = [ "rust-src" "rust-analyzer" ];
          };
      };

      wrapped-nightly = body.${system}.wrappers.wrapToolchain {
        config = self.config //  {
          crossFlags = self.config.crossFlags ++ [ "-Zlinker-features=-lld" ];
        };
        rust-toolchain =
          pkgs.rust-bin.nightly.latest.default.override (old: {
            inherit targets;
            extensions = [ "rust-src" "rust-analyzer" ];
          });
      };

      dioxus-hot-reload =
      let
        dioxus = pkgs.dioxus-cli.override (old: {
          rustPlatform = old.rustPlatform // {
            buildRustPackage = args:
              old.rustPlatform.buildRustPackage (
                args // {
                  src = old.fetchCrate {
                    pname = "dioxus-cli";
                    version = "0.7.0-alpha.2";
                    hash =
                      "sha256-wPdU0zXx806zkChJ6vPGK9nwtVObEYX98YslK5U74qk=";
                  };
                  cargoHash =
                    "sha256-b4CvC0hpqsOuYSyzHq1ABCE9V1I/+ZhpHFTJGt3gYNM=";
                  cargoPatches = [ ];
                  buildFeatures = [ ];
                }
              );
          };
        });
      in
        body.${system}.wrappers.wrapProgramPath {
          program-path = "${dioxus}/bin/dx";
          output-name = "dx";
        };
    });

    body = genAttrs systems (system: 
    let
      pkgs = nixpkgs.legacyPackages.${system};
      systemIsLinux = pkgs.stdenv.isLinux;
      systemIsDarwin = pkgs.stdenv.isDarwin;
      configureDependencies = config: rec {
        runtime =
        let
          inherit (config) linux;
        in
          optionals (systemIsLinux) (
            (with pkgs; [
              alsa-lib-with-plugins
              libxkbcommon
              udev
            ])
            ++ optionals linux.runtime.vulkan.enable [ pkgs.vulkan-loader ]
            ++ optionals linux.runtime.opengl.enable [ pkgs.libGL ]
            ++ optionals linux.runtime.wayland.enable [ pkgs.wayland ]
            ++ optionals linux.runtime.xorg.enable
              (with pkgs.xorg; [
                libX11
                libXcursor
                libXi
                libXrandr
              ])
          );

        headers = (
          optionals (systemIsDarwin) [ pkgs.darwin.libiconv.dev ]
          ++ optionals (systemIsLinux)
            (with pkgs; [
              alsa-lib-with-plugins.dev
              libxkbcommon.dev
              openssl.dev
              udev.dev
              wayland.dev
            ])
        );

        build = (
          (with pkgs; [
            pkg-config
          ])
          ++ optionals (systemIsLinux) [ pkgs.stdenv.cc ]
        );

        all = runtime ++ headers ++ build;
      };

      wrappers = {
        wrapProgramPath =
          {
            program-path,
            output-name, 
            config ? self.config,
            extra ? { runtime = []; headers = []; },
            arguments ? "",
          }:
          let
            dependencies = configureDependencies config;
            rpathString = "${
              makeRpath (dependencies.runtime ++ extra.runtime)
            }";
          in
            pkgs.writeShellScriptBin "${output-name}" ''
              ${config.baseEnvironment}
              export RUSTFLAGS="${rpathString} $RUSTFLAGS"
              exec ${program-path} ${arguments} "$@"
            '';

        wrapToolchain = makeOverridable (
          {
            rust-toolchain,
            config ? self.config,
            extra ? { runtime = []; headers = []; },
          }:
          let
            inherit (config)
              windows macos
              baseEnvironment targetEnvironment
              localFlags crossFlags;
            dependencies = configureDependencies config;
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
                    # Remove '--no-wrapper' from args, then run unwrapped cargo.
                    set -- "''${@:1:$((ARG_COUNT-1))}" "''${@:$((ARG_COUNT+1))}"
                    exec ${rust-toolchain}/bin/cargo "$@"
                  ;;
                esac
              done

              # Set up MacOS SDK.
              MACOS_SDK_DIR="${macos.sdk}"

              # Set up Windows SDK and CRT.
              ${optionalString (windows.pin) ''
                export XWIN_CACHE_DIR="${(
                  if (pkgs.stdenv.isDarwin)
                    then "$HOME/Library/Caches/"
                    else "\${XDG_CACHE_HOME:-$HOME/.cache}/"
                  )
                  + "bevy-flake/xwin/"
                  + "manifest${windows.manifestVersion}-"
                  + "sdk${windows.sdkVersion}-"
                  + "crt${windows.crtVersion}"
                }"
                export XWIN_VERSION="${windows.manifestVersion}"
                export XWIN_SDK_VERSION="${windows.sdkVersion}"
                export XWIN_CRT_VERSION="${windows.crtVersion}"
              ''}

              # Make sure first argument of 'cargo' is correct for target.
              case $BEVY_FLAKE_TARGET in
                *-apple-darwin)
                  if [ "$MACOS_SDK_DIR" = "" ]; then
                    printf "%s%s\n" \
                      "bevy-flake: Building to MacOS target without SDK, " \
                      "compilation will most likely fail." 1>&2
                  fi
                ;&
                *-unknown-linux-gnu*);&
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

              # Base environment for all targets.
              export PKG_CONFIG_ALLOW_CROSS="1"
              export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"
              ${baseEnvironment}

              # Set final environment variables based on target.
              case $BEVY_FLAKE_TARGET in
                # No target is local system.
                "")
                  if [ "$1" = 'zigbuild' ] || [ "$1 $2" = 'xwin build' ]; then
                    echo "bevy-flake: Can't use 'cargo $@' without a '--target'"
                    exit 1
                  fi
                  # If on NixOS, add runtimePackages to rpath.
                  ${optionalString systemIsLinux ''
                    RUSTFLAGS="${
                      makeRpath (dependencies.runtime ++ extra.runtime)
                    } $RUSTFLAGS"
                  ''}
                  RUSTFLAGS="${makeFlagString localFlags} $RUSTFLAGS"
                ;;

                ${makeSwitchCases crossFlags (targetEnvironment // {
                  "x86_64-unknown-linux-gnu*" =
                    (targetEnvironment."x86_64-unknown-linux-gnu*") + ''
                      export PKG_CONFIG_PATH="${
                        makePkgconfigPath dependencies.headers
                      }"
                    '';
                  "aarch64-unknown-linux-gnu*" =
                    (targetEnvironment."aarch64-unknown-linux-gnu*") + ''
                      export PKG_CONFIG_PATH="${
                        makePkgconfigPath dependencies.headers
                      }"
                    '';
                })}
              esac

              # Run cargo with relevant RUSTFLAGS.
              RUSTFLAGS="$RUSTFLAGS" exec ${rust-toolchain}/bin/cargo "$@"
            '';
          in
            pkgs.symlinkJoin rec {
              name = "bevy-flake-wrapped-toolchain";
              pname = "cargo";
              paths = with pkgs; [
                cargo-wrapper
                cargo-zigbuild
                cargo-xwin
              ];
              nativeBuildInputs = [ pkgs.makeWrapper ];
              buildInputs = with pkgs; [
                rust-toolchain
                libclang.lib
              ]
              ++ paths
              ++ dependencies.all
              ++ extra.runtime
              ++ extra.headers;
              # postBuild = ''
              #   wrapProgram $out/bin/cargo \
              #     --prefix PATH : \
              #       ${makeBinPath (dependencies.build ++ [ rust-toolchain ])} \
              #     --prefix PKG_CONFIG_PATH : \
              #       ${makePkgconfigPath
              #         (dependencies.headers ++ extra.headers)
              #       }
              # '';
            }
          );
        };
    in {
      inherit wrappers configureDependencies;
    });

    lib = {
      # Make rustflag that sets rpath to searchpath of input packages.
      # This is what is used instead of LD_LIBRARY_PATH.
      makeRpath = packages:
        "-C link-args=-Wl,-rpath,/usr/lib:${
          makeLibraryPath (map (p: p.out) packages)
        }";

      # Puts all strings in a list into a single string, with a space separator.
      makeFlagString = flags: builtins.concatStringsSep " " flags;

      # Makes a search path for 'pkg-config' made up of every package in a list.
      makePkgconfigPath = packages:
        "${makeSearchPath "lib/pkgconfig" packages}";

      # Unfolds { target = environment } into 'target) environment crossFlags;;'
      makeSwitchCases = crossFlags: targetEnvironment:
      let
        setupCrossFlags =
          "RUSTFLAGS=\"${makeFlagString crossFlags} $RUSTFLAGS\"";

        formatted = mapAttrsToList (target: env: ''
          ${target})
          ${env}
          ${setupCrossFlags}
          ;;
        '') targetEnvironment;
      in
        "\n" + builtins.concatStringsSep "\n" formatted;
      };
  };
}
