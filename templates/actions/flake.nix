{
  description = "The flake used for automatic update GitHub actions for bevy-flake.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bevy-flake = {
      url = "github:swagtop/bevy-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      bevy-flake,
      fenix,
      ...
    }:
    bevy-flake.lib.mkFlake {
      perSystem =
        {
          pkgs,
          system,
          packages,
          formatter,
          ...
        }:
        {
          packages = {
            inherit (packages) rust-toolchain;
            targets = pkgs.symlinkJoin {
              name = "targets-breakout";
              paths = map (item: {
                inherit (item) name;
                value = item.value.overrideAttrs (old: {
                  cargoProfile = "dev";
                  cargoBuildFlags = old.cargoBuildFlags ++ [
                    "--example"
                    "breakout"
                  ];
                });
              }) packages.targets.list;
            };
          };
        };

      config =
        {
          pkgs,
          system,
          ...
        }:
        {
          src = builtins.path {
            name = "src";
            path = ./.;

            # Ignore files that aren't needed in compilation of Bevy project.
            filter =
              path: type:
              !(builtins.elem (baseNameOf path) [
                "flake.lock"
                "flake.nix"
              ]);
          };

          rustToolchain =
            targets:
            let
              channel = "stable"; # For nightly, use "latest".
              fx = fenix.packages.${system};
              stds = map (target: fx.targets.${target}.${channel}.rust-std) targets;
            in
            fx.combine ([ fx.${channel}.toolchain ] ++ stds);
        };
    };
}
