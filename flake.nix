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
      assembleConfigs =
        configList: pkgs:
        builtins.foldl' (
          acc: config:
          (
            acc
            // (
              if isFunction config then
                config {
                  inherit pkgs;
                  previous = acc;
                  default = defaultConfig { inherit pkgs; };
                }
              else
                config
            )
          )
        ) { } configList;

      mkBf =
        configListInput:
        let
          # We don't have a 'pkgs' yet, so we pass an empty attribute set.
          # This is why 'systems' is the only config attribute that cannot
          # reference 'pkgs'.
          inherit (assembleConfigs configListInput { }) systems;

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
              config = assembleConfigs configListInput pkgs;
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
            systems
            eachSystem
            ;
        };

      makeConfigurable =
        f: addedConfig: previousConfigs:
        let
          configs = previousConfigs ++ [ addedConfig ];
          result = f configs;
        in
        result
        // {
          configure =
            nextAddedConfig:
            makeConfigurable f nextAddedConfig configs;
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
