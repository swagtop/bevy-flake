{
  description =
    "A Nix flake using nix-community's fenix wrapped with bevy-flake.";

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
        bf = bevy-flake.packages.override {
          rustToolchainFor = system:
            let
              fx = fenix.packages.${system};
              channel = "stable";
            in
              fx.combine
                [ fx.${channel}.toolchain ]
                  ++ map (target: fx.targets.${target}.${channel}.rust-std)
                    bevy-flake.targets;
            
        };
      in {
        default = pkgs.mkShell {
          name = "bevy-flake-fenix";
          packages = [
            bf.${system}.wrapped-rust-toolchain
            bf.${system}.wrapped-dioxus-cli
          ];
        };
      }  
    );
  };
}
