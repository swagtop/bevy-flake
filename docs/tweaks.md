# Tweaks

## Cargo / Rust

### Changing toolchain version

You can change the version of the version of the Rust toolchain by editing the
`rust-toolchain` section:

```nix
rust-toolchain.stable.latest.default         # Latest stable
rust-toolchain.stable."1.48.0".default       # Specific version of stable
rust-toolchain.beta."2021-01-01".default     # Specific date for beta
rust-toolchain.nightly."2020-12-31".default  # ... or nightly
```

> [!NOTE]
> Changing away from the nightly compiler will no longer let you use the
> nightly only flags (the ones begining with `-Z`)

More info can be found on the [rust-overlay repository.][rust-overlay]

[rust-overlay]: https://github.com/oxalica/rust-overlay

### Using the mold linker

Add mold to the `shellPackages` list:
```diff
shellPackages = with pkgs; [
+ mold
];
```

Then add this to the list of your local `RUSTFLAGS`:

```diff
localFlags = lib.concatStringsSep " " [
+ "-C link-arg=-fuse-ld=mold"
  "-C link-args=-Wl,-rpath,${ ... }"
];
```
*Do not add this to crossFlags, the wrapper will handle everything there.*

## Adding environment variables

### All targets

To add environment variables that affect all targets, simply add your exports
around the already existing ones, right before the switch case:

```diff
  # Environment variables for all targets.
  ## Stops 'blake3' from messing up.
  export CARGO_FEATURE_PURE=1
  ## Needed for MacOS target, and many non-bevy crates.
  export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"

+ export FOO="bar"

  case $BEVY_FLAKE_TARGET in
```

### Individual targets

If your environment variable is only relevant to a specific target (like your
own local NixOS system), then add it under its individual case:

```diff
  case $BEVY_FLAKE_TARGET in
    # No target means local system, sets localFlags if running or building.
    "")
+     export NIXOS_FOO="bar"
      if [ "$1" = 'zigbuild' ] || [ "$1 $2" = 'xwin build' ]; then
        echo "bevy-flake: Cannot use '"cargo $@"' without a '--target'"
        exit 1
      elif [ "$1" = 'run' ] || [ "$1" = 'build' ]; then
        RUSTFLAGS="${localFlags} $RUSTFLAGS"
      fi
    ;;
    *-apple-darwin)
+     export MACOS_FOO="bar"
      # Set up MacOS cross-compilation environment if SDK is in inputs.
      ${if (inputs ? mac-sdk) then macEnvironment else "# None found."}
    ;;
```

This way you avoid tainting the target build environments with unwanted changes.
Right now most of the targets don't need much individual attention, and are
therefore combined into one.

When you want to split any of the targets in the combined one off, it can easily
be done like so:

```diff
- x86_64-unknown-linux-gnu*|*-pc-windows-msvc|wasm32-unknown-unknown)
+ *-pc-windows-msvc|wasm32-unknown-unknown)
    RUSTFLAGS="${crossFlags} $RUSTFLAGS"
  ;;
+ x86_64-unknown-linux-gnu*)
+   RUSTFLAGS="${crossFlags} $RUSTFLAGS"
+   export X86_LINUX_FOO="bar"
+ ;;
```

## Wayland issues

If you're having Wayland issues, Wayland can simply be turned
off in the development shell, by commenting out the list concatnation of
`[ wayland ]`, in the `localFlags` rpath section:
```diff
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
+ # ++ lib.optionals (!(builtins.getEnv "NO_WAYLAND" == "1")) [ wayland ]
  )}"
];
```

Alternatively you can run `NO_WAYLAND=1 nix develop --impure` to remove it
temporarily without editing the flake.

## Removing any restrictions, or other behaviours of `cargo-wrapper`
Just use the `--no-wrapper` flag when running `cargo`, and you will essentially
be running cargo unwrapped.
