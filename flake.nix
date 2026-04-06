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
        attrNames
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

      defaultFlake =
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

      mkFlake = (
        configList: f:
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

          systemAttrsNoInput = f (
            genAttrs [ "system" "pkgs" "packages" "formatter" ] (
              attr:
              throw (
                "You are referencing ${attr} in your 'config' attribute "
                + "from the 'mkFlake' input. These inputs are based on your "
                + "'config', which is evaluated before anything else.\n"
                + "Make sure you do not reference these in the 'config' "
                + "section. Read more on how to configure bevy-flake properly "
                + "in the documentation."
              )
            )
          );

          finalConfigList = (configList ++ [ systemAttrsNoInput.config or { } ]);
          finalConfig = assembleConfigs finalConfigList;
          configNoPkgs = finalConfig fauxPkgs;

          systems = (configNoPkgs).systems;
        in
        foldl'
          (
            accumulator: system:
            let
              pkgs = applyIfFunction configNoPkgs.withPkgs system;

              systemAttrs =
                let
                  systemAttrsInputs = {
                    inherit (pkgs.stdenv.hostPlatform) system;
                    inherit pkgs;
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
                      config = finalConfig pkgs;
                    };
                  };
                in
                f systemAttrsInputs;
            in
            accumulator
            // systemAttrs
            # Poperly merge flake schema attributes.
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
            // (
              if systemAttrs ? hydraJobs then
                {
                  hydraJobs = genAttrs (attrNames systemAttrs.hydraJobs) (
                    attribute:
                    (accumulator.hydraJobs or { }).${attribute} or { }
                    // {
                      ${system} = systemAttrs.hydraJobs.${attribute};
                    }
                  );
                }
              else
                { }
            )
          )
          {
            inherit systems;
            forSystems = warn "forSystems if being moved to lib.forSystems." (genAttrs systems);
            lib = {
              forSystems = genAttrs systems;
              mkFlake = mkFlake finalConfigList;
            };
            configure = c: mkFlake (finalConfigList ++ [ c ]) f;
          }
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
