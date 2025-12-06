{
  nixpkgs,
  pkgs,
  config,
}:
let
  inherit (builtins)
    attrNames
    concatStringsSep
    warn
    ;
  inherit (nixpkgs.lib)
    attrsToList
    genAttrs
    importTOML
    makeOverridable
    optionalAttrs
    optionals
    subtractLists
    ;
  inherit (config)
    src
    systems
    rustToolchainFor
    macos
    targetEnvironments
    ;

  wrapExecutable = (import ./wrapper.nix config) pkgs;

  targets = attrNames targetEnvironments;
  input-rust-toolchain = rustToolchainFor targets;
  wrapped-rust-toolchain =
    (wrapExecutable {
      name = "cargo";
      executable = input-rust-toolchain + "/bin/cargo";
      symlinkPackage = input-rust-toolchain;
    })
    // {
      inherit wrapExecutable;
      unwrapped = input-rust-toolchain;

      # Attributes needed for 'makeRustPlatform' compatibility.
      targetPlatforms = systems;
      badTargetPlatforms = [ ];
    };
in
{
  rust-toolchain = wrapped-rust-toolchain;

  dioxus-cli = makeOverridable wrapExecutable {
    name = "dx";
    executable = pkgs.dioxus-cli + "/bin/dx";
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
          PKG_CONFIG_PATH = pkgs.openssl.dev + "/lib/pkgconfig";
          cargoLock.lockFile = src + "/Cargo.lock";
          doCheck = false;
        }
      );
    in
    makeOverridable wrapExecutable {
      name = "bevy";
      extraRuntimeInputs = [
        pkgs.binaryen
      ];
      executable = bevy-cli-package + "/bin/bevy";
      argParser =
        default:
        default
        + ''
          if [[ $2 == "web" ]]; then
            export BF_TARGET="wasm32-unknown-unknown"
          fi
        '';
    };
}
# If 'src' is defined in config, add the 'targets' package, which builds
# every target defined in targetEnvironments. Individual targets can be built
# with 'targets.target-triple', eg. 'targets.wasm32-unknown-unknown'.
// optionalAttrs (src != null) {
  targets = makeOverridable (
    overridedAttrs:
    let
      usingDefaultToolchain =
        if (input-rust-toolchain ? bfDefaultToolchain) then
          input-rust-toolchain.bfDefaultToolchain
        else
          false;

      manifest = (importTOML "${src}/Cargo.toml").package;
      packageNamePrefix =
        if (manifest ? version) then "${manifest.name}-${manifest.version}-" else "${manifest.name}-";

      rustPlatform = pkgs.makeRustPlatform {
        cargo = wrapped-rust-toolchain;
        rustc = wrapped-rust-toolchain;
      };
      validTargets =
        subtractLists
          # Disable cross-compilation for MacOS targets, if the SDK is not
          # present in the config.
          (optionals (macos.sdk == null) [
            "aarch64-apple-darwin"
            "x86_64-apple-darwin"
          ])
          (
            if usingDefaultToolchain then
              # Disable cross-compilation in 'targets' if using the default
              # toolchain, as it doesn't have any of the stdlibs other than for
              # the system it is built for.
              [
                pkgs.stdenv.hostPlatform.config
              ]
            else
              (attrNames targetEnvironments)
          );

      everyTarget = genAttrs validTargets (
        target:
        rustPlatform.buildRustPackage (
          {
            inherit src target;

            name = packageNamePrefix + target;

            nativeBuildInputs = [ wrapped-rust-toolchain ];

            cargoLock.lockFile = src + "/Cargo.lock";
            cargoProfile = "release";
            cargoBuildFlags = [ ];

            buildPhase = ''
              runHook preBuild

              cargo build \
                -j "$NIX_BUILD_CORES" \
                --profile "$cargoProfile" \
                --target "$target" \
                --offline \
                ''${cargoBuildFlags[@]}

              runHook postBuild
            '';

            # Copied and edited for multi-target purposes from nixpkgs Rust hooks.
            installPhase = ''
              runHook preInstall

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

              runHook postInstall
            '';

            dontAutoPatchelf = true;
            doCheck = false;
          }
          // overridedAttrs
        )
      );

      defaultToolchainWarn =
        i:
        if usingDefaultToolchain then
          warn (
            "Only building for your system, as you are using the default"
            + " toolchain, which does not support cross-compilation."
          ) i
        else
          i;

      full-build = pkgs.stdenvNoCC.mkDerivation (
        let
          buildList = (attrsToList everyTarget);
        in
        {
          # Only warn about default toolchain when building all targets.
          name = defaultToolchainWarn (packageNamePrefix + "all-targets");

          linkBuilds = true;
          buildInputs = map (build: build.value) buildList;
          installPhase = ''
            mkdir -p $out

            if [[ $linkBuilds == "1" ]]; then
              ${concatStringsSep "\n" (
                map (build: "ln -s \"${build.value}\" $out/\"${build.name}\"") buildList
              )}
            else
              ${concatStringsSep "\n" (
                map (build: "cp -r \"${build.value}\" $out/\"${build.name}\"") buildList
              )}
            fi
          '';

          phases = [ "installPhase" ];
        }
      );
    in
    full-build // everyTarget
  ) { };
}
