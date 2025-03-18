# Tweaks

## Cargo / Rust

### Changing toolchain version
You can change the version of the version of the Rust toolchain by editing the
`rustToolchain` section:

```nix
rustToolchain.stable.latest.default         # Latest stable
rustToolchain.stable."1.48.0".default       # Specific version of stable
rustToolchain.beta."2021-01-01".default     # Specific date for beta
rustToolchain.nightly."2020-12-31".default  # ... or nightly
```

More info can be found on the [rust-overlay repository.][rust-overlay]

[rust-overlay]: https://github.com/oxalica/rust-overlay

### Using the mold linker

Add mold to the `shellPackages` list:
```nix
shellPackages = with pkgs; [
  cargo-zigbuild
  cargo-xwin
  rustToolchain
  mold # <-
];
```

Then add this to the list of your local `RUSTFLAGS`:

```sh
localFlags = lib.concatStringsSep " " [
  "-C link-arg=-fuse-ld=mold" # <-
  "-C link-args=-Wl,-rpath,${ ... }"
];
```
*Do not add this to crossFlags, the wrapper will handle everything there.*

## Wayland issues

If you're having Wayland issues, Wayland can simply be turned
off in the development shell, by commenting out the list concatnation of
`[ wayland ]`, in the `localFlags` rpath section:
```nix
localFlags = lib.concatStringsSep " " [
  "-C link-args=-Wl,-rpath,${lib.makeLibraryPath (with pkgs; [
    alsa-lib-with-plugins
    libGL
    libxkbcommon
    udev
    vulkan-loader
    xorg.libX11
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr
  ]
  # ++ lib.optionals (!(builtins.getEnv "NO_WAYLAND" == "1")) [ wayland ] # <-
  )}"
];
```

Alternatively you can run `NO_WAYLAND=1 nix develop --impure` to remove it
temporarily without editing the flake.

## Removing `cargo build --target` and `cargo run` restrictions
Just use the `--no-wrapper` flag when running `cargo`, and you will essentially
be running it without any restrictions placed by `bevy-flake`.
