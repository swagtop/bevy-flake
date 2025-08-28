{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    bevy-flake = {
      url = "github:swagtop/bevy-flake/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, bevy-flake, fenix, ... }: {
    devShells = bevy-flake.eachSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        fx = fenix.packages.${system};
        bf = bevy-flake.packages.${system};
        wrapped-rust-toolchain = bf.wrapped-rust-toolchain.override {
          rust-toolchain = fx.combine ([
            fx.stable.toolchain
          ]
          ++ map (target: fx.targets.${target}.stable.rust-std)
            bevy-flake.targets
          );
        };
      in {
        default = pkgs.mkShell {
          name = "bevy-flake-fenix";
          packages = [
            wrapped-rust-toolchain
          ];
        };
      }  
    );
  };
}
