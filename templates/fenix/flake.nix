{
  description =
    "A flake using nix-community's fenix wrapped with bevy-flake.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    bevy-flake = {
      url = "github:swagtop/bevy-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, bevy-flake, fenix, ... }: 
  let
    bf = bevy-flake.override {
      mkRustToolchain = targets: pkgs:
      let
        fx =
          (import nixpkgs {
            inherit (pkgs) system;
            overlays = [ (fenix.overlays.default ) ];
          }).fenix;
        channel = "stable"; # For nightly, use "latest".
      in
        fx.combine (
          [ fx.${channel}.toolchain ]
          ++ map (target: fx.targets.${target}.${channel}.rust-std) targets
        );
    };
  in {
    inherit (bf) packages;

    devShells = bf.eachSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
    in {
      default = pkgs.mkShell {
        name = "bevy-flake-fenix";
        packages = [
          bf.packages.${system}.rust-toolchain
          # bf.packages.${system}.dioxus-cli
          # bf.packages.${system}.bevy-cli
        ];
      };
    });
  };
}
