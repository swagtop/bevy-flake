{
  autoconf,
  bash,
  bzip2,
  clangStdenv,
  coreutils,
  cpio,
  fetchgit,
  findutils,
  gnugrep,
  gnused,
  gnutar,
  lib,
  libxml2,
  openssl,
  writeShellApplication,
  xz,
  zlib,
  ...
}:
let
  osxcross = fetchgit {
    url = "https://github.com/tpoechtrager/osxcross";
    rev = "e6ab3fa7423f9235ce9ed6381d6d3af191b46b59";
    sha256 = "sha256-MuOPFExFudprW/AZzcPoUXmSrGhEwQ20dFvwu6Q7OXc";
    passthru = {
      xar = clangStdenv.mkDerivation {
        name = "xar";
        src = fetchgit {
          url = "https://github.com/tpoechtrager/xar";
          rev = "5fa4675419cfec60ac19a9c7f7c2d0e7c831a497";
          sha256 = "sha256-lAntWSslNu2NSSGo/vnnSuqJCaomRlYIt+6PQbkttCQ=";
        };
        nativeBuildInputs = [
          autoconf
          libxml2.dev
          openssl.dev
          bzip2.dev
          zlib
        ];
        configurePhase = ''
          mkdir $out
          cd xar
          ./configure --prefix="$out"
        '';
        passthru.meta = {
          homepage = "https://github.com/tpoechtrager/xar";
          license = lib.licenses.unfree;
          mainProgram = "xar";
        };
      };
      pbzx = clangStdenv.mkDerivation {
        name = "pbzx";
        src = fetchgit {
          url = "https://github.com/tpoechtrager/pbzx";
          rev = "2a4d7c3300c826d918def713a24d25c237c8ed53";
          sha256 = "sha256-NKHmyM7pnrLLQIT25PNxdypv3GZC6Ili4TpTIFp8XbA=";
        };
        nativeBuildInputs = [
          xar
          xz.dev
        ];
        buildPhase = ''
          mkdir -p $out/bin
          clang -llzma -lxar pbzx.c -o $out/bin/pbzx
        '';
        passthru.meta = {
          homepage = "https://github.com/tpoechtrager/pbzx";
          license = lib.licenses.gpl3;
          mainProgram = "pbzx";
        };
      };
    };
  };
in
writeShellApplication {
  name = "package-macos-sdk";
  runtimeInputs = [
    osxcross.pbzx
    osxcross.xar
    bash
    cpio
    xz
    coreutils
    findutils
    gnugrep
    gnused
    gnutar
  ];
  text = ''
    XCODE=$(realpath "$1")

    TMP_DIR=$(mktemp -d)

    echo "Extracting $1 to $TMP_DIR"
    xar -xf "$XCODE" -C "$TMP_DIR"

    echo "Preparing for packaging"
    pbzx -n "$TMP_DIR/Content" | cpio -i --directory "$TMP_DIR"

    echo "Running packaging script from osxcross"
    XCODEDIR="$TMP_DIR" ${osxcross}/tools/gen_sdk_package.sh
  '';
  passthru = {
    inherit osxcross;
    meta = {
      description = ''
        MacOS SDK packaging script for Xcode versions >8.0, ported to Nix.
      '';
      homepage = "https://github.com/tpoechtrager/osxcross";
      license = lib.licenses.gpl2;
      mainProgram = "package-macos-sdk";
    };
  };
}
