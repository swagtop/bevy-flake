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
    let
      bf = bevy-flake.configure (
        { pkgs, ... }:
        {
          src = ./.;
          rustToolchain =
            targets:
            let
              fx = fenix.packages.${pkgs.stdenv.hostPlatform.system};
              channel = "stable"; # For nightly, use "latest".
              targets-rust-std = 
                map (target: fx.targets.${target}.${channel}.rust-std) targets;
            in
            fx.combine ([ fx.${channel}.toolchain ] ++ targets-rust-std);
        }
      );
    in
    {
      inherit (bf) packages formatter;

      devShells = bf.forSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            name = "bevy-flake-fenix";
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
