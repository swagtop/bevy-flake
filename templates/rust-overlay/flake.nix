{
  description =
    "A flake using Oxalica's rust-overlay wrapped with bevy-flake.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    bevy-flake = {
      url = "github:swagtop/bevy-flake/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, bevy-flake, rust-overlay, ... }:
  let
    bf = bevy-flake.override {
      rustToolchainFor = system:
      let
        pkgs-with-overlay = (import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay ) ];
        });
        channel = "stable"; # For nightly, use "nightly".
      in
        pkgs-with-overlay.rust-bin.${channel}.latest.default.override {
          inherit (bevy-flake) targets;
          extensions = [ "rust-src" "rust-analyzer" ];
        };
    };
  in {
    inherit (bf) packages;

    devShells = bf.eachSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
    in {
      default = pkgs.mkShell {
        name = "bevy-flake-rust-overlay";
        packages = [
          bf.packages.${system}.rust-toolchain
          # bf.packages.${system}.dioxus-cli
        ];
      };
    });
  };
}
