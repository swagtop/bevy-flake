{
  coreutils,
  findutils,
  gnutar,
  pkgsCross,
  stdenv,
  writeShellApplication,
  xz,
  ...
}:
if stdenv.isDarwin then
  throw (
    "Packaging the Windows SDK is not supported on MacOS. "
    + "Because the MacOS filesystem is case-insensitive, the output of the "
    + "'windows.sdk' package is missing critical symlinks needed on Linux.\n"
    + "Run this on a Linux system instead. After it has been created on Linux, "
    + "it can be unpacked and used on MacOS just fine."
  )
else
  writeShellApplication {
    name = "package-windows-sdk";
    runtimeInputs = [
      coreutils
      findutils
      gnutar
      xz
    ];
    text = ''
      echo "Do you accept the Microsoft Software License Terms? [y/n]"
      echo "https://go.microsoft.com/fwlink/?LinkId=2086102"
      read -r

      if [[ $REPLY != "y" ]]; then
        exit 0
      fi

      TMP_DIR=$(mktemp -d)
      TMP_FILE=$(mktemp)

      echo "Extracting SDK for arm64 to $TMP_DIR"
      cp --no-preserve=mode -r ${pkgsCross.aarch64-windows.windows.sdk}/* "$TMP_DIR"
      echo "Extracting SDK for x86_64 to $TMP_DIR"
      cp --no-preserve=mode -r ${pkgsCross.x86_64-windows.windows.sdk}/* "$TMP_DIR"

      pushd "$TMP_DIR"

      echo "Packaging non-symlinks"
      find . -type f ! -type l  -print0 | tar --null --owner=0 --group=0 -cf "$TMP_FILE" -T -

      echo "Packaging symlinks"
      find . -type l -print0 | tar --owner=0 --group=0 --null -rf "$TMP_FILE" -T -

      popd

      echo "Compressing archive"
      xz -c "$TMP_FILE" > ./"WindowsMSVC${pkgsCross.x86_64-windows.windows.sdk.version}.sdk.tar.xz"
    '';
  }
