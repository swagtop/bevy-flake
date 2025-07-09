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
      forSystems forConfig
      makeRpath makeFlagString makePkgconfigPath;
    inherit (nixpkgs.lib)
      optionals optionalString mapAttrsToList
      makeLibraryPath makeSearchPath makeOverridable;
  in {
    config = {
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
        # If you always want the latest SDK and CRT version, set this to false.
        pin = true;
        # Run `xwin list` to list latest versions (not cargo-xwin, but xwin).
        manifestVersion = "16";
        sdkVersion = "10.0.17134";
        crtVersion = "14.29.16.10";
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
        "--remap-path-prefix=\${HOME}=/build"
      ];

      # Base environment for every target to build on.
      baseEnvironment = ''
        # Stops 'blake3' crate from messing up.
        export CARGO_FEATURE_PURE=1
      '';

      # Environment variables set for individual targets.
      # The target (attribute names) should use Bash case-switching syntax.
      targetEnvironment = rec {
        "x86_64-unknown-linux-gnu*" = ''
          export PKG_CONFIG_PATH="${
            makePkgconfigPath self.module."x86_64-linux".inputs.headers
          }"
        '';
        "aarch64-unknown-linux-gnu*"= ''
          export PKG_CONFIG_PATH="${
            makePkgconfigPath self.module."aarch64-linux".inputs.headers
          }"
        '';

        "x86_64-pc-windows-msvc" = "";
        "aarch64-pc-windows-msvc" = "";

        "x86_64-apple-darwin" = ''
          FRAMEWORKS="$MAC_SDK_DIR/System/Library/Frameworks";
          export SDKROOT="$MAC_SDK_DIR"
          export COREAUDIO_SDK_PATH="$FRAMEWORKS/CoreAudio.framework/Headers"
          export BINDGEN_EXTRA_CLANG_ARGS="${makeFlagString [
            "--sysroot=$MAC_SDK_DIR"
            "-F $FRAMEWORKS"
            "-I$MAC_SDK_DIR/usr/include"
          ]}"
          RUSTFLAGS="${makeFlagString [
            "-L $MAC_SDK_DIR/usr/lib"
            "-L framework=$FRAMEWORKS"
            "$RUSTFLAGS"
          ]}"
        '';
        "aarch64-apple-darwin" = x86_64-apple-darwin;

        "wasm32-unknown-unknown" = ''
          RUSTFLAGS="${makeFlagString [
            # https://docs.rs/getrandom/latest/getrandom/#webassembly-support
            "--cfg getrandom_backend=\"wasm_js\""
            "$RUSTFLAGS"
          ]}"
        '';
      };
    };

    devShells =
      forSystems self.config.systems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          name = "bevy-flake";
          packages = [
            self.packages.${system}.wrapped-nightly
          ];
          CARGO = "${self.packages.${system}.wrapped-nightly}/bin/cargo";
        };
    });

    packages =
      forSystems self.config.systems (system:
        let
          rust-nightly-module = self.module.override (old: {
            crossFlags =
              old.crossFlags ++ [
                "-Zlocation-detail=none"
                # Currently required rustflag for nightly toolchain on Nix.
                # https://github.com/NixOS/nixpkgs/issues/24744
                "-Zlinker-features=-lld"
              ];
          });
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };
        in rec {
        default = wrapped-nightly;
        
        wrapped-stable = self.module.${system}.wrapToolchain {
          rust-toolchain =
            pkgs.rust-bin.stable.latest.default.override {
              inherit (self.config) targets;
              extensions = [ "rust-src" "rust-analyzer" ];
            };
        };

        wrapped-nightly = rust-nightly-module.${system}.wrapToolchain {
          rust-toolchain =
            pkgs.rust-bin.nightly.latest.default.override {
              inherit (self.config) targets;
              extensions = [ "rust-src" "rust-analyzer" ];
            };
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
                        version = "0.7.0-alpha.1";
                        hash =
                          "sha256-3b82XlxffgbtYbEYultQMzJRRwY/I36E1wgzrKoS8BU=";
                      };
                      cargoHash =
                        "sha256-r42Z6paBVC2YTlUr4590dSA5RJJEjt5gfKWUl91N/ac=";
                      cargoPatches = [ ];
                      buildFeatures = [ ];
                    }
                  );
              };
            });
          in
            self.module.${system}.wrapProgram {
              program-path = "${dioxus}/bin/dx";
              output-name = "dx";
            };
      });

    # Access module attributes with a system, like so:
    #   bevy-flake.module.${system}.wrapProgram
    #   bevy-flake.module.${system}.inputs.linkers
    #
    # Override config used in module like so:
    #   (bevy-flake.module.override {
    #     localFlags = [ "-C link-arg=-fuse-ld=mold" ];
    #   }).${system}.wrapToolchain
    module = forConfig (config: system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      thisModule = self.module.${system};
    in {
      wrapProgram =
        {
          program-path,
          output-name, 
          runtimePackages ? thisModule.inputs.runtimePackages,
          arguments ? "",
        }:
        let
          rpathString = "${makeRpath runtimePackages}";
        in
        pkgs.writeShellScriptBin "${output-name}" ''
          ${config.baseEnvironment}
          export RUSTFLAGS="${rpathString} $RUSTFLAGS"
          exec ${program-path} ${arguments} "$@"
        '';

      wrapToolchain =
        {
          runtimePackages ? thisModule.inputs.runtimePackages,
          buildPackages ? thisModule.inputs.buildPackages,
          rust-toolchain ?
            pkgs.rust-bin.stable.latest.default.override {
              inherit (config) targets;
              extensions = [ "rust-src" "rust-analyzer" ];
            }
        }:
        let
          inherit (config)
            windows macos
            baseEnvironment targetEnvironment
            localFlags crossFlags;

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
            MAC_SDK_DIR="${macos.sdk}"

            # Set up Windows SDK and CRT.
            ${optionalString (windows.pin) ''
              export XWIN_CACHE_DIR="${(
                if (pkgs.stdenv.isDarwin)
                  then "$HOME/Library/Caches"
                  else "\${XDG_CACHE_HOME:-$HOME/.cache}"
                )
                + "/bevy-flake/xwin/"
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
                if [ "$MAC_SDK_DIR" = "" ]; then
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
            export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"
            ${baseEnvironment}

            # Set final environment variables based on target.
            case $BEVY_FLAKE_TARGET in
              # No target is local system.
              "")
                if [ "$1" = 'zigbuild' ] || [ "$1 $2" = 'xwin build' ]; then
                  echo "bevy-flake: Cannot use 'cargo $@' without a '--target'"
                  exit 1
                fi
                # If on NixOS, add runtimePackages to rpath.
                ${optionalString pkgs.stdenv.isLinux ''
                  RUSTFLAGS="${makeRpath runtimePackages} $RUSTFLAGS"
                ''}
                RUSTFLAGS="${makeFlagString localFlags} $RUSTFLAGS"
              ;;

              ${"\n" + (builtins.concatStringsSep "\n" (
                  mapAttrsToList (target: env:
                    "${target})\n${env}\n"
                  + "RUSTFLAGS=\"${makeFlagString crossFlags} "
                  + "$RUSTFLAGS\"" + "\n;;\n"
                  ) targetEnvironment
              ))}
            esac

            # Run cargo with relevant RUSTFLAGS.
            RUSTFLAGS="$RUSTFLAGS" exec ${rust-toolchain}/bin/cargo "$@"
          '';
        in
          pkgs.stdenv.mkDerivation {
            name = "bevy-flake-wrapped-toolchain";
            buildInputs = [ cargo-wrapper ];
            propagatedBuildInputs = [ rust-toolchain ] ++ buildPackages;
            installPhase = ''
              mkdir $out
              ln -s ${cargo-wrapper}/* $out/
            '';
            unpackPhase = "true";
          };

      inputs =
        let
          inherit (config.linux) runtime;
        in rec {
          runtimePackages =
            optionals (pkgs.stdenv.isLinux) (
              (with pkgs; [
                alsa-lib-with-plugins
                libxkbcommon
                udev
              ])
              ++ optionals runtime.vulkan.enable [ pkgs.vulkan-loader ]
              ++ optionals runtime.opengl.enable [ pkgs.libGL ]
              ++ optionals runtime.wayland.enable [ pkgs.wayland ]
              ++ optionals runtime.xorg.enable
                (with pkgs.xorg; [
                  libX11
                  libXcursor
                  libXi
                  libXrandr
                ])
            );

          linkers = with pkgs; [
            cargo-zigbuild
            cargo-xwin
          ];

          headers =
            optionals (pkgs.stdenv.isLinux)
              (with pkgs; [
                alsa-lib.dev
                libxkbcommon.dev
                udev.dev
                wayland.dev
              ]);

          buildPackages = [ pkgs.pkg-config ] ++ linkers ++ headers;

          all = runtimePackages ++ buildPackages;
        };
    });

    lib = {
      # Makes an attribute for each system in a list, in a set. Exposes system.
      forSystems = systems: f:
        builtins.listToAttrs (map (system: {
          name = system;
          value = f system;
        }) systems);

      # Calls 'forSystems' on systems in a config, exposes system and config.
      forConfig = f:
        makeOverridable (cfg:
          forSystems cfg.systems (system: f cfg system)
        ) self.config;

      # Make rustflag that sets rpath to searchpath of input packages.
      # This is what is used instead of LD_LIBRARY_PATH.
      makeRpath = packages:
        "-C link-args=-Wl,-rpath,/usr/lib:${makeLibraryPath
          (map (p: p.out) packages)
        }";

      # Puts all strings in a list into a single string, with a space separator.
      makeFlagString = flags: builtins.concatStringsSep " " flags;

      # Makes a search path for 'pkg-config' made up of every package in a list.
      makePkgconfigPath = packages:
        "${makeSearchPath "lib/pkgconfig" packages}:$PKG_CONFIG_PATH";
    };
  };
}
