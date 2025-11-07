# Details

## Who is `bevy-flake` for?

This flake is for Nix users, who want to work with Bevy. It is for the developer
who wants to use a Nix environment to compile portable binaries for the major
desktop platforms on their own computer, instead of having to resort to using
Docker, GitHub actions, or the like.

Its goal is to be as easy to use for beginners, as it is ergonomic to use for
power users. The flake provides a suite of packages useful for Bevy development,
that all are configured from a single place.

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
    rust-toolchain = <derivation>; # The input toolchain, with 'cargo' wrapped.
    rust-toolchain.wrapper = <derivation>; # Just the 'cargo' wrapper.
    rust-toolchain.unwrapped = <derivation>; # The input toolchain.
    rust-toolchain.envWrap = <function>; # Use this to wrap your own packages.
    
    dioxus-cli = <derivation>;
    bevy-cli = <derivation>;

    # If you've set up the Nix builder with `buildSource = ./.`
    targets = <derivation>; # All targets, symlinked to the same directory.
    targets."<target>" = <derivation>; # The individual targets.
  };

  # The general templates for the different toolchains.
  templates."<name>" = <template>;

  # The function used for configuring bevy-flake. Read docs/config.md for info.
  override = <function>;
}
```


## What does `bevy-flake` do?

The flake provides a preconfigured environment for the Rust toolchain, and a
couple of packages that are helpful for Bevy development. The environment for
these packages can be overridden with ones own configuration.


## How does `bevy-flake` work?

TODO: Have a writeup on how the flake does things here.

The environment adapter makes use of the following environment variables:

```bash
# If this variable is set to "1", the environment wrapper runs the execPath
# without changing the environment.
BF_NO_WRAPPER 

# The environment wrapper sets up the MacOS environment variables based on the
# path given by this environment variable. You should not set this yourself, but
# set it through the `macos.sdk` attribute.
BF_MACOS_SDK_PATH

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
  inherit (bevy-flake.packages.${system}.rust-toolchain) envWrap;
  wrapped-cowsay = envWrap {
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

[wrap]: config.md#wrapper


## What is the future of `bevy-flake`?

There are a couple of things that I would like to be added to `bevy-flake`.

1. The flake should support the mobile targets, ie. Android and iOS. I've tried
   myself to set it up for a bit, but couldn't get iOS working and therefore put
   it on the backburner. I might look into it more later.

2. The flake should include some utilities for doing stuff that Bevy itself
   cannot do properly yet, such as setting up the Window icon, or easily making
   a MacOS `.app` directory.

If you manage to configure any of this stuff yourself, please open a pull
request!


## What am I allowed to do with the `bevy-flake` repo?

You can do whatever you want with it.

If you find that you dislike the structure of it, or the opinonated design, you
can just fork it or copy it or just take the bits you find useful for yourself.
You don't have to provide any credit or include the license or anything like
that.

This flake is just the culmination of a lot of trial and error, with the goal of
making working with Bevy on Nix more comfortable.
