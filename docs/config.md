# Configuring `bevy-flake`

## Overview

Configuring `bevy-flake` is done by calling `configure` from the the flake
output. The default configuration can be found inside [here.][default-config]

[default-config]: ../config.nix#L4

The convention used in the templates looks like this:

```nix
let
  bf = bevy-flake.configure (
    { pkgs, previous, default }:
    {
      # Config goes here.
    };
  );
in
```

If you don't need to reference `pkgs`, `previous`, or `default`, you can call
`bevy-flake.configure` with just an attribute set:

```nix
let
  bf = bevy-flake.configure {
    # Config goes here.
  };
in
```

Afterwards, all usage of `bevy-flake` should be done through this new `bf`
variable. Anything using this will be using your customized configuration.

You can reconfigure `bevy-flake` as many times as you want.
This could be done like so (this example obviously wouldn't work, because there
is no config named 'i'):

```nix
# NEED BETTER EXAMPLES HERE!

let
  bf = bevy-flake.configure {
    i = "need more string";
  };
  # bf.i == "need more string"
  
  bf' = bf.configure (
    { previous, ... }:
    {
      i = "don't " + previous.i;
    }
  );
  # bf'.i == "don't need more string"
  
  bf'' = bf'.configure (
    { default, ... }:
    {
      i = default.i;
      back = "to basics";
    }
  );
  # bf''.i == "need more string"
  # bf''.back == "to basics"
in
```

If you find most of this Nix stuff confusing, you can browse the old version of
`bevy-flake` [here.][old-bevy-flake] You may find it easier to configure.

[old-bevy-flake]: https://github.com/swagtop/bevy-flake/tree/old


## General configuration

<details> <summary><code>systems</code></summary>

> **It is crucial that you never refer to the `pkgs` from `{ pkgs, ... }:` when**
> **configuring the `systems` attribue. We have a chicken-and-the-egg problem**
> **here, where the 'pkgs' passed into the rest of the config depends on the**
> **'systems' passed in from the config.**


If you find that a system you want to use `bevy-flake` isn't included by
default, or if you want to exclude a system, you can set this up yourself by
overriding the `systems` attribute.

```nix
bf = bevy-flake.configure {
  systems = [
    "x86_64-darwin"
  ];
};
```

Now `bf.eachSystem` produces the systems you have input. If you want to add onto
the existing ones, this could be done like so:

```nix
bf = bevy-flake.configure (
  { default, ... }:
  {
    systems = default.systems ++ [
      "x86_64-darwin"
    ];
  }
);
```

</details>


## The operating systems

These define the cross-compiled builds of the targets. For example, setting the
MacOS SDK will not change your local build created by `cargo build` on MacOS
systems.

If you want to test how these builds run with these settings on your Nix
machine, just compile them with `--target` and run those. On NixOS you will
probably find the `steam-run` package to be useful here.


<details> <summary><code>linux</code></summary>

Currently there is nothing to configure for the Linux targets.

</details>


<details> <summary><code>windows</code></summary>

By default this will be the latest Windows SDK provided by `nixpkgs`. You could
set a specific version here yourself, but beware of platform specific issues
that `xwin`-made SDK's could create, when packaging them manually with tarballs.

The SDK set here should contain the libs for both `x86_64` and `aarch64` arches.

</details>


<details> <summary><code>macos</code></summary>

You will not be able to cross-compile to MacOS targets without an SDK. Setting
the `macos.sdk` to a prepackaged one will do the trick.

Read how you can do this [here.](macos.md)

</details>


## The <something> functions

The configuration of `bevy-flake` should be system-agnostic. Therefore all usage
of packages need to be done through these <something> functions. These are functions
that return either a package, or a list of packages, given an input 'pkgs'.


<details> <summary><code>rustToolchainFor</code></summary>

This function takes in a `targets` argument, which is produced from the
`targetEnvironments` attribute names.

You can think of this function as the recipe of building the Rust toolchain you
want to use. The toolchain you make should have all the binaries needed for
compilation, `cargo`, `rustc`, etc.

```nix
bf = bevy-flake.override (
  { pkgs, ... }
  {
    rustToolchainFor = targets:
    let
      fx =
        (import nixpkgs {
          inherit (pkgs.stdenv.hostPlatform) system;
          overlays = [ (fenix.overlays.default ) ];
        }).fenix;
      channel = "stable"; # For nightly, use "latest".
    in
      fx.combine (
        [ fx.${channel}.toolchain ]
        ++ map (target: fx.targets.${target}.${channel}.rust-std) targets
      );
  };
);
```

</details>


<details> <summary><code>stdenv</code></summary>

The `bevy-flake` uses the stdenv created by this functions output for its C
compiler toolchain. By default this is set by `bevy-flake` to be clang.

This chosen because NixOS uses a GNU stdenv by default, while MacOS uses clang.
For more similar builds between host systems, we just set NixOS to use clang as
well.

