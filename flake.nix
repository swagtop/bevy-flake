{
  description =
    "A flake for development and distribution of Bevy projects.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };
  
  outputs = { nixpkgs, ... }:
  let
    inherit (builtins)
      removeAttrs attrNames concatStringsSep warn;
    inherit (nixpkgs.lib)
      optionals genAttrs makeSearchPath makeOverridable;

    config = {
      inherit mkStdenv mkHeaderInputs mkRuntimeInputs mkRustToolchain;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      linux = {
        glibcVersion = "2.41";
      };

      windows = {
        # Set to false if you don't want bevy-flake to manage cargo-xwin.
        pin = true;
        manifestVersion = "17";
        sdkVersion = "10.0.22621";
        crtVersion = "14.44.17.14";
      };

      macos = {
        # You will not be able to cross-compile to MacOS targets without an SDK.
        sdk = "";
      };

      localDevRustflags = [ ];

      crossPlatformRustflags = [
        "--remap-path-prefix \${HOME}=/build"
      ];

      # Base environment for every target to build on.
      sharedEnvironment = {
        # Stops blake3 from messing builds up every once in a while.
        CARGO_FEATURE_PURE = "1";
      };

      # Environment variables set for individual targets.
      # The target names, and bodies should use Bash syntax.
      targetEnvironment =
      let
        macos =
        let
          frameworks = "$BF_MACOS_SDK_PATH/System/Library/Frameworks";
        in {
          SDKROOT = "$BF_MACOS_SDK_PATH";
          COREAUDIO_SDK_PATH = "${frameworks}/CoreAudio.framework/Headers";
          BINDGEN_EXTRA_CLANG_ARGS = concatStringsSep " " [
            "--sysroot=$BF_MACOS_SDK_PATH"
            "-F ${frameworks}"
            "-I$BF_MACOS_SDK_PATH/usr/include"
          ];
          RUSTFLAGS = concatStringsSep " " [
            "-L $BF_MACOS_SDK_PATH/usr/lib"
            "-L framework=${frameworks}"
          ];
        };
      in {
        "x86_64-apple-darwin" = macos;
        "aarch64-apple-darwin" = macos;
        "x86_64-unknown-linux-gnu" = {
          PKG_CONFIG_PATH = "${
            makeSearchPath "lib/pkgconfig"
              (mkHeaderInputs nixpkgs.legacyPackages."x86_64-linux")
          }";
        };
        "aarch64-unknown-linux-gnu" = {
          PKG_CONFIG_PATH = "${
            makeSearchPath "lib/pkgconfig"
              (mkHeaderInputs nixpkgs.legacyPackages."aarch64-linux")
          }";
        };
        "wasm32-unknown-unknown" = {
          RUSTFLAGS = concatStringsSep " " [
            ''--cfg getrandom_backend=\"wasm_js\"''
          ];
        };
        # No environment setup needed for Windows targets.
        "x86_64-pc-windows-msvc" = { };
        "aarch64-pc-windows-msvc" = { };
      };

      extraScript = "";

      defaultArgParser = ''
        # Check if what the adapter is being run with.
        TARGET_ARG_NO=0
        for arg in "$@"; do
          TARGET_ARG_NO=$((TARGET_ARG_NO + 1))
          case $arg in
            "--target")
              # Save next arg as target.
              eval "BF_TARGET=\$$((TARGET_ARG_NO + 1))"
              export BF_TARGET="$BF_TARGET"
            ;;
            "--no-wrapper")
              # Remove '--no-wrapper' from args, then run unwrapped exec.
              set -- "''${@:1:$((TARGET_ARG_NO - 1))}" \
                     "''${@:$((TARGET_ARG_NO + 1))}"
              export BF_NO_WRAPPER="1"
            ;;
          esac
        done
      '';
    };

    mkRustToolchain = targets: pkgs:
      pkgs.symlinkJoin {
        name = "nixpkgs-rust-toolchain";
        pname = "cargo";
        paths = with pkgs; [
          cargo
          clippy
          rust-analyzer
          rustc
          rustfmt
        ];
      };

    mkRuntimeInputs = pkgs:
      optionals (pkgs.stdenv.isLinux)
        (with pkgs; [
          alsa-lib-with-plugins
          libxkbcommon
          udev
          vulkan-loader
          libGL
          wayland
          xorg.libX11
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
        ]);

    mkHeaderInputs = pkgs:
      optionals (pkgs.stdenv.isLinux)
        (with pkgs; [
          alsa-lib-with-plugins.dev
          libxkbcommon.dev
          openssl.dev
          udev.dev
          wayland.dev
        ]);

    mkStdenv = pkgs: pkgs.clangStdenv;
  in
    makeOverridable (config:
    let
      eachSystem = genAttrs config.systems;
      packages = import ./packages.nix (config // { inherit nixpkgs; });
    in {
      inherit (config) systems;
      inherit config eachSystem packages;

      devShells = eachSystem (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          name = "bevy-flake";
          packages = [
            packages.${system}.rust-toolchain
            # packages.${system}.dioxus-cli
            # packages.${system}.bevy-cli
          ];
        };
      });

      targets = attrNames config.targetEnvironment;

      templates = {
        nixpkgs = warn "This template does not support any cross-compilation." {
          path = ./templates/nixpkgs;
          description = "Get the rust toolchain from nixpkgs.";
        };
        rust-overlay = {
          path = ./templates/rust-overlay;
          description = "Get the rust toolchain through oxalica's rust-overlay.";
        };
        fenix = {
          path = ./templates/fenix;
          description = "Get the rust toolchain through nix-community's fenix.";
        };
      };
  }) config;
}
