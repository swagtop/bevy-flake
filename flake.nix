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
          configNoPkgs = assembleConfigs configList;
          mkFlake =
            systems: f:
            foldl' (
              accumulator: system:
              let
                systemAttrsNoInput =
                  f (genAttrs [ "system" "pkgs" "packages" "formatter" ] (
                    attr:
                    throw (
                      "You are referencing ${attr} in your 'config' attribute "
                      + "of the 'mkFlake' input. These inputs are based on the "
                      + "'config', which is evaluated before everything else.\n"
                      + "Make sure you do not reference these in the 'config' "
                      + "section. Read more on how to configure properly in "
                      + "the documentation."
                    )
                  ));

                pkgs = applyIfFunction (
                  assembleConfigs [
                    configNoPkgs
                    systemAttrsNoInput.config or { }
                  ] fauxPkgs
                ).withPkgs system;

                systemAttrs =
                  let
                    systemAttrsInputs = {
                      inherit (pkgs.stdenv.hostPlatform) system;
                      inherit pkgs;
                      packages = throw "bleh";
                      formatter = pkgs.nixfmt-tree;
                    };
                    packages = import ./packages.nix {
                      # Now we have a 'pkgs' to assemble the configs with.
                      inherit
                        pkgs
                        assembleConfigs
                        applyIfFunction
                        mkBf
                        ;
                      config = assembleConfigs (configList ++ [ (f systemAttrsInputs).config or { } ]) pkgs;
                    };
                  in
                  f (systemAttrsInputs // { inherit packages; });
              in
              accumulator
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
            ) { } systems;

          systems = (assembleConfigs configList fauxPkgs).systems;
        in
        mkFlake systems (
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
          }
        )
        // {
          inherit systems;
          forSystems = warn "forSystems if being moved to lib.forSystems." genAttrs systems;
          lib = {
            forSystems = genAttrs systems;
            mkFlake = mkFlake systems;
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
