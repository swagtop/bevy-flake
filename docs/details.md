# Details

## Who is `bevy-flake` for?

This flake is for Nix users that want to work with Bevy. It is for the developer
who wants to use a Nix environment to compile portable binaries for the major
desktop platforms on their own computer, instead of having to rely on  Docker,
GitHub actions, or the like.

Its goal is to be both easy to use for beginners, and powerfully ergonomic for
experienced users. The flake provides a suite of packages useful for Bevy
development, all are configured from a single place.

The flake is easy to configure and extend, should you want support for a target,
or a package wrapped, that isn't included by default.


## What is the schema of `bevy-flake`?

```nix
{
  # Systems supported and the eachSystem helper function for this instance.
  systems = [ <system> ];
  eachSystem = <function>;

  # The default devShell, includes the packages that don't need to be built.
  devShells."<system>".default = <derivation>;

  packages."<system>" = {
    rust-toolchain = <derivation>; # The wrapped Rust toolchain.
    rust-toolchain.unwrapped = <derivation>; # The unwrapped Rust toolchain.
    rust-toolchain.wrapExecutable = <function>; # Use to wrap your own packages.
    
    # Pre-wrapped packages.
    dioxus-cli = <derivation>;
    bevy-cli = <derivation>;

    # If you've set the 'src' config attribute to your source code:
    targets = <derivation>; # All targets, symlinked to the same derivation.
    targets."<target>" = <derivation>; # The individual targets.
  };

  # The general templates for the different toolchains.
  templates."<name>" = <template>;

  # The function used for configuring bevy-flake. Read docs/config.md for info.
  configure = <function>;
}
```


## What does `bevy-flake` do?

Normally, cross-compiling with Nix is done within the context of the Nix
builder, through the nixpkgs cross-compilation system.

What this flake does instead is put all of the configuration for the
cross-compilation into a single wrapper script, wrapping `cargo`, `dx`, and
`bevy-cli`, such that cross- compilation can happen anywhere the wrapper is
run, outside or inside of the Nix builder.

This wrapper is built based on a single place of configuration. Configuring
`bevy-flake` to your liking is very easy and flexible, more on this
[here.](config.md)

When run, the wrapper changes the environment for the target specified,
individually and separately for every target.

To do this, it goes through a couple of different steps:

 1. Arg parsing

    _The input args are by default parsed for the '--target' flag, to figure out_
    _which target is being compiled for._


 2. Base environment is set up

    _Basic environment variables are exported, eg._
    _`PKG_CONFIG_CONFIG_ALLOW_CROSS=1`._


 3. `sharedEnvironment` is set up

    _The user configured environment for all targets is set up._


 4. The `targetSpecificEnviornments.<target>` environment is set up.

    _The environment for the target found by the arg parser is set up. The_
    _target triple is stored in the `BF_TARGET` environment variable. If it is_
    _empty, the wrapper script assumes that you are developing, and sets up the_
    _development environhment._


 5. The `extraScript` section runs

    _If you want to add some functionality to the wrapper for all packages that_
    _is wrapped with it, you can add it here in through the configuration. By_
    _default this is configured to do nothing._

  
 6. The `postExtraScript` section runs

    _If you want to add some functionality to a singular package, you can_
    _add it here when wrapping a package with `wrapExecutable`._

  
 7. The executable wrapped is run.


## How does `bevy-flake` work?

For the best way to get an understanding of how `bevy-flake` works, you should
first read through the [wrapper.nix](../wrapper.nix) file. This is where your
configuration is turned into the shell script that wraps the programs shipped
with the flake.

After you've read through the source code, you can see the final outcome of this
configuration by running:
```sh
$EDITOR $(which cargo)
```

The environment adapter makes use of the following environment variables:

```bash
# If this variable is set to "1", the environment wrapper runs the executable
# without changing the environment.
BF_NO_WRAPPER 

# The environment wrapper sets up the MacOS environment variables based on the
# path given by this environment variable. You should not set this yourself, but
# set it through the `macos.sdk` config attribute.
BF_MACOS_SDK_PATH
BF_MACOS_SDK_MINIMUM_VERSION
BF_MACOS_SDK_DEFAULT_VERSION

# This is the path to the Windows SDK used for the Windows targets. By default
# it is set to the one from nixpkgs, but you can set it to any other version
# through the `windows.sdk` config attribute.
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
  inherit (bevy-flake.packages.${system}.rust-toolchain) wrapExecutable;
  wrapped-cowsay = wrapExecutable {
    name = "cowsay";
    executable = "${pkgs.cowsay}/bin/cowsay";
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

The following things should be added to `bevy-flake`.

1. The flake should support the mobile targets, ie. Android and iOS. I've tried
   myself to set it up for a bit, but couldn't get iOS working and therefore put
   it on the backburner. I might look into it more later.

If you manage to configure any of this stuff yourself, please open a pull
request!


## What am I allowed to do with the `bevy-flake` repo?

Feel free to do anything you would like with it, it is licensed with MIT-0.
