{
  description =
    "A flake for painless development and distribution of Bevy projects.";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
  
  outputs = { nixpkgs, ... }:
  let
    inherit (builtins)
      concatStringsSep warn;
    inherit (nixpkgs.lib)
      optionals genAttrs makeSearchPath makeOverridable;

    config = {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      linux = {
        glibcVersion = "2.41";
      };

      windows = {
        # The latest sysroot will be fetched if you don't have it set.
        sysroot = null;
      };

      macos = {
        # You will not be able to cross-compile to MacOS targets without an SDK.
        sdk = null;
      };

      crossPlatformRustflags = [];

      # Base environment for every target to build on.
      sharedEnvironment = {
        # Fixes cargo-zigbuild builds that break on blake3 without this feature.
        CARGO_FEATURE_PURE = "1";
      };

      devEnvironment = {};

      # Environment variables set for individual targets.
      targetEnvironments =
      let
        linuxHeaders = system: makeSearchPath "lib/pkgconfig"
          (with nixpkgs.legacyPackages.${system}; [
            alsa-lib-with-plugins.dev
            libxkbcommon.dev
            openssl.dev
            udev.dev
            wayland.dev
          ]);
        windowsEnv = {
          XWIN_CROSS_COMPILER = "clang";
          BINDGEN_EXTRA_CLANG_ARGS = concatStringsSep " " [
            "--sysroot=$BF_WINDOWS_SDK_PATH"
            "-I$BF_WINDOWS_SDK_PATH/crt/include"
          ];
          RUSTFLAGS = concatStringsSep " " [
            "-C linker=lld-link"
            "-C link-arg=/LIBPATH:C:$BF_WINDOWS_SDK_PATH/Lib/ucrt/x64"
            "-C link-arg=/LIBPATH:C:$BF_WINDOWS_SDK_PATH/Lib/um/x64"
            "-L $BF_WINDOWS_SDK_PATH/sdk/lib/um/x64"
            "-L $BF_WINDOWS_SDK_PATH/crt/lib/x64"
          ];
        };
        macosEnv =
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
            "$RUSTFLAGS"
          ];
        };
      in {
        "x86_64-unknown-linux-gnu" = {
          PKG_CONFIG_PATH = linuxHeaders "x86_64-linux";
        };
        "aarch64-unknown-linux-gnu" = {
          PKG_CONFIG_PATH = linuxHeaders "aarch64-linux";
        };
        "wasm32-unknown-unknown" = {
          RUSTFLAGS = concatStringsSep " " [
            ''--cfg getrandom_backend=\"wasm_js\"''
            "$RUSTFLAGS"
          ];
        };
        "x86_64-apple-darwin" = macosEnv;
        "aarch64-apple-darwin" = macosEnv;
        "x86_64-pc-windows-msvc" = windowsEnv;
        "aarch64-pc-windows-msvc" = windowsEnv;
      };

      extraScript = "";

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
            libGL
            libxkbcommon
            openssl
            udev
            vulkan-loader
            wayland
            xorg.libX11
            xorg.libXcursor
            xorg.libXi
            xorg.libXrandr
          ]);

      mkStdenv = pkgs: pkgs.clangStdenv;

      buildSource = null;
    };

    mkBf = bf: removeAttrs (makeOverridable bf config) [ "overrideDerivation" ];
  in
    mkBf (config:
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

      templates = {
        nixpkgs = warn "This template does not support any cross-compilation." {
          path = ./templates/nixpkgs;
          description = "Get the Rust toolchain from nixpkgs.";
        };
        rust-overlay = {
          path = ./templates/rust-overlay;
          description = "Get the Rust toolchain through oxalica's rust-overlay.";
        };
        fenix = {
          path = ./templates/fenix;
          description = "Get the Rust toolchain through nix-community's fenix.";
        };
      };
  });
}
