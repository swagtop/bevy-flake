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

      mergeConfig =
        old: new:
        builtins.foldl' (
          acc: key:
          let
            val = new.${key};
          in
          if builtins.isAttrs val && builtins.isAttrs (old.${key} or { }) then
            acc // { ${key} = mergeConfig (old.${key}) val; }
          else if builtins.isFunction val then
            acc // { ${key} = val; }
          else
            acc // { ${key} = val; }
        ) old (builtins.attrNames new);

      mkBf =
        overridedConfig:
        let
          cfgFn = if builtins.isFunction overridedConfig then overridedConfig else (_: overridedConfig);

          packages = eachSystem (
            system:
            let
              builtConfig = import ./config.nix { inherit system nixpkgs; };
              inherit (builtConfig) pkgs;

              config = mergeConfig builtConfig.config (cfgFn {
                inherit pkgs;
                old = builtConfig.config;
              });
            in
            import ./packages.nix { inherit pkgs nixpkgs config; }
          );

          devShells = eachSystem (system: {
            default = nixpkgs.legacyPackages.${system}.mkShell {
              name = "bevy-flake";
              packages = [
                packages.${system}.rust-toolchain
                packages.${system}.dioxus-cli
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
    in
    let
      base = makeOverridable mkBf ({ });
    in
    base
    // {
      configure =
        cfgFn:
        base.override (
          prevFn:
          (
            args:
            cfgFn {
              inherit (args) pkgs;
              old = prevFn args;
            }
          )
        );
    };
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
