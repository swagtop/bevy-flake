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
}:

let
  inherit (builtins)
    attrNames
    concatStringsSep
    ;

  inherit (pkgs.lib)
    genAttrs
    makeSearchPath
    mapAttrsToList
    optionals
    optionalString
    subtractLists
    ;

  validTargets =
    subtractLists
      # Disable cross-compilation for MacOS and Windows targets, if their SDK
      # are not present in the config.
      (optionals (macos.sdk == null) macos.targets ++ optionals (windows.sdk == null) windows.targets)
      (
        let
          usingDefaultToolchain = rustToolchain.bfDefaultToolchain or false;
        in
        if usingDefaultToolchain then
          # Disable cross-compilation in 'targets' if using the default
          # toolchain, as it doesn't have any of the stdlibs other than for
          # the system it is built for.
          [
            pkgs.stdenv.hostPlatform.rust.rustcTarget
          ]
        else
          attrNames targetEnvironments
      );

  exportEnv =
    env: concatStringsSep "\n" (mapAttrsToList (name: val: "export ${name}=\"${val}\"") env);
in
config
// {
  rustToolchain = rustToolchain validTargets;

  sharedEnvironment = pkgs.writeTextFile {
    name = "bevy-flake-shared-environment.bash";
    text = exportEnv sharedEnvironment;
    passthru.env = sharedEnvironment;
  };

  devEnvironment = pkgs.writeTextFile (
    let
      env = 
        devEnvironment
        // {
          PKG_CONFIG_PATH =
            "${devEnvironment.PKG_CONFIG_PATH or ""}:"
            + makeSearchPath "lib/pkgconfig" (map (p: p.dev or null) runtimeInputs);
          RUSTFLAGS =
            "${devEnvironment.RUSTFLAGS or ""} "
            + optionalString pkgs.stdenv.isLinux "-C link-args=-Wl,-rpath,${makeSearchPath "lib" runtimeInputs}";
        };
    in
    {
      name = "bevy-flake-dev-environment.bash";
      text = exportEnv env;
      passthru = { inherit env; };
    }
  );

  targetEnvironments = genAttrs validTargets (
    target:
    pkgs.writeTextFile (
      let
        env = 
          targetEnvironments.${target}
          // {
            RUSTFLAGS =
              "${targetEnvironments.${target}.RUSTFLAGS or ""} "
              + concatStringsSep " " (config.crossPlatformRustflags or [ ]);
          };
      in
      {
        name = "bevy-flake-${target}-environment.bash";
        text = exportEnv env;
        passthru = { inherit env; };
      }
    )
  );
}
