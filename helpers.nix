{ pkgs, ... }:
let
  unpackTarballSkipOldFiles =
    src:
    pkgs.stdenvNoCC.mkDerivation {
      inherit src;
      name = "unpacked-sdk";
      phases = [ "installPhase" ];
      nativeBuildInputs = [
        pkgs.gnutar
        pkgs.coreutils
      ];
      installPhase = ''
        mkdir $out

        if 

        PASSED_LINKS=0

        tar -tvf "$src" | tac | while read -r file; do
          if [[ ${"file:0:1"} != "l" ]]; then
            PASSED_LINKS="1"
          elif [[ ${"file:0:1"} == "l" && $PASSED_LINKS == "1" ]]; then
            echo "Your tarball is packaged wrong."
            exit 1
          fi
        done

        tar -xf "$src" -C "$out" --skip-old-files
      '';
    };

in
{
  inherit unpackTarballSkipOldFiles;

  fetchWindowsSDK =
    { url, sha256 }: unpackTarballSkipOldFiles (pkgs.fetchurl { inherit url sha256; });
}
