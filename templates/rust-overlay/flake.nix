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
    bevy-flake.lib.mkFlake (
      {
        pkgs,
        formatter,
        packages,
        system,
        ...
      }:
      {
        inherit packages formatter;

        devShells.default = pkgs.mkShell {
          name = "bevy-flake-rust-overlay";
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
                channel = "stable"; # For nightly, use "nightly".
              in
              pkgs.rust-bin.${channel}.latest.default.override {
                inherit targets;
                extensions = [
                  "rust-src"
                  "rust-analyzer"
                ];
              };
            withPkgs =
              system:
              import nixpkgs {
                inherit system;
                overlays = [ (import rust-overlay) ];
              };
          };
      }
    );
}
