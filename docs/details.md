# Details

## Who is this for?

This flake is for Nix users, who want to work with Bevy. Its goal is to be
as easy to use for beginners, as it is ergonomic to use for power users. The
flake provides a suite of packages useful for Bevy development, that all are
configured from a single place.

It is for the developer who wants to use a Nix environment to compile portable
binaries for the major desktop platforms on their own computer, instead of
having to resort to using Docker, GitHub actions, or the like.

The flake is easy to configure and extend, should you want support for a target,
or a package wrapped, that isn't included by default.

## What is the schema of `bevy-flake`?

```nix
{
  # The config used for creating this instance.
  config = <config>;

  # Systems supported and the eachSystem helper function for this instance.
  systems = [ <string> ];
  eachSystem = <function>;

  # The default devShell, includes the packages that don't need to be built.
  devShells."<system>".default = <derivation>;

  # All packages pre-wrapped by bevy-flake.
  packages."<system>" = {
    rust-toolchain = <derivation>; # Includes the wrapper function, 'wrapInEnv'.
    dioxus-cli = <derivation>;
    bevy-cli = <derivation>;
  };

  # The general templates for the different toolchains.
  templates."<name>" = <template>;

  # Read more on how to configure bevy-flake in docs/configuration.md
  override = <function>;
}
```

## What does `bevy-flake` do?

The flake provides a preconfigured environment for the Rust toolchain, and a
couple of packages that are helpful for Bevy development. The environment for
these packages can be overridden with ones own configuration.

## How does `bevy-flake` work?

The environment adapter makes use of the following environment variables:

```bash
# If this variable is set to "1", the environment wrapper runs the execPath
# without changing the environment.
BF_NO_WRAPPER 

# The environment wrapper sets up the MacOS environment variables based on the
# path given by this environment variable. You should not set this yourself, but
# set it through the `config.macos.sdk` attribute.
BF_MACOS_SDK_PATH

# By default `bevy-flake` uses `cargo-xwin` to fetch a specific version of the
# SDK and CRT. This is not # fully deterministic however, as no hashes are
# checked.
# You can package this fetched SDK and CRT however, and when that is done, this
# environment variable points to it.
# Read more on how to do this in `docs/windows.md`.
BF_WINDOWS_SDK_PATH

# The environment wrapper uses this variable to switch to the appropriate
# environment for compilation. It includes a default arg parser, that sets this
# variable to the arg after '--target'. You can swap this parser out for your
# own, should you use a tool that uses different keywords (see bevy-cli).
BF_TARGET
```

## How do I use `bevy-flake` to wrap one of my own packages?

Lets say you are wrapping `cowsay`:

```nix
let
  inherit (bevy-flake.packages.${system}.rust-toolchain) wrapInEnv;
  wrapped-cowsay = wrapInEnv {
    name = "cowsay";
    execPath = "${pkgs.cowsay}/bin/cowsay";
  };
in
  # ...
    packages = [
      wrapped-cowsay
    ];
  # ...
```

Read more on the inner workings of the wrapper, and how to use it [here.][wrap]

[wrap]: configuration.md#wrapper

## What is the future of `bevy-flake`?

The flake should include a builder for your Bevy project, such that the Nix
build system handles everything deterministically. I have made an attempt at
getting this set up, using `makeRustPlatform` with our wrapped Rust toolchain,
but could not get it to work.

If you manage to set one up, please open a pull request!

## What am I allowed to do with the `bevy-flake` repo?

You can do whatever you want with it.

If you find that you dislike the structure of it, or the opinonated design, you
can just fork it or copy it or just take the bits you find useful for yourself.
You don't have to provide any credit or include the license or anything like
that.

This flake is just the culmination of a lot of trial and error, with the goal of
making Bevy easier to use with Nix.
