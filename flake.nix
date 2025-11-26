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
        configList: pkgs:
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
        ) { } configList;

      mkBf =
        configList:
        let
          configNoPkgs = assembleConfigs configList (
            # Because the 'pkgs' that can be input into the configs rely on the
            # 'systems' config attribute, we have to get systems without
            # passing in any 'pkgs' first.
            # Because of lazy evaluation, this will not be a problem, unless
            # 'pkgs' is referenced in 'systems' or 'pkgsFor'.
            # A helpful error is thrown, should this ever happen.
            throw (
              "You cannot reference 'pkgs' from the config inputs in 'systems'"
              + " or 'pkgsFor'.\nIf you're using a 'pkgs.lib' function, get it"
              + " through 'nixpkgs.lib' instead."
            )
          );

          eachSystem = genAttrs configNoPkgs.systems;
          packages = eachSystem (
            system:
            let
              pkgs = configNoPkgs.pkgsFor system;
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
            (configNoPkgs)
            systems;
          inherit
            devShells
            eachSystem
            formatter
            packages
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
