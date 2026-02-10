{
  description = "A flake for painless development and distribution of Bevy projects.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (builtins)
        foldl'
        isFunction
        ;
      inherit (nixpkgs.lib)
        genAttrs
        ;

      applyIfFunction = f: input: if isFunction f then f input else f;

      defaultConfig = import ./config.nix nixpkgs;
      assembleConfigs =
        configList: pkgs:
        let
          configInputs = {
            inherit pkgs;
            default = defaultConfig { inherit pkgs; };
          };
        in
        foldl' (
          accumulator: config:
          accumulator
          // applyIfFunction config (
            configInputs
            // {
              previous = accumulator;
            }
          )
        ) { } configList;

      mkBf =
        configList:
        let
          configNoPkgs = assembleConfigs configList (
            # To construct the 'forSystems' that is used in generating the rest
            # of the flake, we need to get the 'systems' config attribute before
            # anything else, as the rest of the config attributes need the
            # 'system' they are being built for.
            # This is why you cannot reference 'pkgs' in 'systems' or
            # 'withPkgs'. A helpful error is thrown, should this ever happen.
            throw (
              "You cannot reference 'pkgs' from the config inputs in 'systems'"
              + " or 'withPkgs'.\nIf you're using a 'pkgs.lib' function, get it"
              + " through 'nixpkgs.lib' instead."
            )
          );

          forSystems = genAttrs configNoPkgs.systems;

          packages = forSystems (
            system:
            let
              pkgs = applyIfFunction configNoPkgs.withPkgs system;
            in
            import ./packages.nix {
              # Now we have a 'pkgs' to assemble the configs with.
              inherit pkgs;
              config = assembleConfigs configList pkgs;
            }
          );
          devShells = forSystems (system: {
            default = nixpkgs.legacyPackages.${system}.mkShell {
              name = "bevy-flake";
              packages = [
                packages.${system}.rust-toolchain
                packages.${system}.dioxus-cli
                # packages.${system}.bevy-cli
              ];
            };
          });
          formatter = forSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
        in
        {
          inherit (configNoPkgs)
            systems
            ;
          inherit
            devShells
            formatter
            forSystems
            packages
            ;
        };

      makeConfigurable =
        f: previousConfigs: addedConfig:
        let
          currentConfigs = previousConfigs ++ [ addedConfig ];
          result = f currentConfigs;
        in
        result
        // {
          configure = makeConfigurable f currentConfigs;
        };

    in
    (makeConfigurable mkBf [ ] defaultConfig)
    // {
      withoutDefault = (makeConfigurable mkBf [ ] { });

      templates = {
        rust-overlay = {
          path = ./templates/rust-overlay;
          description = "Get the Rust toolchain through oxalica's rust-overlay.";
        };
        fenix = {
          path = ./templates/fenix;
          description = "Get the Rust toolchain through nix-community's fenix.";
        };
        nixpkgs = {
          path = ./templates/nixpkgs;
          description = "Get the Rust toolchain from nixpkgs, no cross-compilation.";
        };
      };
    };
}
