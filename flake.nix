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
        filter
        ;

      applyIfFunction = f: input: if isFunction f then f input else f;
      genAttrs =
        attrList: f:
        foldl' (
          accumulator: attribute:
          accumulator
          // {
            ${attribute} = f attribute;
          }
        ) { } attrList;

      defaultConfig = import ./config.nix nixpkgs;
      assembleConfigs =
        configList: system: pkgs:
        let
          configInputs = {
            inherit pkgs system;
            default = defaultConfig { inherit system pkgs; };
          };
          helpersNoPrevious = import ./helpers.nix configInputs;
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
                  helpers = helpersNoPrevious accumulator;
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

      defaultFlake = {
        perSystem =
          {
            pkgs,
            packages,
            system,
            formatter,
            ...
          }:
          {
            inherit packages formatter;
            devShells.default = pkgs.mkShell {
              name = "bevy-flake";
              packages = [
                packages.rust-toolchain.develop
                packages.dioxus-cli.develop
                # packages.bevy-cli.develop
              ];
            };
          };
      };

      mkFlake = (
        configList: flake:
        let
          pkgsWarn = throw (
            "You cannot reference 'pkgs' and 'lib' from the config inputs in "
            + "'systems' or 'withPkgs'.\n"
            + "If you're using a 'lib' function, use 'nixpkgs.lib' instead."
          );

          systemWarn = throw "You cannot reference 'system' from the config inputs in 'systems'.";

          finalConfigList =
            let
              throwExplain =
                string:
                throw (
                  "'bevy-flake.lib.mkFlake' is not identical to 'flake-parts.lib.mkFlake'.\n"
                  + "It is merely mimicking its interface for ease-of-use.\n\n"
                  + string
                );
            in
            if isFunction flake then
              throwExplain (
                "It will not work with anything more complicated than the input:\n\n"
                + "{\n  config = <config>;\n  perSystem = <function>;\n  flake = <attrs>;\n}"
              )
            else if flake ? systems then
              throwExplain "Set systems with '{ config.systems = [ <system> ]; }'."
            else if flake ? imports then
              throwExplain "Use flake-parts for features like 'imports'."
            else
              configList ++ [ flake.config or { } ];
          assembledConfig = assembleConfigs finalConfigList;

          systems = (assembledConfig systemWarn pkgsWarn).systems;
        in
        foldl'
          (
            accumulator: system:
            let
              pkgs = applyIfFunction (assembledConfig system pkgsWarn).withPkgs system;

              systemAttrs =
                let
                  systemAttrsInputs = {
                    inherit pkgs system;
                    inherit (pkgs) lib;
                    formatter = pkgs.nixfmt-tree;
                    packages = import ./packages.nix {
                      # Now we have a 'pkgs' to assemble the configs with.
                      inherit
                        pkgs
                        assembleConfigs
                        applyIfFunction
                        defaultFlake
                        ;
                      reconfigure = (mkFlake finalConfigList defaultFlake).configure;
                      config = assembledConfig system pkgs;
                    };
                  };
                in
                flake.perSystem systemAttrsInputs;
            in
            accumulator
            # Poperly merge perSystem attributes.
            //
              genAttrs
                (filter (attr: systemAttrs ? ${attr}) [
                  "apps"
                  "checks"
                  "devShells"
                  "formatter"
                  "legacyPackages"
                  "packages"
                ])
                (
                  attribute:
                  accumulator.${attribute} or { }
                  // {
                    ${system} = systemAttrs.${attribute} or { };
                  }
                )
          )
          (
            {
              inherit systems;
              forSystems = warn "forSystems if being moved to lib.forSystems." (genAttrs systems);
              lib = {
                forSystems = genAttrs systems;
                mkFlake = mkFlake finalConfigList;
              };
              configure = newConfig: mkFlake (finalConfigList ++ [ newConfig ]) flake;
            }
            // flake.flake or { }
          )
          systems
      );
    in
    mkFlake [ defaultConfig ] defaultFlake
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
        nixpkgs = warn "The nixpkgs template does not support any cross-compilation." {
          path = ./templates/nixpkgs;
          description = "Get the Rust toolchain from nixpkgs, no cross-compilation.";
        };
      };
    };
}
