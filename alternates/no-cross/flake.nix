{
  description = "A NixOS development flake for Bevy development.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, rust-overlay, nixpkgs, ... }:
  let
    system = "x86_64-linux";
    overlays = [ (import rust-overlay) ];
    pkgs = import nixpkgs { inherit system overlays; };
    lib = pkgs.lib;

    rust-toolchain = pkgs.rust-bin.nightly.latest.default.override {
      extensions = [ "rust-src" "rust-analyzer" ];
      targets = [
        "x86_64-unknown-linux-gnu"
      ];
    };

    shellPackages = with pkgs; [
      # mold
    ];

    localFlags = lib.concatStringsSep " " [
      "-C link-args=-Wl,-rpath,${lib.makeLibraryPath (with pkgs; [
        alsa-lib-with-plugins
        libGL
        libxkbcommon
        udev
        vulkan-loader
        xorg.libX11
        xorg.libXcursor
        xorg.libXi
        xorg.libXrandr
      ]
      ++ lib.optionals (!(builtins.getEnv "NO_WAYLAND" == "1")) [ wayland ]
      )}"
      # "-C link-arg=-fuse-ld=mold"
    ];

    compileTimePackages = with pkgs; [
      # The wrapper, compilers, and pkg-config.
      cargo-wrapper
      rust-toolchain
      pkg-config
      # Headers for x86_64-unknown-linux-gnu.
      alsa-lib.dev
      libxkbcommon.dev
      udev.dev
      wayland.dev
    ];

    # Wrapping 'cargo', to adapt the environment to context of compilation.
    cargo-wrapper = pkgs.writeShellScriptBin "cargo" ''
      # Check if cargo is being run with '--target', or '--no-wrapper'.
      if [[ "$*@" =~ '--no-wrapper' ]]; then
        # Remove '--no-wrapper' from args, run cargo without changed env.
        set -- $(printf '%s\n' "$@" | grep -vx -- '--no-wrapper')
        exec ${rust-toolchain}/bin/cargo "$@"
      fi

      # Stops 'blake3' from messing up.
      export CARGO_FEATURE_PURE=1 

      # Run cargo with relevant RUSTFLAGS.
      RUSTFLAGS="${localFlags}" exec ${rust-toolchain}/bin/cargo "$@"
    '';
  in {
    devShells.${system}.default = pkgs.mkShell {
      name = "bevy-flake";

      packages = shellPackages;
      nativeBuildInputs = compileTimePackages;
    };
  };
}
