{
  pkgs,
  previous,
  default,
  ...
}:
let
  inherit (builtins) foldl';
  inherit (pkgs.lib) recursiveUpdate;

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

  editTargets =
    origin: list: f:
    foldl' (
      accumulator: target:
      let
        targetEnv = origin.targetEnvironments.${target};
      in
      accumulator
      // {
        ${target} = recursiveUpdate targetEnv (f targetEnv);
      }
    ) origin.targetEnvironments list;
in
{
  inherit unpackTarballSkipOldFiles editTargets;

  fetchWindowsSDK =
    { url, sha256 }: unpackTarballSkipOldFiles (pkgs.fetchurl { inherit url sha256; });

  editDefaultTargets = editTargets default;
  editPreviousTargets = editTargets previous;
}
