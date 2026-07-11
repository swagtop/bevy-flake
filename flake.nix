{
  description = "A flake for painless development and distribution of Bevy projects.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    inputs:
    let
      inherit (builtins)
        filter
        foldl'
        isFunction
        mapAttrs
        warn
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

      # The only place where 'inputs' is used is to set 'withPkgs' in here.
      defaultConfig = import ./config.nix inputs;

      # Merge all individual configs into one, from oldest to newest.
      assembleConfigs =
        configList: system: pkgs:
        let
          configInputs = {
            inherit pkgs system;
            default = defaultConfig { inherit system pkgs; };
          };
          helpersWithoutPrevious = import ./helpers.nix configInputs;
        in
        foldl' (
          accumulator: config:
          accumulator
          // (
            let
              previous = accumulator;
              step = applyIfFunction config (
                configInputs
                // {
                  inherit previous;
                  helpers = helpersWithoutPrevious previous;
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

      # Output of this flake.
      defaultFlake = {
        perSystem =
          {
            pkgs,
            system,
            packages,
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

      mkFlake =
        configList: flake:
        let
          # Use placeholder values with error messages for proper configuration
          # initialization.
          # To get the 'pkgs', we need to have the 'system', and to get that we
          # need to have 'systems' from the config, without any of these
          # values present. This is why we use these placeholder values.
          placehold = {
            pkgs = throw (
              "You cannot reference 'pkgs' and 'lib' from the config inputs in "
              + "'systems' or 'withPkgs'.\n"
              + "If you're using a 'lib' function, use 'nixpkgs.lib' instead."
            );

            system = throw "You cannot reference 'system' from the config inputs in 'systems'.";
          };

          # Check if the user is trying to use flake-parts features that aren't
          # supported by bevy-flake.
          assertProperUsage =
            expression:
            let
              assertMsg =
                pred: msg:
                pred
                || throw (
                  "'bevy-flake.lib.mkFlake' is not identical to 'flake-parts.lib.mkFlake'.\n"
                  + "It is merely mimicking its interface for ease-of-use.\n\n"
                  + msg
                );
            in
            assert assertMsg (!isFunction flake) (
              "It will not work with anything more complicated than the input:\n\n"
              + "{\n  config = <config>;\n  perSystem = <function>;\n  flake = <attrs>;\n}"
            );
            assert assertMsg (!flake ? systems) "Set systems with '{ config.systems = [ <system> ]; }'.";
            assert assertMsg (!flake ? imports) "Use flake-parts for features like 'imports'.";
            assert assertMsg (
              !flake ? inputs
            ) "Remove '{ inherit inputs; }', or use flake-parts for this feature.";
            expression;

          # Assert proper usage before we move on to assembling configs.
          finalConfigList = assertProperUsage (configList ++ [ flake.config or { } ]);

          assembledConfig = assembleConfigs finalConfigList;

          inherit (assembledConfig placehold.system placehold.pkgs) systems;
        in
        foldl'
          (
            accumulator: system:
            let
              pkgs = applyIfFunction (assembledConfig system placehold.pkgs).withPkgs system;

              systemAttrs =
                let
                  systemAttrsInputs = {
                    inherit (pkgs) lib;
                    inherit pkgs system;
                    formatter = pkgs.nixfmt-tree;

                    # Import packages with final configuration.
                    packages = import ./packages.nix {
                      inherit pkgs applyIfFunction;
                      reconfigure = (mkFlake finalConfigList defaultFlake).configure;
                      rawConfig = assembledConfig system pkgs;
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
            let
              lib = {
                inherit systems;
                forSystems = genAttrs systems;
                configure = newConfig: mkFlake (finalConfigList ++ [ newConfig ]) flake;
              };
            in
            mapAttrs (
              name: value:
              warn (
                "The 'bevy-flake.${name}' attribute has moved to "
                + "'bevy-flake.lib.${name}', and will be removed from top "
                + "level flake outputs at the date '2027-01-01'."
              ) value
            ) lib
            // flake.flake or { }
            // {
              lib = lib // { mkFlake = mkFlake finalConfigList; } // (flake.flake or { }).lib or { };
            }
          )
          systems;
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
