{
  description = "A flake for painless development and distribution of Bevy projects.";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (builtins)
        isFunction
        warn
        ;
      inherit (nixpkgs.lib)
        genAttrs
        ;

      defaultConfig = import ./config.nix { inherit nixpkgs; };
      configAssembler =
        configList: pkgs:
        builtins.foldl' (
          acc: configInput:
          (
            acc
            // (
              if isFunction configInput then
                configInput {
                  inherit pkgs;
                  prev = acc;
                  default = defaultConfig { inherit pkgs; };
                }
              else
                configInput
            )
          )
        ) { } configList;

      mkBf =
        configListInput:
        let
          # Get the systems to genAttrs for.
          # We don't have a 'pkgs' yet, so we pass an empty attribute set.
          # This is why only the 'systems' config cannot reference 'pkgs'.
          eachSystem = genAttrs (configAssembler configListInput { }).systems;
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
              config = configAssembler configListInput pkgs;
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
            packages
            devShells
            formatter
            eachSystem
            ;
        };

      makeConfigurable =
        f: config: prev:
        let
          new = prev ++ [ config ];
          result = f new;
        in
        result
        // {
          configure = newConfig: makeConfigurable f newConfig new;
        };

    in
    (makeConfigurable mkBf defaultConfig [ ])
    // {
      templates = {
        nixpkgs = warn "This template does not support any cross-compilation." {
          path = ./templates/nixpkgs;
          description = "Get the Rust toolchain from nixpkgs.";
        };
        rust-overlay = {
          path = ./templates/rust-overlay;
          description = "Get the Rust toolchain through oxalica's rust-overlay.";
        };
        fenix = {
          path = ./templates/fenix;
          description = "Get the Rust toolchain through nix-community's fenix.";
        };
      };
    };
}
