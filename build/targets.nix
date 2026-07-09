appliedConfig@{
  systems,
  withPkgs,
  linux,
  windows,
  macos,
  web,
  crossPlatformRustflags,
  sharedEnvironment,
  devEnvironment,
  targetEnvironments,
  extraScript,
  rustToolchain,
  runtimeInputs,
  stdenv,
  src,
}:

{
  pkgs,
  wrapped-rust-toolchain,
}:

let
  inherit (builtins)
    attrNames
    attrValues
    mapAttrs
    concatStringsSep
    warn
    ;
  inherit (pkgs.lib)
    importTOML
    genAttrs
    attrsToList
    optionalAttrs
    ;

  manifest = (importTOML "${src}/Cargo.toml").package or { name = "no-name"; };

  packageNamePrefix =
    if manifest ? version then "${manifest.name}-${manifest.version}-" else "${manifest.name}-";

  targetBuilds =
    {
      compileIndividually ? false,
    }:
    genAttrs (attrNames targetEnvironments) (
      target:
      let
        targetToolchain = wrapped-rust-toolchain.overrideWrapper (
          {
            disableDevelop = true;
          }
          // optionalAttrs compileIndividually {
            targets = [ target ];
          }
        );

        targetRustPlatform = pkgs.makeRustPlatform {
          cargo = targetToolchain;
          rustc = targetToolchain;
        };
      in
      # Here, 'buildPhase' and 'installPhase' sections are based on the
      # Rust hooks from nixpkgs found here:
      # 'nixpkgs/pkgs/build-support/rust/hooks/cargo-{build,install}-hook.sh'
      targetRustPlatform.buildRustPackage {
        inherit src stdenv target;

        name = packageNamePrefix + target;

        cargoLock.lockFile = "${src}/Cargo.lock";

        cargoBuildFlags = [ ];

        buildPhase = ''
          runHook preBuild

          echo "Building for '${target}'"

          export "CARGO_PROFILE_''${cargoBuildType@U}_STRIP"=false

          if [ -n "''${buildAndTestSubdir-}" ]; then
            CARGO_TARGET_DIR="$(pwd)/target"
            export CARGO_TARGET_DIR

            pushd "''${buildAndTestSubdir}"
          fi

          flagsArray=(
            "-j" "$NIX_BUILD_CORES"
            "--target" "$target"
            "--offline"
          )

          if [ "''${cargoBuildType}" != "debug" ]; then
            flagsArray+=("--profile" "''${cargoBuildType}")
          fi

          if [ -n "''${cargoBuildNoDefaultFeatures-}" ]; then
            flagsArray+=("--no-default-features")
          fi

          if [ -n "''${cargoBuildFeatures-}" ]; then
            flagsArray+=("--features=$(concatStringsSep "," cargoBuildFeatures)")
          fi

          concatTo flagsArray cargoBuildFlags

          echoCmd 'cargoBuildHook flags' "''${flagsArray[@]}"

          cargo build "''${flagsArray[@]}"

          if [ -n "''${buildAndTestSubdir-}" ]; then
            popd
          fi

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          if [[ $cargoBuildType == "dev" ]]; then
            # Set dev profile environment variable to match correct directory.
            export cargoBuildType="debug"
          fi

          buildDir=target/"${target}"/"$cargoBuildType"
          bins=$(find "$buildDir" \
            -maxdepth 1 \
            -type f \
            -executable ! \( -regex ".*\.\(so.[0-9.]+\|so\|a\|dylib\)" \))
          libs=$(find "$buildDir" \
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

        passthru = {
          inherit (targetToolchain) appliedConfig;
          inherit (targetEnvironments.${target}) env;
        };
      }
    );

  combinedBuild =
    {
      linkBuilds,
      overrideAttrs ? { },
      passthru ? { },
      eachTarget ? { },
    }:
    let
      overrideEachTarget = mapAttrs (name: value: value.overrideAttrs overrideAttrs);

      finalTargetBuilds = overrideEachTarget (if eachTarget == { } then targetBuilds { } else eachTarget);

      buildList = attrsToList finalTargetBuilds;
    in
    pkgs.stdenvNoCC.mkDerivation {
      inherit linkBuilds;

      # Only warn about default toolchain when building all targets.
      name = packageNamePrefix + "all-targets";

      nativeBuildInputs = attrValues finalTargetBuilds;

      phases = [ "installPhase" ];

      installPhase = ''
        mkdir -p $out

        if [[ $linkBuilds == "1" ]]; then
          COPY_OR_LINK="ln -s"
        else
          COPY_OR_LINK="cp -r"
        fi

        ${concatStringsSep "\n" (
          map (build: "$COPY_OR_LINK \"${build.value}\" $out/\"${build.name}\"") buildList
        )}
      '';

      passthru =
        let
          individualBuilds = overrideEachTarget (targetBuilds {
            compileIndividually = true;
          });

          targets = mapAttrs (name: value: value // { only = individualBuilds.${name}; }) finalTargetBuilds;
        in
        passthru
        // targets
        // {
          inherit appliedConfig targets;

          individualTargets = individualBuilds;

          list = buildList;

          overrideAttrsTargets =
            o:
            combinedBuild {
              inherit linkBuilds passthru;
              overrideAttrs = o;
              eachTarget = finalTargetBuilds;
            };
        };
    };
in
if src == null then
  warn "You have not configured any 'src' to build." (
    pkgs.writeTextFile {
      name = "bevy-flake-no-src";
      text = ''
        You have not configured 'bevy-flake' to build any 'src'.
        Set 'src' to the root path of your Bevy project.
      '';
    }
  )
else
  combinedBuild {
    linkBuilds = true;
    passthru =
      let
        copiedCombinedBuild = combinedBuild { linkBuilds = false; };

        tarballedCombinedBuild = pkgs.stdenvNoCC.mkDerivation {
          name = packageNamePrefix + "tarball";

          src = copiedCombinedBuild;

          phases = [ "installPhase" ];

          nativeBuildInputs = [ pkgs.gnutar ];

          installPhase = ''
            tar -cJf $out -C $src .
          '';
        };
      in
      {
        copied = copiedCombinedBuild;
        tarball = tarballedCombinedBuild;
      };
  }
