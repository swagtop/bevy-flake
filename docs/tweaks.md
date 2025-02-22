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

Add mold to the `devShellPackages` list:
```nix
devShellPackages = with pkgs; [
  rustToolchain
  mold
];
```

Then add this to your `RUSTFLAGS`, such that they look like this in your
`shellHook`:

```sh
export RUSTFLAGS="-C link-args=-Wl,-rpath,${rpathLibrary}"
export RUSTFLAGS="-C link-arg=-fuse-ld=mold $RUSTFLAGS"
```
*Do not add this to the build shell, we are already using the Zig linker as an
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
]
++ xorgPackages
# ++ waylandPackages # <--- Comment out if you're having Wayland issues.
);
```

*Do not remove the `waylandPackages` from `compileTimePackages`.
Bevy builds with the `bevy/wayland` feature will fall back to x11 if the system
its running on doesn't support Wayland. Your build will have greater
compatibility like this.*

## Removing `cargo build --target` and `cargo run` restrictions
You should not be doing this. When running these in the wrong shell, the build
will inevitably fail, and cargo will completely restart the compilation of your
program from scratch.
Running these in the wrong shell by accident will waste you a lot of time.
