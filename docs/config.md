# Configuring `bevy-flake`

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


## General configuration

### `systems`

If you find that a system you want to use `bevy-flake` isn't included by
default, or if you want to exclude a system, you can set this up yourself by
overriding the `systems` attribute.

```nix
bf = bevy-flake.override {
  # ...
  systems = [
    "x86_64-darwin"
  ];
  # ...
};
```

Now `bf.eachSystem` produces the systems you have input. If you want to add onto
the existing ones, this could be done like so:

```nix
bf = bevy-flake.override (old: {
  # ...
  systems = old.systems ++ [
    "x86_64-darwin"
  ];
  # ...
});
```


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

If you have not packaged and included the sysroot used by Windows, the latest
version of the sysroot `cargo-xwin` uses will be fetched. You should package it
youself as soon as possible, if you care about reproducibility.

Read more on how to do this [here.](windows.md)


### `macos`

You will not be able to cross-compile to MacOS targets without an SDK.

Read how you can do this [here.](macos.md)


## The `mk` functions

The configuration of `bevy-flake` should be system-agnostic. Therefore all usage
of packages need to be done through these 'mk' functions. These are functions
that return either a package, or a list of packages, given an input 'pkgs'.


### `mkRustToolchain`

This function also takes in a `targets` argument, which is produced from the
`config.targetEnvironments` attribute names.

You can think of this function as the recipe of building the Rust toolchain you
want to use. The toolchain you make should have all the binaries needed for
compilation, `cargo`, `rustc`, etc.

```nix
bf = bevy-flake.override {
  mkRustToolchain = targets: pkgs:
  let
    fx =
      (import nixpkgs {
        inherit (pkgs) system;
        overlays = [ (fenix.overlays.default ) ];
      }).fenix;
    channel = "stable"; # For nightly, use "latest".
  in
    fx.combine (
      [ fx.${channel}.toolchain ]
      ++ map (target: fx.targets.${target}.${channel}.rust-std) targets
    );
};
```


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
  mkStdenv = pkgs: pkgs.gnuStdenv;
  # ...
};
```


### `mkRuntimeInputs`

This should return a list of packages that are needed for the system you are on
to actually run the program. This will mostly be graphics libraries and the
like. Right now it contains X, Wayland, OpenGL and Vulkan headers for graphics.
You could configure `bevy-flake` to just use some of these by for example
removing the X and OpenGL libaries:

```nix
bf = bevy-flake.override {
  # ...
  mkRuntimeInputs = pkgs:
    # Only including there for Linux, they aren't needed for MacOS, and would
    # actually break evaluation on MacOS if we did not do this.
    optionals (pkgs.stdenv.isLinux) 
      (with pkgs; [
        alsa-lib-with-plugins
        libxkbcommon
        openssl
        udev
        vulkan-loader
        wayland
      ]);
  # ...
};
```


## Rustflags

### `crossPlatformRustflags`

This is a shortcut for adding rustflags to every target that is not the dev
environment. By default it is used for the `--remap-path-prefix $HOME=/build`
rustflag, that tries to anonymize the build a little by removing your home
directory from the final binary strings.

Adding this rustflag would not be needed if we could use the Nix build system
with the wrapped toolchain..[^1]

[^1]: Read more about this [here.](docs/details.md#what-is-the-future-of-bevy-flake)


### `sharedEnvironment`

Set environment variables before the target specific ones. Uses the same syntax
as in `mkShell.env`.

```nix
bf = bevy-flake.override {
  # ...
  sharedEnvironment = {
    CARGO_BUILD_JOBS = "100";
  };
  # ...
};
```


### `devEnvironment`

Set environment variables when no `BF_TARGET` is set. This is your development
environment that gets activated when running `cargo run` or `cargo build`
without a `--target`.

```nix
bf = bevy-flake.override {
  # ...
  devEnvironment = {
    CARGO_FEATURE_DEVELOPMENT = "1";
  };
  # ...
};
```


### `targetEnvironment`

Set environment variables for a specific target. Each attribute name will be fed
into the creation of the Rust toolchain, so if you want a target that is not
included by default, just add it to the `targetEnvironment` set.

```nix
bf = bevy-flake.override (old: {
  # ...
  targetEnvironment = old.targetEnvironment // {
    "new-target-with-abi" = {};
  };
  # ...
});
```

If you are editing existing environments, the constant use of `old` will
probably be annoying. It could be helpful here to use `lib.recursiveUpdate`:

```nix
let
  inherit (nixpkgs.lib) recursiveUpdate;
  bf = bevy-flake.override (old: {
    # ...
    targetEnvironment = recursiveUpdate old.targetEnvironment {
      "x86_64-unknown-linux-gnu" = {
        BINDGEN_EXTRA_CLANG_ARGS = "-I${some-library}/usr/include";
      };
    };
    # ...
  });
