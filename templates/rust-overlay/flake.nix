{
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
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay ) ];
        };
        bf = bevy-flake.packages.${system};
        wrapped-rust-toolchain = bf.wrapped-rust-toolchain.override {
          rust-toolchain = pkgs.rust-bin.stable.latest.default.override {
            inherit (bevy-flake) targets;
            extensions = [ "rust-src" "rust-analyzer" ];
          };
        };
      in {
        default = pkgs.mkShell {
          name = "bevy-flake-rust-overlay";
          packages = [
            wrapped-rust-toolchain
          ];
        };
      }
    );
  };
}
