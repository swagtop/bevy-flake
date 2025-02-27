# Tweaks

## Cargo / Rust

### Adding targets
Instead of using `rustup target add`, add your targets to the `targets` section
of the `rustToolchain` section:
```nix
rustToolchain = pkgs.rust-bin.stable.latest.nightly.override {
  extensions = [ "rust-src" "rust-analyzer" ];
    targets = [
      "aarch64-apple-darwin"
      "x86_64-apple-darwin"
      "x86_64-unknown-linux-gnu"
      "x86_64-pc-windows-gnu"
      "x86_64-pc-windows-gnullvm"
      "x86_64-pc-windows-msvc"
      "wasm32-unknown-unknown"
          
      # Add extra targets here!
    ];
  };
```
The ones already there have been tested, and are known to work.

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

Add mold to the `developShellPackages` list:
```nix
shellPackages = with pkgs; [
  cargo-zigbuild
  cargo-xwin
  clang
  rustToolchain
  mold # <-
];
```

Then add this to the list of your local `RUSTFLAGS`:

```sh
localFlags = lib.concatStringsSep " " [
  "-C link-args=-Wl,-rpath,${lib.makeLibraryPath runtimePackages}"
  "-C link-arg=-fuse-ld=mold" # <-
];
```
*Do not add this to crossFlags, we are already using the Zig linker as an
alternative linker there.*

## Wayland issues

If you're having Wayland issues, Wayland can simply be turned
off in the development shell, by commenting out the list concatnation of
`waylandPackages`, in the `runtimePackages` section:
```nix
runtimePackages = (with pkgs; [
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
# ++ [ wayland ] # <--- Comment out if you're having Wayland issues. 
);
```

## Removing `cargo build --target` and `cargo run` restrictions
Just use the `--no-wrapper` flag when running `cargo`, and you will essentially
be running it without any restrictions placed by `bevy-flake`.
