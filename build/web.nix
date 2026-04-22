config@{
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
  appliedConfig,

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
    crossCompileOnly = true;
    targets = [ "wasm32-unknown-unknown" ];
  };
  webRustPlatform = pkgs.makeRustPlatform {
    cargo = webToolchain;
    rustc = webToolchain;
  };
in
if src == null then
  warn "You have not configured any 'src' to build." (
    pkgs.writeShellScriptBin "bevy-flake-no-src" ''
      echo "You do not have any bevy!!!"
    ''
  )
else
  webRustPlatform.buildRustPackage {
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

    env.BF_TARGET = "wasm32-unknown-unknown";

    buildPhase = ''
      runHook preBuild

      bevy --version
      bevy build -j $NIX_BUILD_CORES web ''${bevyBuildFlags[@]}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      cp -r target/bevy_web/web/"${manifest.name}" $out

      runHook postInstall
    '';

    passthru = {
      inherit appliedConfig;
    };
  }
