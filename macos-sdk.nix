{
  pkgs ? import <nixpkgs> { system = builtins.currentSystem; },
  ...
}:
let
  xar = pkgs.clangStdenv.mkDerivation {
    name = "xar";
    src = fetchGit {
      url = "https://github.com/tpoechtrager/xar";
      rev = "5fa4675419cfec60ac19a9c7f7c2d0e7c831a497";
    };
    nativeBuildInputs = with pkgs; [
      autoconf
      libxml2.dev
      openssl.dev
      libz.dev
    ];
    configurePhase = ''
      mkdir $out
      cd xar
      ./configure --prefix="$out"
    '';
  };
  pbzx = pkgs.clangStdenv.mkDerivation {
    name = "pbzx";
    src = fetchGit {
      url = "https://github.com/tpoechtrager/pbzx";
      rev = "2a4d7c3300c826d918def713a24d25c237c8ed53";
    };
    nativeBuildInputs = [
      xar
      pkgs.xz.dev
    ];
    buildPhase = ''
      mkdir -p $out/bin
      clang -llzma -lxar -I ${pkgs.xz.dev}/usr/include pbzx.c -o $out/bin/pbzx
    '';
  };
  osxcross = fetchGit {
    url = "https://github.com/tpoechtrager/osxcross";
    rev = "e6ab3fa7423f9235ce9ed6381d6d3af191b46b59";
  };
in
pkgs.writeShellScriptBin "package-macos-sdk" ''
  if [[ $1 == "" ]]; then
    echo "Use the path to <xcode.xip> as the first argument."
    exit 1
  fi

  XCODE=$(realpath "$1")
  
  TMP_DIR=$(mktemp -d)

  pushd $TMP_DIR
  
  ${xar}/bin/xar -xf "$XCODE" -C "$TMP_DIR"
  ${pbzx}/bin/pbzx -n Content | cpio -i

  popd

  XCODEDIR=$TMP_DIR ${osxcross}/tools/gen_sdk_package.sh
''
// {
  meta.mainProgram = "package-macos-sdk";
}
