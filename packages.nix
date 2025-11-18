{ config, nixpkgs }:
let
  inherit (builtins)
    attrNames
    concatStringsSep
    isFunction
    ;
  inherit (nixpkgs.lib)
    genAttrs
    importTOML
    makeOverridable
    optionalAttrs
    optionals
    subtractLists
    ;
in
genAttrs (config null).systems (
  system:
  let
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        microsoftVisualStudioLicenseAccepted = true;
      };
    };

    finalConfig = if isFunction config then config pkgs else config;
    inherit (finalConfig)
      src
      linux
      macos
      systems
      ;

    wrapExecutable = import ./wrapper.nix (
      finalConfig
      // {
        inherit pkgs;
      }
    );

    rust-toolchain =
      (wrapExecutable {
        name = "cargo";
        executable = "${(finalConfig.mkRustToolchain finalConfig.targets)}/bin/cargo";
        symlinkPackage = finalConfig.mkRustToolchain finalConfig.targets;
      })
      // {
        inherit wrapExecutable finalConfig;
        targetPlatforms = systems;
        badTargetPlatforms = [ ];
      };
  in
  {
    inherit rust-toolchain;

    dioxus-cli = makeOverridable wrapExecutable {
      name = "dx";
      executable = "${pkgs.dioxus-cli}/bin/dx";
    };

    # For now we package 'bevy-cli' ourselves, as it is not in nixpkgs yet.
    bevy-cli =
      let
        bevy-cli-package = pkgs.rustPlatform.buildRustPackage (
          let
            version = "0.1.0-alpha.2";
            src = fetchTarball {
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
  # If 'src' is defined in config, add the 'targets' package, which builds
  # every target defined in targetEnvironments. Individual targets can be built
  # with 'targets.target-specific-triple', eg. 'targets.wasm32-unknown-unknown'.
  // optionalAttrs (src != null) {
    targets = makeOverridable (
      overridedAttrs:
      let
        manifest = (importTOML "${src}/Cargo.toml").package;
        packageNamePrefix =
          if (manifest ? version) then "${manifest.name}-${manifest.version}-" else "${manifest.name}-";

        rustPlatform = pkgs.makeRustPlatform {
          cargo = rust-toolchain;
          rustc = rust-toolchain;
        };
        validTargets = subtractLists (optionals (macos.sdk == null) [
          "aarch64-apple-darwin"
          "x86_64-apple-darwin"
        ]) (attrNames finalConfig.targetEnvironments);

        everyTarget = genAttrs validTargets (
          target:
          rustPlatform.buildRustPackage (
            {
              inherit src;

              name = packageNamePrefix + target;

              nativeBuildInputs = [ rust-toolchain ];

              cargoLock.lockFile = "${src}/Cargo.lock";
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
