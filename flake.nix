{
  description = "A flake for painless development and distribution of Bevy projects.";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      inherit (builtins)
        isFunction
        concatStringsSep
        warn
        ;
      inherit (nixpkgs.lib)
        optionals
        genAttrs
        makeSearchPath
        ;

      config = {
        systems = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ];

        linux = {
          # Setting GLIBC version to the one Debian stable uses.
          glibcVersion = "2.41";
        };

        windows = {
          # Setting the Windows SDK to the latest one in nixpkgs, both arches.
          mkSdk =
            pkgs:
            pkgs.symlinkJoin {
              name = "windows-sdk-both-arches";
              paths = [
                pkgs.pkgsCross.aarch64-windows.windows.sdk
                pkgs.pkgsCross.x86_64-windows.windows.sdk
              ];
            };
        };

        macos = {
          # You will not be able to cross-compile to MacOS targets without an SDK.
          sdk = null;
        };

        crossPlatformRustflags = [ ];

        # Base environment for every target to build on.
        sharedEnvironment = {
          # Cross-compiling the 'blake3' crate to Linux breaks without this feature.
          CARGO_FEATURE_PURE = "1";
        };

        devEnvironment = { };

        # Environment variables set for individual targets.
        targetEnvironments =
          let
            linuxEnvFor = system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
              cc = pkgs.stdenv.cc;
              config = pkgs.stdenv.hostPlatform.config;
            in {
              PKG_CONFIG_PATH = makeSearchPath "lib/pkgconfig" (
                with pkgs;
                [
                  alsa-lib-with-plugins.dev
                  libxkbcommon.dev
                  openssl.dev
                  udev.dev
                  wayland.dev
                ]
              );
              RUSTFLAGS = concatStringsSep " " [
                "-C linker=ld.lld"
                "-C link-arg=-fuse-ld=lld"
                "-C link-arg=--sysroot=${cc.cc}"
                "-L ${pkgs.glibc}/lib"
                "-L ${nixpkgs.legacyPackages.${system}.libgcc}/lib"
                (if system == "aarch64-linux" then
                  "-C link-arg=-Wl,--dynamic-linker=/lib64/ld-linux-aarch64.so.1"
                else
                  "-C link-arg=-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2")
              ];
            };
            windowsEnvFor = arch: {
              RUSTFLAGS = concatStringsSep " " [
                "-C linker=lld-link"
                "-L $BF_WINDOWS_SDK_PATH/crt/lib/${arch}"
                "-L $BF_WINDOWS_SDK_PATH/sdk/lib/ucrt/${arch}"
                "-L $BF_WINDOWS_SDK_PATH/sdk/lib/um/${arch}"
              ];
            };
            macosEnv =
              let
                frameworks = "$BF_MACOS_SDK_PATH/System/Library/Frameworks";
              in
              {
                SDKROOT = "$BF_MACOS_SDK_PATH";
                COREAUDIO_SDK_PATH = "${frameworks}/System/Library/Frameworks/CoreAudio.framwork/Headers";
                BINDGEN_EXTRA_CLANG_ARGS = concatStringsSep " " [
                  "-F $BF_MACOS_SDK_PATH/System/Library/Frameworks"
                  "-I$BF_MACOS_SDK_PATH/usr/include"
                  "--sysroot=$BF_MACOS_SDK_PATH"
                ];
                RUSTFLAGS = concatStringsSep " " [
                  "-C linker=clang-unwrapped"
                  "-C link-arg=-fuse-ld=lld"
                  "-C link-arg=--target=$BF_TARGET"
                  "-C link-arg=${
                    concatStringsSep "," [
                      "-Wl"
                      "-platform_version"
                      "macos"
                      "$BF_MACOS_SDK_MINIMUM_VERSION"
                      "$BF_MACOS_SDK_DEFAULT_VERSION"
                    ]
                  }"
                ];
              };
          in
          {
            "x86_64-unknown-linux-gnu" = linuxEnvFor "x86_64-linux";
            "aarch64-unknown-linux-gnu" = linuxEnvFor "aarch64-linux";
            "x86_64-pc-windows-msvc" = windowsEnvFor "x64";
            "aarch64-pc-windows-msvc" = windowsEnvFor "arm64";
            "x86_64-apple-darwin" = macosEnv;
            "aarch64-apple-darwin" = macosEnv;
            "wasm32-unknown-unknown" = {
              RUSTFLAGS = ''--cfg getrandom_backend=\"wasm_js\"'';
            };
          };

        prePostScript = "";

        mkRustToolchain =
          targets: pkgs:
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

        mkRuntimeInputs =
          pkgs:
          optionals (pkgs.stdenv.isLinux) (
            with pkgs;
            [
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
            ]
          );

        mkStdenv = pkgs: pkgs.clangStdenv;

        src = null;
      };

      # Defining a simpler makeOverriable function.
      makeOverridable =
        f: args:
        let
          r = f args;
        in
        r
        // {
          override = a: makeOverridable f (args // (if isFunction a then a args else a));
        };
      mkBf = bf: (makeOverridable bf config);
    in
    mkBf (
      config:
      let
        eachSystem = genAttrs config.systems;
        packages = import ./packages.nix { inherit config nixpkgs; };
      in
      {
        inherit (config) systems;
        inherit config eachSystem packages;

        devShells = eachSystem (system: {
          default = nixpkgs.legacyPackages.${system}.mkShell {
            name = "bevy-flake";
            packages = [
              packages.${system}.rust-toolchain
              packages.${system}.dioxus-cli
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

        formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
      }
    );
}
