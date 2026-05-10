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

  individualTargetBuilds =
    {
      useIndividualToolchain ? false,
    }:
    genAttrs (attrNames targetEnvironments) (
      target:
      let
        targetToolchain = wrapped-rust-toolchain.overrideWrapper (
          {
            disableDevelop = true;
          }
          // optionalAttrs useIndividualToolchain {
            targets = [ target ];
          }
        );

        targetRustPlatform = pkgs.makeRustPlatform {
          cargo = targetToolchain;
          rustc = targetToolchain;
        };
      in
      targetRustPlatform.buildRustPackage {
        inherit src target;

        name = packageNamePrefix + target;

        cargoLock.lockFile = src + "/Cargo.lock";
        cargoProfile = "release";
        cargoBuildFlags = [ ];

        buildPhase = ''
          runHook preBuild

          cargo build \
            -j "$NIX_BUILD_CORES" \
            --profile "$cargoProfile" \
            --target "$target" \
            --frozen \
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

        passthru = {
          inherit (targetToolchain) appliedConfig;
          env = targetEnvironments.${target};
        };
      }
    );

  wholeBuild =
    {
      linkBuilds,
      passthru ? { },
    }:
    let
      collectiveBuilds = individualTargetBuilds { };
      buildList = attrsToList collectiveBuilds;
    in
    pkgs.stdenvNoCC.mkDerivation {
      inherit linkBuilds;

      # Only warn about default toolchain when building all targets.
      name = packageNamePrefix + "all-targets";

      nativeBuildInputs = map (build: build.value) buildList;

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
          individualBuilds = individualTargetBuilds { useIndividualToolchain = true; };
        in
        passthru
        // genAttrs (map (item: item.name) buildList) (
          attr: collectiveBuilds.${attr} // { only = individualBuilds.${attr}; }
        )
        // {
          inherit appliedConfig;

          list = buildList;
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
  wholeBuild {
    linkBuilds = true;
    passthru =
      let
        copiedWholeBuild = wholeBuild { linkBuilds = false; };
      in
      {
        copied = copiedWholeBuild;

        tarball = pkgs.stdenvNoCC.mkDerivation {
          name = packageNamePrefix + "tarball";

          src = copiedWholeBuild;

          phases = [ "installPhase" ];

          nativeBuildInputs = [ pkgs.gnutar ];

          installPhase = ''
            tar -cJf $out -C $src .
          '';
        };
      };
  }
