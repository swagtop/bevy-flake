{
  description = "A flake for painless development and distribution of Bevy projects.";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (builtins)
        isFunction
        concatStringsSep
        warn
        ;
      inherit (nixpkgs.lib)
        makeOverridable
        optionals
        optionalString
        genAttrs
        makeSearchPath
        ;

      eachSystem = genAttrs [
        "aarch64-linux"
        "aarch-darwin"
        "x86_64-linux"
      ];

      mkBf =
        overridedConfig:
        let
          packages = eachSystem (
            system:
            let
              builtConfig = import ./config.nix { inherit system nixpkgs; };
              inherit (builtConfig) pkgs;
              config = builtConfig.config // overridedConfig;
            in
            import ./packages.nix {
              inherit pkgs nixpkgs config;
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
          inherit packages devShells formatter;
        };
    in
    makeOverridable mkBf {};
  # mkBf (_: {
  #   templates = {
  #     nixpkgs = warn "This template does not support any cross-compilation." {
  #       path = ./templates/nixpkgs;
  #       description = "Get the Rust toolchain from nixpkgs.";
  #     };
  #     rust-overlay = {
  #       path = ./templates/rust-overlay;
  #       description = "Get the Rust toolchain through oxalica's rust-overlay.";
  #     };
  #     fenix = {
  #       path = ./templates/fenix;
  #       description = "Get the Rust toolchain through nix-community's fenix.";
  #     };
  #   };

  #   formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
  # });
}
