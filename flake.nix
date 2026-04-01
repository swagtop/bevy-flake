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

      applyIfFunction = f: input: if isFunction f then f input else f;
      genAttrs =
        attrList: f:
        foldl' (
          accumulator: item:
          accumulator
          // {
            ${item} = f item;
          }
        ) { } attrList;

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
          // (
            let
              step = applyIfFunction config (
                configInputs
                // {
                  previous = accumulator;
                }
              );
            in
            step
            # Update some config attributes one step up.
            // genAttrs [ "linux" "windows" "macos" "web" ] (
              attribute: accumulator.${attribute} or { } // step.${attribute} or { }
            )
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
              "You cannot reference 'pkgs' from the config inputs in 'systems' "
              + "or 'withPkgs'.\nIf you're using a 'pkgs.lib' function, get it "
              + "through 'nixpkgs.lib' instead."
            )
          );
        in
        foldl' (
          accumulator: system:
          let
            pkgs = applyIfFunction configNoPkgs.withPkgs system;
            packages.${system} = import ./packages.nix {
              # Now we have a 'pkgs' to assemble the configs with.
              inherit pkgs assembleConfigs applyIfFunction;
              config = assembleConfigs configList pkgs;
            };
            step = {
              inherit packages;
              devShells.${system}.default = pkgs.mkShell {
                name = "bevy-flake";
                packages = [
                  packages.${system}.rust-toolchain.develop
                  packages.${system}.dioxus-cli.develop
                  # packages.${system}.bevy-cli.develop
                ];
              };
              formatter.${system} = pkgs.nixfmt-tree;
            };
          in
          accumulator
          // genAttrs [ "packages" "devShells" "formatter" ] (
            attribute: accumulator.${attribute} or { } // step.${attribute}
          )
        ) { } configNoPkgs.systems
        // {
          inherit (configNoPkgs) systems;
          forSystems = genAttrs configNoPkgs.systems;
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
      # withoutDefault = (makeConfigurable mkBf [ ] { });

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
          description = "Get the Rust toolchain from nixpkgs, no cross-compilation.";
        };
      };
    };
}
