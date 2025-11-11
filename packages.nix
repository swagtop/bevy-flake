{ config, nixpkgs }:
let
  inherit (builtins)
    attrNames
    concatStringsSep
    throw
    ;
  inherit (nixpkgs.lib)
    genAttrs
    optionalAttrs
    subtractLists
    importTOML
    optionals
    optionalString
    makeOverridable
    ;
  inherit (config)
    systems
    macos
    linux
    buildSource
    ;
in
genAttrs systems (
  system:
  let
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        microsoftVisualStudioLicenseAccepted = true;
      };
    };

    wrapExecutable = import ./wrapper.nix (
      config
      // {
        inherit pkgs;
      }
    );

    rust-toolchain =
      (wrapExecutable {
        name = "cargo";
        extraRuntimeInputs = with pkgs; [ cargo-zigbuild ];
        executable = "${wrapExecutable.input-rust-toolchain}/bin/cargo";
        symlinkPackage = wrapExecutable.input-rust-toolchain;

        argParser =
          default:
          default
          + ''
            if [[ $BF_NO_WRAPPER != "1" ]]; then
               if [[ $BF_TARGET == *"-unknown-linux-gnu"* ]]; then
                 # Insert glibc version into args for Linux targets.
                 set -- \
                   "''${@:1:((TARGET_ARG_NO-1))}" \
                   "$BF_TARGET.${linux.glibcVersion}" \
                   "''${@:$((TARGET_ARG_NO+1))}"
              fi
            fi
          '';

        postPostScript = ''
          # Set linker for specific targets.
          case $BF_TARGET in
            *-apple-darwin*)
              ${optionalString (macos.sdk == null) ''
                printf "%s%s\n" \
                  "bevy-flake: Building to MacOS target without SDK, " \
                  "compilation will most likely fail." 1>&2
              ''}
            ;&
            *-unknown-linux-gnu*);&
            "wasm32-unknown-unknown")
              ${optionalString (pkgs.stdenv.isDarwin) ''
                # Stops `cargo-zigbuild` from jamming with Zig on MacOS systems.
                ulimit -n 4096
              ''}
              if [[ "$1" == "build" ]]; then
                echo "bevy-flake: Switching to 'cargo-zigbuild'" 1>&2 
                exec ${pkgs.cargo-zigbuild}/bin/cargo-zigbuild zigbuild "''${@:2}"
              fi
            ;;
          esac
        '';
      })
      // {
        targetPlatforms = systems;
        badTargetPlatforms = [ ];
      };
  in
  {
    inherit rust-toolchain;

    # For now we have to override the package for hot-reloading.
    dioxus-cli =
      let
        version = "0.7.1";
        dioxus-cli-package = pkgs.dioxus-cli.override (old: {
          rustPlatform = old.rustPlatform // {
            buildRustPackage =
              args:
              old.rustPlatform.buildRustPackage (
                args
                // {
                  inherit version;
                  src = old.fetchCrate {
                    inherit version;
                    pname = "dioxus-cli";
                    hash = "sha256-tPymoJJvz64G8QObLkiVhnW0pBV/ABskMdq7g7o9f1A=";
                  };
                  cargoHash = "sha256-mgscu6mJWinB8WXLnLNq/JQnRpHRJKMQXnMwECz1vwc=";

                  cargoPatches = [ ];
                  buildFeatures = [ ];

                  postPatch = "";
                  checkFlags = [
                    "--skip"
                    "test_harnesses::run_harness"
                  ];
                }
              );
          };
        });
      in
      makeOverridable wrapExecutable {
        name = "dx";
        extraRuntimeInputs = [ ];
        executable = "${dioxus-cli-package}/bin/dx";
      };

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
          in
          {
            inherit version src;
            name = "bevy-cli-${version}";
            nativeBuildInputs = [
              pkgs.openssl.dev
              pkgs.pkg-config
            ];
            PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
            cargoLock.lockFile = "${src}/Cargo.lock";
            doCheck = false;
          }
        );
      in
      makeOverridable wrapExecutable {
        name = "bevy";
        extraRuntimeInputs = [
          pkgs.wasm-bindgen-cli_0_2_104
          pkgs.binaryen
        ];
        executable = "${bevy-cli-package}/bin/bevy";
        argParser =
          default:
          default
          + ''
            if [[ $* == *" web"* ]]; then
              export BF_TARGET="wasm32-unknown-unknown"
            fi
          '';
      };
  }
  # If buildSource is defined in config, add the 'targets' package, which builds
  # every target defined in targetEnvironments. Individual targets can be built
  # with 'targets.target-specific-triple', eg. 'targets.wasm32-unknown-unknown'.
  // optionalAttrs (buildSource != null) {
    targets = makeOverridable (
      overridedAttrs:
      let
        manifest = (importTOML "${buildSource}/Cargo.toml").package;
        packageNamePrefix =
          if (manifest ? version) then "${manifest.name}-${manifest.version}-" else "${manifest.name}-";

        rustPlatform = pkgs.makeRustPlatform {
          cargo = rust-toolchain;
          rustc = rust-toolchain;
        };
        validTargets = subtractLists (optionals (macos.sdk == null) [
          "aarch64-apple-darwin"
          "x86_64-apple-darwin"
        ]) (attrNames wrapExecutable.targetEnvironments);

        everyTarget = genAttrs validTargets (
          target:
          rustPlatform.buildRustPackage (
            {
              name = packageNamePrefix + target;

              src = buildSource;

              nativeBuildInputs = [ rust-toolchain ];

              cargoLock.lockFile = "${buildSource}/Cargo.lock";
              cargoProfile = "release";
              cargoBuildFlags = [ ];

              buildPhase = ''
                runHook preBuild

                cargo build \
                  -j "$NIX_BUILD_CORES" \
                  --profile "$cargoProfile" \
                  --target "${target}" \
                  --offline \
                  ''${cargoBuildFlags[@]}

                runHook postBuild
              '';

              # Copied and edited for multi-target purposes from nixpkgs Rust hooks.
              installPhase = ''
                if [[ $cargoProfile == "dev" ]]; then
                  # Set dev profile environment variable to match correct directory.
                  export cargoProfile="debug"
                fi

                buildDir=target/"${target}"/"$cargoProfile"
                bins=$(find $buildDir \
                  -maxdepth 1 \
                  -type f \
                  -executable ! \( -regex ".*\.\(so.[0-9.]+\|so\|a\|dylib\)" \))
                libs=$(find $buildDir \
                  -maxdepth 1 \
                  -type f \
                  -regex ".*\.\(so.[0-9.]+\|so\|a\|dylib\)")

                mkdir -p $out/{bin,lib}

                for file in $bins; do
                  cp $file $out/bin/
                done

                for file in $libs; do
                  cp $file $out/lib/
                done

                rmdir --ignore-fail-on-non-empty $out/{bin,lib}
              '';

              # Wrapper script will not work without having a set $HOME.
              HOME = ".";

              dontPatch = true;
              dontAutoPatchelf = true;
              doCheck = false;
            }
            // overridedAttrs
          )
        );

        full-build = pkgs.stdenvNoCC.mkDerivation (
          let
            buildList = (nixpkgs.lib.attrsToList everyTarget);
          in
          {
            name = packageNamePrefix + "all-targets";

            buildInputs = map (build: build.value) buildList;
            installPhase = ''
              mkdir -p $out
              ${concatStringsSep "\n" (map (build: "ln -s \"${build.value}\" $out/\"${build.name}\"") buildList)}
            '';

            phases = [ "installPhase" ];
          }
        );
      in
      full-build // everyTarget
    ) { };
  }
)
