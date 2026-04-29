{
  description = "A flake using nix-community's fenix wrapped with bevy-flake.";

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
          inherit packages formatter;

          devShells.default = pkgs.mkShell {
            name = "bevy-flake-fenix";
            packages = [
              packages.rust-toolchain.develop
              packages.dioxus-cli.develop
              # packages.bevy-cli.develop
            ];
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
