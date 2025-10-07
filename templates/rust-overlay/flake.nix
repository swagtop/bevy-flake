{
  description =
    "A Nix flake using Oxalica's rust-overlay wrapped with bevy-flake.";

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

  outputs = { nixpkgs, bevy-flake, rust-overlay, ... }: {
    devShells = bevy-flake.eachSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        bf = bevy-flake.packages.override {
          rustToolchainFor = system:
            let
              pkgs-with-overlay = (import nixpkgs {
                inherit system;
                overlays = [ (import rust-overlay ) ];
              });
              channel = "stable";
            in
              pkgs-with-overlay.rust-bin.${channel}.latest.default.override {
                inherit (bevy-flake) targets;
                extensions = [ "rust-src" "rust-analyzer" ];
              };
        };
      in {
        default = pkgs.mkShell {
          name = "bevy-flake-rust-overlay";
          packages = [
            bf.${system}.wrapped-rust-toolchain
            bf.${system}.wrapped-dioxus-cli
          ];
        };
      }
    );
  };
}
