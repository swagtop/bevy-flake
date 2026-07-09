{
  system ? builtins.currentSystem,
  config ? { default, ... }: {
    systems = default.systems ++ [ builtins.currentSystem ];
  },
}:
let
  flake-compat = fetchTarball {
    url = "https://github.com/NixOS/flake-compat/archive/5edf11c44bc78a0d334f6334cdaf7d60d732daab.tar.gz";
    sha256 = "sha256:0yqfa6rx8md81bcn4szfp0hjq2f3h9i8zjzhqqyfqdkrj5559nmw";
  };

  flakeOutput = import flake-compat { src = ./.; };

  configuredFlake = flakeOutput.defaultNix.lib.configure config;
in
configuredFlake.packages.${system}