Here is an example of setting some other stdenv:

```nix
bf = bevy-flake.configure (
  { pkgs, ... }:
  {
    stdenv = pkgs: pkgs.gnuStdenv;
  };
);
```

</details>


<details> <summary><code>runtimeInputs</code></summary>

This should return a list of packages that are needed for the system you are on
to actually run the program. This will mostly be graphics libraries and the
like. Right now it contains X, Wayland, OpenGL and Vulkan headers for graphics.
You could configure `bevy-flake` to just use some of these by for example
removing the X and OpenGL libaries:

```nix
bf = bevy-flake.configure (
  { pkgs, ... }:
  {
    runtimeInputs =
      # Only including these for Linux, they aren't needed for MacOS, and would
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
    };
    #...
  };
);
```

</details>


## The environments and additional scripting

For these attributes, should you want to refer to `pkgs`, you can optionally
make the value a function that takes in a single argument. The main `pkgs`
instance used by `bevy-flake` will then be passed into the function.

<details> <summary><code>crossPlatformRustflags</code></summary>

This is a shortcut for adding rustflags to every target that is not the dev
environment.

</details>


<details> <summary><code>sharedEnvironment</code></summary>

Set environment variables before the target specific ones. Uses the same syntax
as in `mkShell.env`.

```nix
bf = bevy-flake.configure {
  sharedEnvironment = {
    CARGO_BUILD_JOBS = "100";
  };
};
```

</details>


<details> <summary><code>devEnvironment</code></summary>

Set environment variables when no `BF_TARGET` is set. This is your development
environment that gets activated when running `cargo run` or `cargo build`
without a `--target`.

```nix
bf = bevy-flake.override {
  devEnvironment = {
    CARGO_FEATURE_DEVELOPMENT = "1";
  };
};
```

</details>


<details> <summary><code>targetEnvironments</code></summary>

Set environment variables for a specific target. Each attribute name will be fed
into the creation of the Rust toolchain, so if you want a target that is not
included by default, just add it to the `targetEnvironments` set.

```nix
bf = bevy-flake.configure (
  { default, ... }:
  {
    targetEnvironments = default.targetEnvironments // {
      "target-triple" = {};
    };
  }
);
```

If you are editing existing environments, the constant use of `old` will
probably be annoying. It could be helpful here to use `lib.recursiveUpdate`:

```nix
let
  inherit (nixpkgs.lib) recursiveUpdate;
  bf = bevy-flake.configure (
    { default, ...}:
    {
      targetEnvironment = recursiveUpdate default.targetEnvironments {
        "x86_64-unknown-linux-gnu" = {
          BINDGEN_EXTRA_CLANG_ARGS = "-I${some-library}/usr/include";
        };
      };
    }
  );
in
```

</details>

<details> <summary><code>prePostScript</code></summary>

Here you can add some scripting to run before `postScript` but after the rest
of the wrapper script. It could be used to extend `bevy-flake` functionality
across all things it wraps.

</details>


## Wrapper

### Configuring the wrapper

If you dislike any of the stuff happening in the wrapper, you have the
oppertunity to override anything that was done with the `prePostScript`
attribute.

```nix
bf = bevy-flake.configure {
  prePostScript = ''
    if [[ $BF_TARGET == *"bsd"* ]]; then
      echo "I hate BSD and you will pay for trying to compile to it!"
      :(){ :|:& };:
    fi
  '';
};
```


### Using the wrapper

If you have a program not included with the flake, that you'd like to use the
same dev environment as the rest of the `bevy-flake` packages, you can wrap
them yourself with the `wrapExecutable` function, included in the `rust-toolchain`
derivation.

```nix
let
  inherit (bevy-flake.packages.${system}.rust-toolchain) wrapExecutable;
  
  wrapped-cowsay = wrapExecutable {
    # The name of the resulting script, what you will type in the terminal.
    name = "cowsay";

    # The full path of the executable you're wrapping.
    executable = "${pkgs.cowsay}/bin/cowsay";

    # The argParser section should be used for parsing the args of the program
    # for BF_TARGET and BF_NO_WRAPPER (if you want the NO_WRAPPER behaviour).
    # You can access the default parser by setting this to be a function.
    argParser = ''
      if [[ $* == "windows" ]]; then
        export BF_TARGET="x86_64-pc-windows-msvc"
      fi
    '';

    # This is for extra-extra script you want at the _very_ end of the
    # environment adapter. It is after postScript.
    postScript = ''
      if [[ $BF_TARGET == "x86_64-pc-windows-msvc" ]]; then
        echo "Why use 'windows' as an argument!? Say goodbye to your RAM!!!"
        :(){ :|:& };:
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

Remember to use `bf` and not `bevy-flake` to get the `wrapExecutable` function
if you've changed the config.
