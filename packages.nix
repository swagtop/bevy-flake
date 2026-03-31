{
  pkgs,
  config,
  assembleConfigs,
  applyIfFunction,
}:
let
  inherit (builtins)
    attrNames
    concatStringsSep
    isFunction
    elem
    warn
    ;
  inherit (pkgs.lib)
    attrsToList
    genAttrs
    importTOML
    makeOverridable
    optionalAttrs
    optionalString
    optionals
    subtractLists
    mapAttrsToList
    makeSearchPath
    ;
  inherit (config)
    macos
    windows
    rustToolchain
    src
    systems
    devEnvironment
    targetEnvironments
    ;

  applyConfig =
    config:
    let
      targets = attrNames config.targetEnvironments;
      exportEnv =
        env: concatStringsSep "\n" (mapAttrsToList (name: val: "export ${name}=\"${val}\"") env);
    in
    config
    // {
      rustToolchain =
        if isFunction rustToolchain then
          rustToolchain targets
        else
          throw (
            "The list of targets are applied to this config attribute. This should "
            + "be a function that is using the input targets when building the "
            + "Rust toolchain."
          );
      sharedEnvironment = pkgs.writeTextFile {
        name = "bevy-flake-shared-environment.bash";
        text = exportEnv config.sharedEnvironment;
      };
      devEnvironment = pkgs.writeTextFile {
        name = "bevy-flake-dev-environment.bash";
        text = exportEnv (
          devEnvironment
          // {
            PKG_CONFIG_PATH =
              "${devEnvironment.PKG_CONFIG_PATH or ""}:"
              + makeSearchPath "lib/pkgconfig" (map (p: p.dev or null) config.runtimeInputs);
            RUSTFLAGS =
              "${devEnvironment.RUSTFLAGS or ""} "
              + optionalString pkgs.stdenv.isLinux "-C link-args=-Wl,-rpath,${makeSearchPath "lib" config.runtimeInputs}";
          }
        );
      };
      targetEnvironments = genAttrs targets (
        target:
        pkgs.writeTextFile {
          name = "bevy-flake-${target}-environment.bash";
          text = exportEnv (
            targetEnvironments.${target}
            // {
              RUSTFLAGS =
                "${targetEnvironments.${target}.RUSTFLAGS or ""} "
                + concatStringsSep " " config.crossPlatformRustflags;
            }
          );
          passthru = {
            variables = targetEnvironments.${target};
          };
        }
      );
    };

  appliedConfig = applyConfig config;

  wrapExecutable = import ./wrapper.nix {
    inherit
      pkgs
      applyConfig
      assembleConfigs
      applyIfFunction
      appliedConfig
      ;
    rawConfig = config;
  };

  package-macos-sdk = pkgs.callPackage (import ./macos-sdk.nix) { };

  wrapped-rust-toolchain = wrapExecutable {
    name = "cargo";
    executable = appliedConfig.rustToolchain + "/bin/cargo";
    symlinkPackage = appliedConfig.rustToolchain;
    passthru = {
      inherit wrapExecutable package-macos-sdk;
      unwrapped = appliedConfig.rustToolchain;

      # Attributes needed for 'makeRustPlatform' compatibility.
      targetPlatforms = systems;
      badTargetPlatforms = [ ];
    };
  };

  wrapped-bevy-cli =
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
        pkgs.cargo-generate
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
in
{
  rust-toolchain = wrapped-rust-toolchain;

  dioxus-cli = makeOverridable wrapExecutable {
    name = "dx";
    executable = pkgs.dioxus-cli + "/bin/dx";
    extraRuntimeInputs = [
      # Needed for hot-reloading.
      pkgs.lld
    ];
  };

  # For now we build 'bevy-cli' from source, as it is not in nixpkgs yet.
  bevy-cli = wrapped-bevy-cli;

  # Useful tools can be reached through this package.
  tools = pkgs.writeShellScriptBin "tools" ''
    echo "bevy-flake: bla"
  ''
  // {
    inherit wrapExecutable package-macos-sdk;
  };
}
# If 'src' is defined in config, add the 'targets' package, which builds
# every target defined in 'targetEnvironments'. Individual targets can be built
# from 'targets.<target>', eg. 'targets.wasm32-unknown-unknown'.
// optionalAttrs (src != null) (
  let
    usingDefaultToolchain =
      if (appliedConfig.rustToolchain ? bfDefaultToolchain) then
        appliedConfig.rustToolchain.bfDefaultToolchain
      else
        false;

    manifest = (importTOML "${src}/Cargo.toml").package;
    packageNamePrefix =
      if (manifest ? version) then "${manifest.name}-${manifest.version}-" else "${manifest.name}-";

    validTargets =
      subtractLists
        # Disable cross-compilation for MacOS targets, if the SDK is not
        # present in the config.
        (
          optionals (macos.sdk == null) [
            "aarch64-apple-darwin"
            "x86_64-apple-darwin"
          ]
          ++ optionals (windows.sdk == null) [
            "aarch64-pc-windows-mvsc"
            "x86_64-pc-windows-mvsc"
          ]
        )
        (
          if usingDefaultToolchain then
            # Disable cross-compilation in 'targets' if using the default
            # toolchain, as it doesn't have any of the stdlibs other than for
            # the system it is built for.
            [
              pkgs.stdenv.hostPlatform.config
            ]
          else
            attrNames targetEnvironments
        );

  in
  {
    targets = makeOverridable (
      overridedAttrs:
      let
        everyTarget = genAttrs validTargets (
          target:
          let
            targetToolchain = wrapped-rust-toolchain.override {
              targets = [ target ];
            };
            targetRustPlatform = pkgs.makeRustPlatform {
              cargo = targetToolchain;
              rustc = targetToolchain;
            };
          in
          targetRustPlatform.buildRustPackage (
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

        buildList = attrsToList everyTarget;
      in
      pkgs.stdenvNoCC.mkDerivation {
        # Only warn about default toolchain when building all targets.
        name =
          (
            if usingDefaultToolchain then
              warn (
                "Only building your current system, as the default toolchain "
                + "doesn't support cross-compilation."
              )
            else
              _: _
          )
            packageNamePrefix
          + "all-targets";

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
        passthru = everyTarget // {
          list = buildList;
        };
      }
    ) { };
  }
  # Add a web build by 'bevy-cli', if "wasm32-unknown-unknown" is a valid target.
  // optionalAttrs (elem "wasm32-unknown-unknown" validTargets) {
    web =
      let
        targetToolchain = wrapped-rust-toolchain.override {
          crossCompileOnly = true;
          targets = [ "wasm32-unknown-unknown" ];
        };
        targetRustPlatform = pkgs.makeRustPlatform {
          cargo = targetToolchain;
          rustc = targetToolchain;
        };
      in
      targetRustPlatform.buildRustPackage {
        inherit src;

        name = packageNamePrefix + "web";
        nativeBuildInputs = [
          (wrapped-bevy-cli.override {
            crossCompileOnly = true;
            targets = [ "wasm32-unknown-unknown" ];
          })
        ];

        cargoLock.lockFile = src + "/Cargo.lock";

        dontFixup = true;
        doCheck = false;

        bevyBuildFlags = [
          "--bundle"
          "--wasm-opt"
          "-Oz"
          "--wasm-opt"
          "-all"
        ];

        buildPhase = ''
          runHook preBuild

          bevy --version
          bevy build web ''${bevyBuildFlags[@]}

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          cp -r target/bevy_web/web/"${manifest.name}" $out

          runHook postInstall
        '';
      };
  }
)
