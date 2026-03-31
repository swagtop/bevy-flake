{
  description = "A flake using Oxalica's rust-overlay wrapped with bevy-flake.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bevy-flake = {
      url = "github:swagtop/bevy-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      bevy-flake,
      rust-overlay,
      ...
    }:
    let
      bf = bevy-flake.configure (
        { pkgs, ... }:
        {
          src = ./.;
          withPkgs =
            system:
            import nixpkgs {
              inherit system;
              overlays = [ (import rust-overlay) ];
            };
          rustToolchain =
            targets:
            let
              channel = "stable"; # For nightly, use "nightly".
            in
            pkgs.rust-bin.${channel}.latest.default.override {
              inherit targets;
              extensions = [
                "rust-src"
                "rust-analyzer"
              ];
            };
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
            name = "bevy-flake-rust-overlay";
            packages = [
              bf.packages.${system}.rust-toolchain.develop
              bf.packages.${system}.dioxus-cli.develop
              # bf.packages.${system}.bevy-cli.develop
            ];
          };
        }
      );
    };
}
