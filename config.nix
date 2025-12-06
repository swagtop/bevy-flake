{ nixpkgs }:

let
  inherit (builtins)
    concatStringsSep
    ;
  inherit (nixpkgs.lib)
    makeSearchPath
    optionals
    optionalString
    ;
in

# Default configuration begins here.
{
  pkgs,
  # previous,
  # default,
  ...
}:
{
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  # Let users set the 'pkgs' used to assemble the configs, should they want to
  # pin it to a specific nixpkgs rev, or perhaps to use some overlays.
  pkgsFor =
    system:
    import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        microsoftVisualStudioLicenseAccepted = true;
      };
    };

  # There are currently no things to configure for the Linux targets.
  linux = { };

  windows = {
    # Combining both x86_64 and aarch64 Windows SDK's into one.
    sdk = pkgs.symlinkJoin {
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

  crossPlatformRustflags = [
    # Getting rid of some '/nix/store' path prefixes.
    "--remap-path-prefix=/nix/store=/build"
  ];

  # Base environment for every target to build on.
  sharedEnvironment = {
    # Cross-compiling the 'blake3' crate to Linux and MacOS breaks without this feature.
    CARGO_FEATURE_PURE = "1";
  };

  # Environment variables for the dev build environment, as in no '--target'.
  devEnvironment = { };

  # Environment variables set for individual targets.
  targetEnvironments =
    let
      linuxEnvironmentFor =
        crossSystem:
        let
          hostSystem = pkgs.stdenv.hostPlatform.system;
          ifCross = str: optionalString (hostSystem != crossSystem) str;
          flags = {
            aarch64-linux = [
              "-C link-arg=-Wl,--dynamic-linker=/lib64/ld-linux-aarch64.so.1"
              "-C linker=${
                pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc + "/bin/${ifCross "aarch64-unknown-linux-gnu-"}cc"
              }"
            ];
            x86_64-linux = [
              "-C link-arg=-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2"
              "-C linker=${pkgs.pkgsCross.gnu64.stdenv.cc + "/bin/${ifCross "x86_64-unknown-linux-gnu-"}cc"}"
            ];
          };
        in
        {
          PKG_CONFIG_PATH = makeSearchPath "lib/pkgconfig" (
            # Getting these libraries through 'nixpkgs.legacyPackages.<system>'
            # instead of 'pkgs.pkgsCross.<system>' lets us fetch them directly
            # without needing to build a ton of stuff through the nixpkgs cross-
            # compilation system.
            with nixpkgs.legacyPackages.${crossSystem};
            [
              alsa-lib-with-plugins.dev
              libxkbcommon.dev
              openssl.dev
              udev.dev
              wayland.dev
            ]
          );
          RUSTFLAGS = concatStringsSep " " flags.${crossSystem};
        };

      windowsEnvironmentFor = arch: {
        RUSTFLAGS = concatStringsSep " " [
          "-C linker=${pkgs.lld}/bin/lld-link"
          "-L $BF_WINDOWS_SDK_PATH/crt/lib/${arch}"
          "-L $BF_WINDOWS_SDK_PATH/sdk/lib/ucrt/${arch}"
          "-L $BF_WINDOWS_SDK_PATH/sdk/lib/um/${arch}"
        ];
      };

      macosEnvironment =
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
            "-C linker=${pkgs.clangStdenv.cc.cc}/bin/clang"
            "-C link-arg=-fuse-ld=${pkgs.lld}/bin/ld64.lld"
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
      "x86_64-unknown-linux-gnu" = linuxEnvironmentFor "x86_64-linux";
      "aarch64-unknown-linux-gnu" = linuxEnvironmentFor "aarch64-linux";
      "x86_64-pc-windows-msvc" = windowsEnvironmentFor "x64";
      "aarch64-pc-windows-msvc" = windowsEnvironmentFor "arm64";
      "x86_64-apple-darwin" = macosEnvironment;
      "aarch64-apple-darwin" = macosEnvironment;
      "wasm32-unknown-unknown" = {
        RUSTFLAGS = ''--cfg getrandom_backend=\"wasm_js\"'';
        # Adding latest version of 'wasm-bindgen' to PATH.
        PATH =
          (pkgs.wasm-bindgen-cli_0_2_105 or pkgs.buildWasmBindgenCli (
            let
              pname = "wasm-bindgen-cli";
              version = "0.2.105";
              src = pkgs.fetchCrate {
                inherit pname version;
                hash = "sha256-zLPFFgnqAWq5R2KkaTGAYqVQswfBEYm9x3OPjx8DJRY=";
              };
            in
            {
              inherit src;
              cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
                inherit src pname version;
                hash = "sha256-a2X9bzwnMWNt0fTf30qAiJ4noal/ET1jEtf5fBFj5OU=";
              };
            }
          ))
          + "/bin:$PATH";
      };
    };

  prePostScript = "";

  rustToolchainFor =
    targets:
    (pkgs.symlinkJoin {
      name = "nixpkgs-rust-toolchain";
      pname = "cargo";
      paths = with pkgs; [
        cargo
        clippy
        rust-analyzer
        rustc
        rustfmt
      ];
    })
    // {
      # Used in 'packages.nix' to check if user is using the default toolchain.
      bfDefaultToolchain = true;
    };

  runtimeInputs = optionals (pkgs.stdenv.isLinux) (
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

  stdenv = pkgs.clangStdenv;

  src = null;
}
