{ nixpkgs }:

{
  pkgs,
  # previous,
  # default,
  ...
}:

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

{
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  # There are currently no things to configure for the Linux targets.
  linux = { };

  windows = {
    # Setting the Windows SDK to the latest one in nixpkgs, both arches.
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

  crossPlatformRustflags = [ ];

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
      linuxEnvFor =
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

      windowsEnvFor = arch: {
        RUSTFLAGS = concatStringsSep " " [
          "-C linker=${pkgs.lld}/bin/lld-link"
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
            "-C linker=${pkgs.clangStdenv.cc.cc}/bin/clang"
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

  rustToolchainFor =
    targets:
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
