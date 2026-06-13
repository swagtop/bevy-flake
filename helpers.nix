{
  pkgs,
  default,
  ...
}:

previous:

let
  inherit (builtins)
    foldl'
    baseNameOf
    isFunction
    ;
  inherit (pkgs.lib) recursiveUpdate;

  applyIfFunction = f: input: if isFunction f then f input else f;

  unpackTarballSkipOldFiles =
    src:
    pkgs.stdenvNoCC.mkDerivation {
      inherit src;
      name = "bevy-flake-${baseNameOf src}-unpacked";
      phases = [ "installPhase" ];
      nativeBuildInputs = with pkgs; [
        gnutar
        coreutils
      ];
      installPhase = ''
        mkdir $out

        PASSED_LINKS=0

        # Read all files in archive in reverse.
        tar -tvf "$src" | tac | while read -r file; do
          # Check if the first letter of the file info is 'l'.
          # If it is 'l', it is a symlink.
          if [[ ''${file:0:1} != "l" ]]; then
            PASSED_LINKS="1"
          elif [[ ''${file:0:1} == "l" && $PASSED_LINKS == "1" ]]; then
            echo "bevy-flake:"
            echo "Your tarball is packaged wrong, as not all symlinks are at the very end of the archive."
            echo "Package it properly, with 'nix run github:swagtop/bevy-flake#tools.package-windows-sdk'."
            exit 1
          fi
        done

        tar -xf "$src" -C "$out" --skip-old-files
      '';
    };

  editTargets =
    environments: list: input:
    foldl' (
      accumulator: target:
      let
        targetEnv = environments.${target};
      in
      accumulator
      // {
        ${target} = recursiveUpdate targetEnv (applyIfFunction input targetEnv);
      }
    ) environments list;
in
{
  inherit unpackTarballSkipOldFiles editTargets;

  fetchWindowsSDK =
    { url, sha256 }: unpackTarballSkipOldFiles (pkgs.fetchurl { inherit url sha256; });

  editDefaultTargets = editTargets default.targetEnvironments;
  editPreviousTargets = editTargets previous.targetEnvironments;
}
