{
  description = "A flake for painless development and distribution of Bevy projects.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (builtins)
        foldl'
        isFunction
        warn
        ;
      inherit (nixpkgs.lib)
        genAttrs
        ;

      defaultConfig = import ./config.nix { inherit nixpkgs; };
      assembleConfigs =
        configs: pkgs:
        foldl' (
          accumulator: config:
          accumulator
          // (
            if isFunction config then
              config {
                inherit pkgs;
                previous = accumulator;
                default = defaultConfig { inherit pkgs; };
              }
            else
              config
          )
        ) { } configs;

      mkBf =
        configList:
        let
          systems =
            (assembleConfigs configList (
              # Because the 'pkgs' that can be used by the config relies on the
              # 'systems' config attribute, we have to get systems without
              # passing in any 'pkgs' first.
              # Because of lazy evaluation, this will not be a problem, unless
              # 'pkgs' is referenced in 'systems'.
              # A nice little error message is thrown should this ever happen.
              throw (
                "You cannot reference 'pkgs' in 'systems'.\nIf you're using a "
                + "'pkgs.lib' function, get it through 'nixpkgs.lib' instead."
              )
            )).systems;

          eachSystem = genAttrs systems;
          packages = eachSystem (
            system:
            let
              pkgs = import nixpkgs {
                inherit system;
                config = {
                  allowUnfree = true;
                  microsoftVisualStudioLicenseAccepted = true;
                };
              };
            in
            import ./packages.nix {
              inherit pkgs nixpkgs;
              # Here we have a 'pkgs' to pass in, and this will be the config
              # that is used from now on.
              config = assembleConfigs configList pkgs;
            }
          );
          devShells = eachSystem (system: {
            default = nixpkgs.legacyPackages.${system}.mkShell {
              name = "bevy-flake";
              packages = [
                packages.${system}.rust-toolchain
                packages.${system}.dioxus-cli
                # packages.${system}.bevy-cli
              ];
            };
          });

          formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
        in
        {
          inherit
            devShells
            eachSystem
            formatter
            packages
            systems
            ;
        };

      makeConfigurable =
        f: addedConfig: previousConfigs:
        let
          currentConfigs = previousConfigs ++ [ addedConfig ];
          result = f currentConfigs;
        in
        result
        // {
          configure = nextAddedConfig: makeConfigurable f nextAddedConfig currentConfigs;
        };

    in
    (makeConfigurable mkBf defaultConfig [ ])
    // {
      templates = {
        rust-overlay = {
          path = ./templates/rust-overlay;
          description = "Get the Rust toolchain through oxalica's rust-overlay.";
        };
        fenix = {
          path = ./templates/fenix;
          description = "Get the Rust toolchain through nix-community's fenix.";
        };
        nixpkgs = warn "This template does not support any cross-compilation." {
          path = ./templates/nixpkgs;
          description = "Get the Rust toolchain from nixpkgs.";
        };
      };
    };
}