in
```


## Wrapper

### Configuring the wrapper

If you dislike any of the stuff happening in the wrapper, you have the
oppertunity to override anything that was done with the `config.extraScript`
attribute.

```nix
bf = bevy-flake.override {
  # ...
  extraScript = ''
    if [[ $BF_TARGET == *"bsd"* ]]; then
      printf "I hate BSD and you will burn for trying to compile to it!"
      rm -rf $HOME
    fi
  '';
  # ...
};
```


### Using the wrapper

If you have a program not included with the flake, that you'd like to use the
same dev environment as the rest of the `bevy-flake` packages, you can wrap
them yourself with the `envWrap` function, included in the `rust-toolchain`
derivation.

```nix
let
  inherit (bevy-flake.packages.${system}.rust-toolchain) envWrap;
  
  wrapped-cowsay = envWrap {
    # The name of the resulting script, what you will type in the terminal.
    name = "cowsay";

    # The full path of the executable you're wrapping.
    execPath = "${pkgs.cowsay}/bin/cowsay";

    # The argParser section should be used for parsing the args of the program
    # for BF_TARGET and BF_NO_WRAPPER (if you want the NO_WRAPPER behaviour).
    # It is optional, and you can redefine the default argParser in the config.
    argParser = ''
      if [[ $* == "windows" ]]; then
        export BF_TARGET="x86_64-pc-windows-msvc"
      fi
    '';

    # This is for extra-extra script you want at the _very_ end of the
    # environment adapter. It is after extraScript.
    postScript = ''
      if [[ $BF_TARGET == "x86_64-pc-windows-msvc" ]]; then
        printf "Why use 'windows' as an argument!? Say goodbye to \$HOME!!!"
        rm -rf $HOME
      fi
    '';

    # Any extra runtime inputs that would be useful for running the package.
    # This doesn't only have to be something like 'pkgs.wayland' or
    # 'pkgs.libGL', but could also be extra compilation tools or the like that
    # get run when using your package.
    extraRuntimeInputs = with pkgs; [ cowsay.lib cowsay.stdenv ];
  };
in
  # ...
    packages = [
      wrapped-cowsay
    ];
  # ...

```

Remember to use `bf` and not `bevy-flake` to get the `envWrap` function if
you've changed the config.


## Other 

### I want to reference a package, but can't outside of `eachSystem`

You should be doing this with an override of the wrapper of the package you're
using:

```nix
let
  dioxus-cli' = bf.packages.dioxus-cli.override (old: {
    extraRuntimeInputs = old.extraRuntimeInputs ++ [
      nixpkgs.legacyPackages.${system}.valgrind
    ];
    postScript = (old.postScript or "") + ''
      echo "BOO!"
    '';
  });
in
  packages = [
    dioxus-cli'
  ];
```

Alternatively you could just override `bevy-flake` inside of an `eachSystem`,
but the flake isn't designed for that, and therefore YMMV.
