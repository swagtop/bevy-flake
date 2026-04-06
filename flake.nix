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
        removeAttrs
        attrNames
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
        configList: pkgs:
        let
          configInputs = {
            inherit pkgs;
            default = defaultConfig { inherit pkgs; };
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

      mkBf = makeConfigurable (
        configList:
        let
          fauxPkgs = 
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
            );
          configNoPkgs = assembleConfigs configList fauxPkgs;
          eachSystem =
            systems: f:
            foldl' (
              accumulator: system:
              let
                stepConfig = (f (genAttrs [ "system" "lib" "pkgs" "packages" ] (_: null))).config or { };
                pkgs = applyIfFunction (assembleConfigs [ configNoPkgs stepConfig ] fauxPkgs).withPkgs system;
                step = f {
                  inherit (pkgs.stdenv.hostPlatform) system;
                  inherit (pkgs) lib;
                  inherit pkgs;
                  packages = import ./packages.nix {
                    # Now we have a 'pkgs' to assemble the configs with.
                    inherit
                      pkgs
                      assembleConfigs
                      applyIfFunction
                      mkBf
                      ;
                    config = assembleConfigs configList pkgs;
                  };
                };
                result =
                  accumulator
                  //
                    genAttrs
                      [
                        "apps"
                        "checks"
                        "devShells"
                        "formatter"
                        "legacyPackages"
                        "packages"
                      ]
                      (
                        attribute:
                        accumulator.${attribute} or { }
                        // (
                          if step ? ${attribute} then
                            {
                              ${system} = step.${attribute} or { };
                            }
                          else
                            { }
                        )
                      );
              in
              removeAttrs result (filter (attr: result.${attr} == { }) (attrNames result))
            ) { } systems;
        in
        eachSystem configNoPkgs.systems (
          {
            pkgs,
            packages,
            system,
            ...
          }:
          {
            inherit packages;
            devShells.default = pkgs.mkShell {
              name = "bevy-flake";
              packages = [
                packages.rust-toolchain.develop
                packages.dioxus-cli.develop
                # packages.bevy-cli.develop
              ];
            };
            formatter = pkgs.nixfmt-tree;
          }
        )
        // {
          inherit (configNoPkgs) systems;
          forSystems = warn "forSystems if being moved to lib.forSystems." genAttrs configNoPkgs.systems;
          lib = {
            forSystems = genAttrs configNoPkgs.systems;
            eachConfigSystem = eachSystem configNoPkgs.systems;
          };
        }
      );
    in
    mkBf [ ] defaultConfig
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
