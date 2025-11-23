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
    let
      bf = bevy-flake.configure { src = ./.; };
    in
    {
      inherit (bf) packages formatter;

      devShells = bf.eachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            name = "bevy-flake-nixpkgs";
            packages = [
              bf.packages.${system}.rust-toolchain
              bf.packages.${system}.dioxus-cli
              # bf.packages.${system}.bevy-cli
            ];
          };
        }
      );
    };
}
