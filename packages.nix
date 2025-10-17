{
  nixpkgs,
  systems,

  linux,
  windows,
  macos,

  crossPlatformRustflags,

  sharedEnvironment,
  devEnvironment,
  targetEnvironment,

  defaultArgParser,
  extraScript,

  mkRustToolchain,
  mkRuntimeInputs,
  mkStdenv,
}:
let
  inherit (builtins)
    attrNames concatStringsSep warn;
  inherit (nixpkgs.lib)
    optionalString optionalAttrs genAttrs mapAttrsToList makeOverridable makeSearchPath;
in
  genAttrs systems (system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
    exportEnv = env: "${concatStringsSep "\n"
      (mapAttrsToList (name: val: "export ${name}=\"${val}\"") env)
    }";

    targets = (attrNames targetEnvironment);
    built-rust-toolchain = mkRustToolchain targets pkgs;
    runtimeInputsBase = mkRuntimeInputs pkgs;
    stdenv = mkStdenv pkgs;

    wrapWithEnv = {
      name,
      execPath,
      argParser ? defaultArgParser,
      postScript ? "",
      extraRuntimeInputs ? []
    }:
      pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = runtimeInputsBase ++ extraRuntimeInputs ++ [
          stdenv.cc
          built-rust-toolchain
        ];
        bashOptions = [ "errexit" "pipefail" ];
        text = ''
          ${argParser}
        
          if [[ $BF_NO_WRAPPER == "1" ]]; then
            exec ${execPath} "$@"
          fi

          # Set up MacOS SDK if configured.
          export BF_MACOS_SDK_PATH="${macos.sdk}"

          export BF_WINDOWS_SDK_PATH="${windows.sdk or ""}"

          # Set up Windows SDK and CRT if pinning is enabled.
          ${let
              cacheDirBase = (if (pkgs.stdenv.isDarwin)
                then "$HOME/Library/Caches/"
                else "\${XDG_CACHE_HOME:-$HOME/.cache/}"
              ) + "bevy-flake";
            in
              optionalString ((windows ? sdk) || (windows ? declarative)) (
                exportEnv ((optionalAttrs (windows.declarative or false) {
                  XWIN_VERSION = windows.manifestVersion;
                  XWIN_SDK_VERSION = windows.sdkVersion;
                  XWIN_CRT_VERSION = windows.crtVersion;
                } // {
                  XWIN_CACHE_DIR = cacheDirBase + (windows.sdk or (
                    "/xwin/"
                    + "manifest${windows.manifestVersion}"
                    + "-sdk${windows.sdkVersion}"
                    + "-crt${windows.crtVersion}")
                  );
                })
              ))
          }

          # Base environment for all targets.
          export PKG_CONFIG_ALLOW_CROSS="1"
          export LIBCLANG_PATH="${pkgs.libclang.lib}/lib";
          export LIBRARY_PATH="${pkgs.libiconv}/lib";
          ${exportEnv sharedEnvironment}

          case $BF_TARGET in
            "")
              ${exportEnv (devEnvironment // {
                PKG_CONFIG_PATH = (devEnvironment.PKG_CONFIG_PATH or "")
                  + makeSearchPath "lib/pkgconfig"
                    (map (p: p.dev or null)
                      (runtimeInputsBase ++ extraRuntimeInputs));
                RUSTFLAGS =
                  (devEnvironment.RUSTFLAGS or "")
                    + optionalString (pkgs.stdenv.isLinux)
                      "-C link-args=-Wl,-rpath,${makeSearchPath "lib"
                        (runtimeInputsBase ++ extraRuntimeInputs)}";
              })}
            ;;

            ${concatStringsSep "\n"
              (mapAttrsToList
                (target: env: ''
                  ${target}*)
                  ${exportEnv (env // {
                    RUSTFLAGS =
                      (env.RUSTFLAGS or "") + " "
                        + concatStringsSep " " crossPlatformRustflags;
                  })}
                  ;;
                '')
              targetEnvironment)}
          esac

          ${extraScript}

          ${postScript}

          exec ${execPath} "$@"
        '';
    };
  in {
    rust-toolchain =
    let
      target-adapter-package = wrapWithEnv {
        name = "cargo";
        extraRuntimeInputs = with pkgs; [
          cargo-zigbuild
          cargo-xwin
        ];
        execPath = "${built-rust-toolchain}/bin/cargo";

        # Insert glibc version for Linux targets.
        argParser = defaultArgParser + ''
          if [[ $BF_NO_WRAPPER != "1"
             && $BF_TARGET == *"-unknown-linux-gnu"* ]]; then
            args=("$@")
            args[TARGET_ARG_NO-1]="$BF_TARGET.${linux.glibcVersion}"
            set -- "''${args[@]}"
          fi
        '';

        postScript = ''
          ${optionalString (pkgs.stdenv.isDarwin) ''
            # Stops `cargo-zigbuild` from jamming on MacOS systems.
            ulimit -n 4096
          ''}

          # Set linker for specific targets.
          case $BF_TARGET in
            *-apple-darwin)
              ${optionalString (macos.sdk == "") ''
                printf "%s%s\n" \
                  "bevy-flake: Building to MacOS target without SDK, " \
                  "compilation will most likely fail." 1>&2
              ''}
            ;&
            *-unknown-linux-gnu*);&
            "wasm32-unknown-unknown")
              if [[ "$1" == "build" ]]; then
                echo "bevy-flake: Switching to 'cargo-zigbuild zigbuild'" 1>&2 
                shift
                exec ${pkgs.cargo-zigbuild}/bin/cargo-zigbuild zigbuild "$@"
              fi
            ;;
            *-pc-windows-msvc)
              # Set up links to /nix/store Windows SDK if configured.
              ${optionalString ((windows ? sdk) && (windows.sdk != "")) ''
                mkdir -p "$XWIN_CACHE_DIR/xwin"
                ln -sf ${windows.sdk}/* "$XWIN_CACHE_DIR/xwin/"
              ''}

              if [[ "$1" == "build" || "$1" == "run" ]]; then
                echo "bevy-flake: Switching to 'cargo-xwin xwin $1'" 1>&2 
                exec ${pkgs.cargo-xwin}/bin/cargo-xwin xwin "$@"
              fi
            ;;
          esac
        '';
      };
    in 
      (makeOverridable (target-adapter: pkgs.symlinkJoin {
        name = "bf-wrapped-rust-toolchain";
        ignoreCollisions = true;
        paths = [
          target-adapter
          built-rust-toolchain
        ];
      }) target-adapter-package);

    # For now we have to override the package for hot-reloading.
    dioxus-cli = 
    let
      version = "0.7.0-rc.1";
      dx-package = pkgs.dioxus-cli.override (old: {
        rustPlatform = old.rustPlatform // {
          buildRustPackage = args:
            old.rustPlatform.buildRustPackage (
              args // {
                inherit version;
                src = old.fetchCrate {
                  inherit version;
                  pname = "dioxus-cli";
                  hash = "sha256-Gri7gJe9b1q0qP+m0fe4eh+xj3wqi2get4Rqz6xL8yA=";
                };
                cargoHash = "sha256-+HPWgiFc7pbosHWpRvHcSj7DZHD9sIPOE3S5LTrDb6I=";

                cargoPatches = [ ];
                buildFeatures = [ ];

                postPatch = "";
                checkFlags = [ "--skip" "test_harnesses::run_harness" ];
              });
        };
      });
    in
      makeOverridable (dx: wrapWithEnv {
        name = "dx";
        extraRuntimeInputs = [ pkgs.lld ];
        execPath = "${dx}/bin/dx";
      }) dx-package;

    # For now we package 'bevy-cli' ourselves, as it is not in nixpkgs yet.
    bevy-cli =
    let
      bevy-cli-package = pkgs.rustPlatform.buildRustPackage (
      let
        version = "0.1.0-alpha.2";
        src = builtins.fetchTarball {
          url = "https://github.com/TheBevyFlock/bevy_cli/archive/refs/tags/cli-v${version}.tar.gz";
          sha256 = "sha256:02p2c3fzxi9cs5y2fn4dfcyca1z8l5d8i09jia9h5b50ym82cr8l";
        };
      in {
        inherit version src;
        name = "bevy-cli-${version}";
        nativeBuildInputs = [
          pkgs.openssl.dev
          pkgs.pkg-config
        ];
        PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
        cargoLock.lockFile = "${src}/Cargo.lock";
        doCheck = false;
      });
    in
      makeOverridable (bevy-cli:
        wrapWithEnv {
          name = "bevy";
          extraRuntimeInputs = [
            pkgs.lld
            (pkgs.wasm-bindgen-cli_0_2_104
              or (warn "Your nixpkgs is too old for bevy-cli web builds."
                pkgs.emptyDirectory)
            )
          ];
          execPath = "${bevy-cli}/bin/bevy";
          argParser = defaultArgParser + ''
            if [[ $* == *" web"* ]]; then
              export BF_TARGET="wasm32-unknown-unknown"
            fi
          '';
        }
      ) bevy-cli-package;
  })
