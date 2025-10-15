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

### `mkRustToolchain`: Defining the Rust toolchain

_This function also takes in a `targets` argument, which is produced from the_
_`config.targetEnvironments` attribute names._



### `mkStdenv`: Defining the stdenv

### `mkRuntimeInputs`: 

### `mkHeaderInputs`: 

## The operating systems

### `linux`: Configuring the Linux builds.

### `windows`: Windows

### `macos`: MacOS

## Rustflags

### `localDevRustflags`: Configuring the local development builds.

### `crossPlatformRustflags`: Configuring the cross-compiled builds.

## Environments

## Wrapper

### Configuring the wrapper

### Using the wrapper
