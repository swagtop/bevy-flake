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
    bevy-flake.lib.mkFlake (
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

        config =
          { pkgs, ... }:
          {
            src = ./.;
            rustToolchain =
              targets:
              let
                fx = fenix.packages.${system};
                channel = "stable"; # For nightly, use "latest".
              in
              fx.combine (
                [ fx.${channel}.toolchain ] ++ map (target: fx.targets.${target}.${channel}.rust-std) targets
              );
          };
      }
    );
}
