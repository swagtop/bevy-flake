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
      headersFor makeRuntime makeSearchPathLite
      makeRpath makeFlagString makePkgconfigPath makeSwitchCases ;
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

    eachSystem = genAttrs systems;
  in {
    inherit systems targets eachSystem; 

    devShells = eachSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        name = "bevy-flake";
        packages = [
          self.packages.${system}.default
          self.packages.${system}.dioxus-cli
        ];
      };
    });

    config = {
      linux = {
        devRuntime = {
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
      targetEnvironment = {
        "x86_64-unknown-linux-gnu" = '''';
        "aarch64-unknown-linux-gnu" = '''';
        "x86_64-pc-windows-msvc" = '''';
        "aarch64-pc-windows-msvc" = '''';
        "x86_64-apple-darwin" = '''';
        "aarch64-apple-darwin" = '''';
        "wasm32-unknown-unknown" = '''';
      };
    };

    packages = eachSystem (system: rec {
      default =
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };
        in
          self.wrapToolchain {
            rust-toolchain = 
              pkgs.rust-bin.stable.latest.default.override (old: {
                inherit targets;
                extensions = [ "rust-src" "rust-analyzer" ];
              });
          };

      # Does not currently work properly on MacOS systems.
      dioxus-cli = self.wrapPackageBinPath (
        let
          dx = nixpkgs.legacyPackages.${system}.dioxus-cli.override (old: {
            rustPlatform = old.rustPlatform // {
              buildRustPackage = args:
                old.rustPlatform.buildRustPackage (
                  args // {
                    src = old.fetchCrate {
                      pname = "dioxus-cli";
                      version = "0.7.0-rc.0";
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
        in {
          package = dx;
          name = "dx";
        });
    });

    wrapPackageBinPath =
      {
        package,
        name,
        alias ? null,
        config ? self.config,
        extra ? { runtime = []; build = []; headers = []; },
      }:
      let
        inherit (config)
          localFlags baseEnvironment;
        system = package.system;
        pkgs = nixpkgs.legacyPackages.${system};
        runtime = makeRuntime config system extra;
      in
        pkgs.writeShellScriptBin "${if alias != null then alias else name}" ''
          ${optionalString pkgs.stdenv.isLinux ''
            export PKG_CONFIG_PATH="${
              makePkgconfigPath ((headersFor system) ++ extra.headers)
            }"
            export RUSTFLAGS="${
              makeRpath (runtime ++ extra.runtime)
            } $RUSTFLAGS"
          ''}
          ${baseEnvironment}
          export RUSTFLAGS="${makeFlagString localFlags} $RUSTFLAGS"
          exec ${package}/bin/${name} "$@"
        '';
      

    wrapToolchain =
      {
        rust-toolchain,
        config ? self.config,
        extra ? { runtime = []; build = []; headers = []; },
      }:
      let
        inherit (config)
          windows macos
          baseEnvironment targetEnvironment
          localFlags crossFlags;
        system = rust-toolchain.system;
        pkgs = nixpkgs.legacyPackages.${system};
        devHeadersPath = makePkgconfigPath (headersFor system);
        runtime = makeRuntime config system extra;
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

          # Make sure right linker is used for target..
          case $BEVY_FLAKE_TARGET in
            *-unknown-linux-gnu*)
              # Clean glibc version from BEVY_FLAKE_TARGET string.
              if [[ "$BEVY_FLAKE_TARGET" =~ 'aarch64' ]]; then
                BEVY_FLAKE_TARGET="aarch64-unknown-linux-gnu"
              elif [[ "$BEVY_FLAKE_TARGET" =~ 'x86_64' ]]; then
                BEVY_FLAKE_TARGET="x86_64-unknown-linux-gnu"
              fi
            ;&
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
              ${optionalString pkgs.stdenv.isLinux ''
                  RUSTFLAGS="${makeRpath (runtime ++ extra.runtime)} $RUSTFLAGS"
              ''}
              export PKG_CONFIG_PATH="${
                devHeadersPath + ":" + (makePkgconfigPath extra.headers)
              }"
              RUSTFLAGS="${makeFlagString localFlags} $RUSTFLAGS"
            ;;

            # Unfold targetEnvironment set into cases.
            ${let
                macosBase = ''
                  if [ "$MACOS_SDK_DIR" = "" ]; then
                    printf "%s%s\n" \
                      "bevy-flake: Building to MacOS target without SDK, " \
                      "compilation will most likely fail." 1>&2
                  fi
                  FRAMEWORKS="$MACOS_SDK_DIR/System/Library/Frameworks";
                  export SDKROOT="$MACOS_SDK_DIR"
                  export COREAUDIO_SDK_PATH="$FRAMEWORKS/CoreAudio.framework/Headers"
                  export BINDGEN_EXTRA_CLANG_ARGS="${
                    makeFlagString [
                      "--sysroot=$MACOS_SDK_DIR"
                      "-F $FRAMEWORKS"
                      "-I$MACOS_SDK_DIR/usr/include"
                    ]
                  }"
                  RUSTFLAGS="${
                    makeFlagString [
                      "-L $MACOS_SDK_DIR/usr/lib"
                      "-L framework=$FRAMEWORKS"
                      "$RUSTFLAGS"
                    ]
                  }"
                '';
              in
                # Set up default bases for environments.
                makeSwitchCases crossFlags (
                  nixpkgs.lib.zipAttrsWith (name: values:
                    builtins.concatStringsSep "\n" values
                  ) [
                    {
                      "x86_64-unknown-linux-gnu" = ''
                        export PKG_CONFIG_PATH="${
                          if (system == "x86_64-linux") then
                            devHeadersPath
                          else
                            makePkgconfigPath (headersFor "x86_64-linux")
                        }"
                      '';
                      "aarch64-unknown-linux-gnu" = ''
                        export PKG_CONFIG_PATH="${
                          if (system == "aarch64-linux") then
                            devHeadersPath
                          else
                            makePkgconfigPath (headersFor "aarch64-linux")
                        }"
                      '';
                      "x86_64-apple-darwin" = macosBase;
                      "aarch64-apple-darwin" = macosBase;
                      "wasm32-unknown-unknown" = ''
                        RUSTFLAGS="${makeFlagString [
                          "--cfg getrandom_backend=\\\"wasm_js\\\""
                          "$RUSTFLAGS"
                        ]}"
                      '';
                    }
                    targetEnvironment
                  ]
                )}
          esac

          # Run cargo with relevant RUSTFLAGS.
          RUSTFLAGS="$RUSTFLAGS" exec ${rust-toolchain}/bin/cargo "$@"
        '';
      in
        pkgs.symlinkJoin {
          name = "bevy-flake-wrapped-toolchain";
          pname = "cargo";
          ignoreCollisions = true;
          paths = with pkgs; [
            cargo-wrapper
            cargo-zigbuild
            cargo-xwin
            pkg-config
            rust-toolchain
          ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = with pkgs; [
            rust-toolchain
            libclang.lib
          ];
          postBuild = ''
            wrapProgram $out/bin/cargo \
              --prefix PATH : \ ${
                  makeSearchPathLite "bin" ([
                    rust-toolchain
                    pkgs.cargo-zigbuild
                    pkgs.cargo-xwin
                  ]
                  ++ optionals (pkgs.stdenv.isLinux) [ pkgs.stdenv.cc ]
                  ++ extra.build
                )} \
              --prefix PKG_CONFIG_PATH : \ ${
                 makePkgconfigPath
                   (optionals pkgs.stdenv.isDarwin [ pkgs.darwin.libiconv.dev ])
                }
          '';
        };

    lib = {
      makeSearchPathLite = path: list:
        "${builtins.concatStringsSep "/${path}:"
          (map (package: package.outPath) list)}/${path}";
      
      # Make rustflag that sets rpath to searchpath of input packages.
      # This is what is used instead of LD_LIBRARY_PATH.
      makeRpath = packages:
        "-C link-args=-Wl,-rpath,${makeSearchPathLite "lib" packages}";

      # Puts all strings in a list into a single string, with a space separator.
      makeFlagString = flags: builtins.concatStringsSep " " flags;

      # Makes a search path for 'pkg-config' made up of every package in a list.
      makePkgconfigPath = packages:
        "${makeSearchPathLite "lib/pkgconfig" packages}";

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

      makeRuntime = config: system: extra:
      let
        inherit (config) linux;
        pkgs = nixpkgs.legacyPackages.${system};
      in
        optionals (pkgs.stdenv.isLinux) (
          (with pkgs; [
            alsa-lib-with-plugins
            libxkbcommon
            udev
          ])
          ++ optionals linux.devRuntime.vulkan.enable [ pkgs.vulkan-loader ]
          ++ optionals linux.devRuntime.opengl.enable [ pkgs.libGL ]
          ++ optionals linux.devRuntime.wayland.enable [ pkgs.wayland ]
          ++ optionals linux.devRuntime.xorg.enable
            (with pkgs.xorg; [
              libX11
              libXcursor
              libXi
              libXrandr
            ])
        )
        ++ extra.runtime;

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
    };
  };
}
