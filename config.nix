inputs:

# Default configuration begins here.
{
  pkgs,
  system,
  # previous,
  # default,
  # helpers,
  ...
}:
let
  inherit (pkgs.lib)
    concatStringsSep
    getExe
    makeSearchPath
    optionals
    ;
in
{
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  # Specify the 'pkgs' used to assemble the configs. Everything using the 'pkgs'
  # from '{ pkgs, ... }:', and all other uses of 'pkgs' in bevy-flake itself,
  # will be using this.
  withPkgs = import inputs.nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
      microsoftVisualStudioLicenseAccepted = true;
    };
  };

  linux = {
    targets = [
      "x86_64-unknown-linux-gnu"
      "aarch64-unknown-linux-gnu"
    ];
  };

  windows = {
    # Combining both x86_64 and aarch64 Windows SDK's into one.
    sdk = pkgs.symlinkJoin {
      name = "windows-sdk-both-arches";
      paths = [
        pkgs.pkgsCross.aarch64-windows.windows.sdk
        pkgs.pkgsCross.x86_64-windows.windows.sdk
      ];
    };
    staticBuild = false;
    targets = [
      "x86_64-pc-windows-msvc"
      "aarch64-pc-windows-msvc"
    ];
  };

  macos = {
    # You will not be able to cross-compile to MacOS targets without an SDK.
    sdk = null;
    targets = [
      "x86_64-apple-darwin"
      "aarch64-apple-darwin"
    ];
  };

  web = {
    wasm-bindgen = pkgs.wasm-bindgen-cli;
    targets = [ "wasm32-unknown-unknown" ];
  };

  crossPlatformRustflags = [
    # Getting rid of some '/nix/store' path prefixes.
    "--remap-path-prefix=/nix/store=/build"
    # Getting rid of some mentions of HOME, that appear if built without Nix.
    "--remap-path-prefix=$HOME=/build"
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
      cc = pkgs.llvmPackages.clang-unwrapped;
      bintools = pkgs.llvmPackages.bintools-unwrapped;

      unwrapped-clang = "${cc}/bin/clang";

      linuxEnvironmentFor =
        targetSystem:
        let
          targetPkgs = import pkgs.path { system = targetSystem; };
        in
        {
          CC = unwrapped-clang;

          # Need these for the 'cc-rs' crate.
          CFLAGS = "-I${targetPkgs.llvmPackages.libc.libc.dev}/include";
          LDFLAGS = "-L${targetPkgs.llvmPackages.libc-full}/lib";

          PKG_CONFIG_PATH = makeSearchPath "lib/pkgconfig" (
            # Getting these libraries through re-importing nixpkgs instead of
            # doing 'pkgs.pkgsCross.<system>', lets us fetch them directly
            # without needing to build a ton of stuff through the nixpkgs cross-
            # compilation system.
            with targetPkgs;
            [
              alsa-lib-with-plugins.dev
              libxkbcommon.dev
              openssl.dev
              udev.dev
              wayland.dev
            ]
          );
          RUSTFLAGS = concatStringsSep " " (
            let
              target-linker =
                {
                  aarch64-linux = pkgs.pkgsCross.aarch64-multiplatform.clangStdenv.cc;
                  x86_64-linux = pkgs.pkgsCross.gnu64.clangStdenv.cc;
                }
                .${targetSystem};
            in
            [
              "-C linker=${getExe target-linker}"
              "-C link-arg=-fuse-ld=${bintools}/bin/ld.lld"
              "-C link-arg=-Wl,--dynamic-linker=${
                {
                  aarch64-linux = "/lib64/ld-linux-aarch64.so.1";
                  x86_64-linux = "/lib64/ld-linux-x86-64.so.2";
                }
                .${targetSystem}
              }"
            ]
          );
        };

      windowsEnvironmentFor =
        arch:
        let
          windows-linker = "${bintools}/bin/lld-link";
        in
        {
          CC = "${cc}/bin/clang-cl";
          AR = "${bintools}/bin/llvm-lib";
          CFLAGS = concatStringsSep " " [
            "-fuse-ld=${windows-linker}"
            "-I$BF_WINDOWS_SDK_PATH/sdk/include/ucrt"
            "-I$BF_WINDOWS_SDK_PATH/crt/include"
          ];
          RUSTFLAGS = concatStringsSep " " [
            "-C linker=${windows-linker}"
            "-L $BF_WINDOWS_SDK_PATH/crt/lib/${arch}"
            "-L $BF_WINDOWS_SDK_PATH/sdk/lib/ucrt/${arch}"
            "-L $BF_WINDOWS_SDK_PATH/sdk/lib/um/${arch}"
            "$BF_WINDOWS_STATIC_FLAG"
          ];
        };

      macosEnvironment =
        let
          frameworks = "$BF_MACOS_SDK_PATH/System/Library/Frameworks";
        in
        {
          CC = unwrapped-clang;
          SDKROOT = "$BF_MACOS_SDK_PATH";
          COREAUDIO_SDK_PATH = "${frameworks}/CoreAudio.framwork/Headers";
          BINDGEN_EXTRA_CLANG_ARGS = concatStringsSep " " [
            "-F ${frameworks}"
            "-I$BF_MACOS_SDK_PATH/usr/include"
            "--sysroot=$BF_MACOS_SDK_PATH"
          ];
          RUSTFLAGS = concatStringsSep " " [
            "-C linker=${unwrapped-clang}"
            "-C link-arg=-fuse-ld=${bintools}/bin/ld64.lld"
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
        WASM_BINDGEN = "$BF_WASM_BINDGEN/bin/wasm-bindgen";
      };
    };

  extraScript = "";

  rustToolchain =
    let
      defaultToolchain =
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
    in
    # Ignore the functor part here, if looking for how to import your own
    # toolchain. We are using a functor here to check in 'packages.nix' if the
    # user is using the default toolchain.
    # When setting your own toolchain, just write something akin to the
    # definition of 'defaultToolchain' above.
    {
      __functor = _: defaultToolchain;
      bfDefaultToolchain = true;
    };

  runtimeInputs = optionals pkgs.stdenv.isLinux (
    with pkgs;
    [
      alsa-lib-with-plugins
      libGL
      libxkbcommon
      openssl
      udev
      vulkan-loader
      wayland
      # The 'xorg' namespace will be removed. Adding the packages like this will
      # mute the warning for now.
      (pkgs.libX11 or xorg.libX11)
      (pkgs.libXcursor or xorg.libXcursor)
      (pkgs.libXi or xorg.libXi)
      (pkgs.libXrandr or xorg.libXrandr)
    ]
  );

  stdenv = pkgs.clangStdenv;

  src = null;
}
