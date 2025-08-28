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
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (fenix.overlays.default) ];
        };
        bf = bevy-flake.packages.${system};
        wrapped-rust-toolchain =
          let
            channel = "stable";
          in bf.wrapped-rust-toolchain.override {
            rust-toolchain = pkgs.fenix.combine ([
              pkgs.fenix.${channel}.toolchain
            ]
            ++ map (target: pkgs.fenix.targets.${target}.${channel}.rust-std)
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
