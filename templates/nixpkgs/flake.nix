{
  description =
    "A flake using the nixpkgs rust toolchain wrapped with bevy-flake.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    bevy-flake = {
      url = "github:swagtop/bevy-flake/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, bevy-flake, ... }: {
    devShells = bevy-flake.eachSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
    in {
      inherit (bevy-flake) packages;

      default = pkgs.mkShell {
        name = "bevy-flake-nixpkgs";
        packages = [
          bevy-flake.packages.${system}.rust-toolchain
          # bevy-flake.packages.${system}.dioxus-cli
        ];
      };
    });
  };
}
