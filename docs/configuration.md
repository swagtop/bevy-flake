# Configuration

## Overview

Configuring `bevy-flake` is done through overriding the flake input. The default
configuration can be found inside of the `config` attribute set in the outermost
let-in section of the `flake.nix` file.

The convention used in the templates looks like this:

```nix
let
  bf = bevy-flake.override {
    # Config goes here.
  };
in
```

Afterwards, all usage of `bevy-flake` should be done through this new `bf`
variable. Anything using this will be using your customized configuration.

## The `mk` functions

The configuration of `bevy-flake` should be system-agnostic. Therefore all usage
of packages need to be done through these 'mk' functions. These are functions
that return either a package, or a list of packages, given an input 'pkgs'.

### `mkRustToolchain`

_This function also takes in a `targets` argument, which is produced from the_
_`config.targetEnvironments` attribute names._




### `mkStdenv`

The `bevy-flake` uses the stdenv created by this functions output for its C
compiler toolchain. By default this is set by `bevy-flake` to be clang.

This chosen because NixOS uses a GNU stdenv by default, while MacOS uses clang.
For more similar builds between host systems, we just set NixOS to use clang as
well.

Here is an example of setting some other stdenv:

```nix
bf = bevy-flake.override {
  # ...
  mkStdenv = pkgs: pkgs.stdenvAdapters.useMoldLinker pkgs.clangStdenv;
  # ...
};
```

### `mkRuntimeInputs`

## The operating systems

These define the cross-compiled builds of the targets. For example, setting the
`linux.glibcVersion` will not change the glibc version used when running
`cargo build`, but only when running
`cargo build --target x86_64-unknown-linux-gnu`.

Likewise, setting the MacOS SDK will not change your local build created by
`cargo build` on MacOS systems.

If you want to test how these builds run with these settings on your Nix
machine, just compile them with '--target' and run those. On NixOS you will
probably find `steam-run` to be useful here.

### `linux`

Setting the `glibcVersion` variable only affects the builds made with the
wrapped `cargo` included with the `rust-toolchain` package. It works by changing
the target you are using to include the glibc version you are targeting, for
`cargo-zigbuild` to consume. Read more about this [here.][glibc]

[glibc]: https://github.com/rust-cross/cargo-zigbuild?tab=readme-ov-file#specify-glibc-version

### `windows`

### `macos`

## Rustflags

### `crossPlatformRustflags`

This is a shortcut for adding rustflags to every target that is not the dev
environment. By default it is used for the `--remap-path-prefix $HOME=/build`
rustflag, that tries to anonymize the build a little by removing your home
directory from the final binary strings.

Adding this rustflag would not be needed if we could use the Nix build system
with the wrapped toolchain, but that will not be possible until the Windows
builds problem is solved.[^1]

[^1]: Read more about this [here.](docs/details.md#where-is-bevy-flake-lacking)

### `sharedEnvironment`

### `devEnvironment`

### `targetEnvironment`

## Wrapper

### Configuring the wrapper

### Using the wrapper
