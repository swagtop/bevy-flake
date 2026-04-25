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
  wrapped-bevy-cli,
}:

let
  inherit (builtins) warn;
  inherit (pkgs.lib) importTOML;

  manifest = (importTOML "${src}/Cargo.toml").package or { name = "no-name"; };
  packageNamePrefix =
    if manifest ? version then "${manifest.name}-${manifest.version}-" else "${manifest.name}-";
  webToolchain = wrapped-rust-toolchain.override {
    disableDevelop = true;
    targets = [ "wasm32-unknown-unknown" ];
  };
  webRustPlatform = pkgs.makeRustPlatform {
    cargo = webToolchain;
    rustc = webToolchain;
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
  webRustPlatform.buildRustPackage {
    inherit src;

    name = packageNamePrefix + "web";
    nativeBuildInputs = [
      (wrapped-bevy-cli.override {
        disableDevelop = true;
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

    env.BF_TARGET = "wasm32-unknown-unknown";

    buildPhase = ''
      runHook preBuild

      bevy --version
      bevy build -j $NIX_BUILD_CORES --frozen web ''${bevyBuildFlags[@]}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      cp -r target/bevy_web/web/"${manifest.name}" $out

      runHook postInstall
    '';

    passthru.appliedConfig = appliedConfig // { rustToolchain = webToolchain; };
  }
