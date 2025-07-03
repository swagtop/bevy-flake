{
  description = "A flake for development and distribution of Bevy projects.";

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
      forSystems makeRpath makeFlagString makePkgconfigPath;
    inherit (nixpkgs.lib)
      optionals optionalString mapAttrsToList makeLibraryPath makeSearchPath;
  in
  {
    devShells =
      forSystems self.config.systems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          name = "bevy-flake";
          packages = [
            self.packages.${system}.rust-toolchain-nightly
          ];
          CARGO = "${self.packages.${system}.rust-toolchain-nightly}/bin/cargo";
        };
    });

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

      windows = {
        # If you always want the latest SDK and CRT version, set this to false.
        pin = true;
        # Run `xwin list` to list latest versions (not cargo-xwin, but xwin).
        manifestVersion = "16";
        sdkVersion = "10.0.17134";
        crtVersion = "14.29.16.10";
      };

      linux = {
        runtime = {
          vulkan.enable = true;
          opengl.enable = true;
          wayland.enable = true && (builtins.getEnv "NO_WAYLAND" == "1");
          xorg.enable = true;
        };
      };

      macos = {
        # Loads MacOS SDK into here automatically, if added as flake input.
        sdk = optionalString (inputs ? macos-sdk) inputs.macos-sdk;
      };

      # Flags for local development environment.
      localFlags = [ ];

      # Flags for other platforms, you are cross-compiling to.
      crossFlags = [
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
          export PKG_CONFIG_PATH=${makePkgconfigPath "x86_64-linux"}
        '';
        "aarch64-unknown-linux-gnu*"= ''
          export PKG_CONFIG_PATH=${makePkgconfigPath "aarch64-linux"}
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
          RUSTFLAGS="--cfg getrandom_backend=\"wasm_js\" $RUSTFLAGS"
        '';
      };
    };

    lib = {
      forSystems = systems: f:
        builtins.listToAttrs (map (system: {
          name = system;
          value = f system;
        }) systems);

      # Make rustflag that sets rpath to searchpath of input packages.
      # This is what is used instead of LD_LIBRARY_PATH.
      makeRpath = packages:
        "-C link-args=-Wl,-rpath,/usr/lib:${makeLibraryPath
          (map (p: p.out) packages)
        }";

      makeFlagString = flags: builtins.concatStringsSep " " flags;

      makePkgconfigPath = system:
        "${(makeSearchPath "lib/pkgconfig"
          self.bundles.${system}.headers
        )}:$PKG_CONFIG_PATH";

      makeRuntimePackagesWrapper =
        {
          system,
          program-path,
          output-name, 
          runtimePackages ? self.bundles.${system}.runtimePackages,
          environment ? "",
          arguments ? "",
        }:
        let
          rpathString = "${makeRpath runtimePackages}";
        in
        nixpkgs.legacyPackages.${system}.writeShellScriptBin "${output-name}" ''
          ${environment}
          export RUSTFLAGS="${rpathString} $RUSTFLAGS"
          exec ${program-path} ${arguments} "$@"
        '';

      makeToolchainWrapper =
        {
          system,
          rust-toolchain ? (nixpkgs.legacyPackages.${system}
            .rust-bin.nightly.latest.default.override {
              inherit (self.config) targets;
              extensions = [ "rust-src" "rust-analyzer" ];
            }),
          runtimePackages ? self.bundles.${system}.runtimePackages,
          buildPackages ? self.bundles.${system}.buildPackages,
          config ? self.config,
        }:
        let
          inherit (config)
            windows macos
            baseEnvironment targetEnvironment
            localFlags crossFlags;
          pkgs = nixpkgs.legacyPackages.${system};
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
    };

    bundles =
      self.lib.forSystems self.config.systems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          linuxOptionals = option:
            optionals (pkgs.stdenv.isLinux && option);
        in rec {
        runtimePackages =
          optionals (pkgs.stdenv.isLinux)
            (with pkgs; [
              alsa-lib-with-plugins
              libxkbcommon
              udev
            ])
          ++ linuxOptionals self.config.linux.runtime.vulkan.enable
            [ pkgs.vulkan-loader ]
          ++ linuxOptionals self.config.linux.runtime.opengl.enable
            [ pkgs.libGL ]
          ++ linuxOptionals self.config.linux.runtime.wayland.enable
            [ pkgs.wayland ]
          ++ linuxOptionals self.config.linux.runtime.xorg.enable
            (with pkgs.xorg; [
              libX11
              libXcursor
              libXi
              libXrandr
            ]);

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
      }
    );

  packages =
    forSystems self.config.systems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
      in {
      rust-toolchain-nightly = self.lib.makeToolchainWrapper {
        inherit system;
        config =
          self.config // {
            crossFlags =
              self.config.crossFlags ++ [
                "-Zlinker-features=-lld"
                "-Zlocation-detail=none"
              ];
          };
        rust-toolchain =
          pkgs.rust-bin.nightly.latest.default.override {
            inherit (self.config) targets;
            extensions = [ "rust-src" "rust-analyzer" ];
          };
      };

      rust-toolchain-stable = self.lib.makeToolchainWrapper {
        inherit system;
        rust-toolchain =
          pkgs.rust-bin.stable.latest.default.override {
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
          self.lib.makeRuntimePackagesWrapper {
            inherit system;
            program-path = "${dioxus}/bin/dx";
            output-name = "dx";
          };
    });
  };
}
