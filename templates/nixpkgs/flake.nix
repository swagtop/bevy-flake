{
  description = "A flake using the nixpkgs rust toolchain wrapped with bevy-flake.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    bevy-flake = {
      url = "github:swagtop/bevy-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, bevy-flake, ... }:
    let
      bf = bevy-flake.override (default: {
        src = ./.;

        targetEnvironments =
          pkgs:
          let
            # Only able to build the target corresponding to system.
            # Get one of the other toolchains for cross-compilation.
            systemTarget = pkgs.stdenv.hostPlatform.config;
          in
          {
            ${systemTarget} = default.targetEnvironments.${systemTarget};
          };
      });
    in
    {
      inherit (bf) packages;

      devShells = bf.eachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            name = "bevy-flake-nixpkgs";
            packages = [
              bf.packages.${system}.rust-toolchain
              # bf.packages.${system}.dioxus-cli
              # bf.packages.${system}.bevy-cli
            ];
          };
        }
      );
    };
}
