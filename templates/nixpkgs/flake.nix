{
  description = "A flake using the nixpkgs rust toolchain wrapped with bevy-flake.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bevy-flake = {
      url = "github:swagtop/bevy-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, bevy-flake, ... }:
    bevy-flake.lib.mkFlake {
      perSystem =
        {
          pkgs,
          formatter,
          packages,
          ...
        }:
        {
          inherit packages formatter;

          devShells.default = pkgs.mkShell {
            name = "bevy-flake-nixpkgs";
            packages = [
              packages.rust-toolchain.develop
              packages.dioxus-cli.develop
              # packages.bevy-cli.develop
            ];
          };
        };
    };
}
