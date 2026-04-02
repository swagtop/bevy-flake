{
  writeShellApplication,
  stdenv,
  coreutils,
  pkgsCross,
  ...
}:
let
  hostSystem = stdenv.hostPlatform.system;
in
writeShellApplication {
  name = "package-windows-sdk";
  runtimeInputs = [
    coreutils
  ];
  text = ''
    echo "Do you accept the Microsoft Software License Terms? [y/n]"
    echo "https://go.microsoft.com/fwlink/?LinkId=2086102"
    read -r
    
    if [[ $REPLY != "y" ]]; then
      exit 0
    fi

    TMP_DIR=$(mktemp -d)

    echo "Extracting arm64 SDK to $TMP_DIR"
    cp --no-preserve=owner,mode -r ${pkgsCross.aarch64-windows.windows.sdk}/* "$TMP_DIR"
    echo "Extracting x86_64 SDK to $TMP_DIR"
    cp --no-preserve=owner,mode -r ${pkgsCross.x86_64-windows.windows.sdk}/* "$TMP_DIR"
  '';
}

