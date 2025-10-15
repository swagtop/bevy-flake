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

### `mkRustToolchain` - Defining the Rust toolchain

_(Single package)_

_This function also takes in a `targets` argument, which is produced from the_
_`config.targetEnvironments` attribute names._




### `mkStdenv` - Defining the stdenv

_(Single package)_

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

### `mkRuntimeInputs` - Defining the base runtime inputs

_(List of packages)_ 

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

### `linux` - Configuring the Linux builds.

### `windows` - Windows

### `macos` - MacOS

## Rustflags

### `devRustflags` - Configuring the local development builds.

### `crossPlatformRustflags` - Configuring the cross-compiled builds.

## Environments

### `sharedEnvironment`

### `devEnvironment`

### `targetEnvironment`

## Wrapper

### Configuring the wrapper

### Using the wrapper
