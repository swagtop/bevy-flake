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
    concatStringsSep
    mapAttrs
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
      overrideAttrs ? { },
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

        # Override build and install hooks with versions that use the 'target'
        # attribute instead of the values tied to the nixpkgs system.
        buildRustPackage = targetRustPlatform.buildRustPackage.override {
          cargoBuildHook = pkgs.makeSetupHook {
            name = "cargo-build-hook.sh";
            substitutions = {
              rustcTargetSpec = "$target";
              setEnv = "";
            };
          } "${pkgs.path}/pkgs/build-support/rust/hooks/cargo-build-hook.sh";

          cargoInstallHook = pkgs.makeSetupHook {
            name = "cargo-install-hook.sh";
            substitutions = {
              targetSubdirectory = "$target";
            };
          } "${pkgs.path}/pkgs/build-support/rust/hooks/cargo-install-hook.sh";
        };
      in
      (buildRustPackage {
        inherit src stdenv target;

        name = packageNamePrefix + target;

        cargoLock.lockFile = "${src}/Cargo.lock";

        cargoBuildFlags = [ ];

        dontAutoPatchelf = true;
        doCheck = false;

        passthru = {
          inherit (targetToolchain) appliedConfig;
          inherit (targetEnvironments.${target}) env;
        };
      }).overrideAttrs
        overrideAttrs
    );

  combinedBuild =
    {
      linkBuilds,
      overrideAttrs ? { },
      passthru ? { },
    }:
    let
      finalTargetBuilds = targetBuilds { inherit overrideAttrs; };

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
          individualBuilds = targetBuilds {
            inherit overrideAttrs;
            compileIndividually = true;
          };

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
