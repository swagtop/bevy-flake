{
  nixpkgs,
  systems,

  linux,
  windows,
  macos,

  crossPlatformRustflags,

  sharedEnvironment,
  devEnvironment,
  targetEnvironments,

  extraScript,

  mkRustToolchain,
  mkRuntimeInputs,
  mkStdenv,

  buildSource,
}:
let
  inherit (builtins)
    attrNames concatStringsSep warn throw isFunction;
  inherit (nixpkgs.lib)
    genAttrs mapAttrsToList optionalAttrs subtractLists
    optionals optionalString makeOverridable makeSearchPath;
in
  genAttrs systems (system:
  let
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        microsoftVisualStudioLicenseAccepted = true;
      };
    };
    exportEnv = env: concatStringsSep "\n"
      (mapAttrsToList (name: val: "export ${name}=\"${val}\"") env);

    targets = (attrNames targetEnvironments);
    input-rust-toolchain = mkRustToolchain targets pkgs;
    runtimeInputsBase = mkRuntimeInputs pkgs;
    stdenv = mkStdenv pkgs;

    windowsSdk = 
      pkgs.symlinkJoin {
        name = "merged-windows-sdk";
        paths = [
          pkgs.pkgsCross.x86_64-windows.windows.sdk
          pkgs.pkgsCross.aarch64-windows.windows.sdk
        ];
      };

    envWrap = {
      name,
      execPath,
      argParser ? (default: default),
      postScript ? "",
      extraRuntimeInputs ? []
    }:
    let
      runtimeInputs =
        runtimeInputsBase ++ extraRuntimeInputs ++ [
          stdenv.cc
          input-rust-toolchain
          pkgs.pkg-config
          pkgs.lld
        ];
      argParser' =
        if (isFunction argParser)
          then (argParser ''
            # Check if what the adapter is being run with.
            TARGET_ARG_NO=1
            for arg in "$@"; do
              case $arg in
                "--target")
                  # Save next arg as target.
                  TARGET_ARG_NO=$((TARGET_ARG_NO + 1))
                  eval "BF_TARGET=\$$TARGET_ARG_NO"
                  export BF_TARGET="$BF_TARGET"
                ;;
                "--no-wrapper")
                  set -- "''${@:1:$((TARGET_ARG_NO - 1))}" \
                         "''${@:$((TARGET_ARG_NO + 1))}"
                  export BF_NO_WRAPPER="1"
                  break
                ;;
              esac
              if [[ $BF_TARGET == "" ]]; then
                TARGET_ARG_NO=$((TARGET_ARG_NO + 1))
              fi
            done
          '')
          else argParser;
    in
      pkgs.writeShellApplication {
        inherit name runtimeInputs;
        bashOptions = [ "errexit" "pipefail" ];
        text = ''
          ${argParser'}
        
          if [[ $BF_NO_WRAPPER == "1" ]]; then
            exec ${execPath} "$@"
          fi

          # Set up MacOS SDK if configured.
          export BF_MACOS_SDK_PATH="${
            if (macos.sdk != null) then macos.sdk else ""
          }"

          export BF_WINDOWS_SDK_PATH="${windowsSdk}"

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
                      (env.RUSTFLAGS or "")
                        + optionalString (crossPlatformRustflags != [])
                          (" " + (concatStringsSep " " crossPlatformRustflags));
                  })}
                  ;;
                '')
              targetEnvironments)}
          esac

          ${extraScript}

          ${postScript}

          exec ${execPath} "$@"
        '';
    };

    rust-toolchain =
    let
      wrapArgs = {
        name = "cargo";
        extraRuntimeInputs = with pkgs; [ cargo-zigbuild ];
        execPath = "${input-rust-toolchain}/bin/cargo";

        argParser = default: default + ''
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

        postScript = ''
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
      };
    in 
      (makeOverridable (wrapArgsInput:
      let
        wrapped-rust-toolchain = (envWrap wrapArgsInput);
        symlinked-wrapped-rust-toolchain = 
        if (wrapArgsInput.execPath != wrapArgs.execPath)
          then throw
            "Don't override the execPath of rust-toolchain."
            + "Set it to use a different toolchain through the config."
          else
            # Merging the wrapper with the input toolchain, such that users get
            # all the useful binaries in their path, like rust-analyzer, etc.,
            # and only the 'cargo' binary is replaced by the wrapper.
            pkgs.buildEnv {
              name = "bf-wrapped-rust-toolchain";
              ignoreCollisions = true;
              paths = [
                wrapped-rust-toolchain
                input-rust-toolchain
              ];
            } // {
              inherit envWrap;
              wrapper = wrapped-rust-toolchain;
              unwrapped = input-rust-toolchain;
            };
      in
        symlinked-wrapped-rust-toolchain
      ) wrapArgs) // { targetPlatforms = systems; badTargetPlatforms = []; };
  in {
    inherit rust-toolchain;

    # For now we have to override the package for hot-reloading.
    dioxus-cli = 
    let
      version = "0.7.1";
      dioxus-cli-package = pkgs.dioxus-cli.override (old: {
        rustPlatform = old.rustPlatform // {
          buildRustPackage = args:
            old.rustPlatform.buildRustPackage (
              args // {
                inherit version;
                src = old.fetchCrate {
                  inherit version;
                  pname = "dioxus-cli";
                  hash = "sha256-tPymoJJvz64G8QObLkiVhnW0pBV/ABskMdq7g7o9f1A=";
                };
                cargoHash = "sha256-mgscu6mJWinB8WXLnLNq/JQnRpHRJKMQXnMwECz1vwc=";

                cargoPatches = [];
                buildFeatures = [];

                postPatch = "";
                checkFlags = [ "--skip" "test_harnesses::run_harness" ];
              });
        };
      });
    in
      makeOverridable envWrap {
        name = "dx";
        extraRuntimeInputs = [];
        execPath = "${dioxus-cli-package}/bin/dx";
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
      makeOverridable envWrap {
        name = "bevy";
        extraRuntimeInputs = [ pkgs.wasm-bindgen-cli_0_2_104 ];
        execPath = "${bevy-cli-package}/bin/bevy";
        argParser = default: default + ''
          if [[ $* == *" web"* ]]; then
            export BF_TARGET="wasm32-unknown-unknown"
          fi
        '';
      };
  } // optionalAttrs (buildSource != null) {
    targets = makeOverridable (overridedAttrs:
    let
      manifest = (builtins.importTOML "${buildSource}/Cargo.toml").package;
      rustPlatform = pkgs.makeRustPlatform {
        cargo = rust-toolchain;
        rustc = rust-toolchain;
      };
      allTargets = genAttrs (
        # Remove targets that cannot be built without specific configuration.
        subtractLists (
          (optionals (macos.sdk == null) [
            "aarch64-apple-darwin"
            "x86_64-apple-darwin"
          ])
        ) (attrNames targetEnvironments)
      ) (target:
        rustPlatform.buildRustPackage ({
          name = "${manifest.name}-${manifest.version}-${target}";
          version = manifest.version;

          src = buildSource;

          nativeBuildInputs = [ rust-toolchain ];

          cargoLock.lockFile = "${buildSource}/Cargo.lock";
          cargoProfile = "release";
          cargoBuildFlags = [];

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
        } // overridedAttrs)
      );

      full-build = pkgs.stdenvNoCC.mkDerivation (
      let
        buildList = (nixpkgs.lib.attrsToList allTargets);
      in {
        name = "bf-all-targets";

        nativeBuildInputs = map (build: build.value) buildList;
        installPhase = ''
          mkdir -p $out
          ${concatStringsSep "\n" (
            map (build: "ln -s \"${build.value}\" $out/\"${build.name}\"")
              buildList
          )}
        '';

        dontUnpack = true;
        dontPatch = true;
        dontBuild = true;
        dontPatchELF = true;
        dontAutoPatchelf = true;
        doCheck = false;
      });
    in 
      full-build // allTargets) {};
  }
)
