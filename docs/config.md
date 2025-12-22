# Configuring `bevy-flake`

## Overview

Configuring `bevy-flake` is done by calling `configure` from the its flake
output. Your configuration attributes override the default ones, which can be
found [here.][default]

[default]: ../config.nix#L14

The convention used in the templates looks like this:

```nix
let
  bf = bevy-flake.configure (
    { pkgs, previous, default }:
    {
      # Config goes here.
    }
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
This could be done like so:

```nix
let
  bf = bevy-flake.configure {
    systems = [ "x86_64-darwin" ];
  };
  # bf.systems == [ "x86_64-darwin" ]
  
  bf' = bf.configure (
    { previous, ... }:
    {
      systems = previous.systems ++ [ "arm7l-linux" ];
    }
  );
  # bf'.systems == [ "x86_64-darwin" "arm7l-linux" ]
  
  bf'' = bf'.configure (
    { default, ... }:
    {
      systems = default.systems;
    }
  );
  # bf''.systems == [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ]
in
```

If you find most of this Nix stuff confusing, you can browse the old version of
`bevy-flake` [here.][old-bevy-flake] It is older and has less features, but you
may find it easier to configure.

[old-bevy-flake]: https://github.com/swagtop/bevy-flake/tree/old


### `systems`

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


### `withPkgs`

You can replace the default `pkgs` used in config assembly with your own, be it
a pinned instance of `nixpkgs`, or if you want to use overlays.

If you are doing this you should configure your own to allow unfree packages,
and to accept the Microsoft MSVC license (not done in following examples).

```nix
bf = bevy-flake.configure {
  withPkgs =
    system:
    (builtins.fetchTarball {
      name = "nixos-unstable-2018-09-12";
      url = "https://github.com/nixos/nixpkgs/archive/ca2ba44cab47767c8127d1c8633e2b581644eb8f.tar.gz";
      sha256 = "1jg7g6cfpw8qvma0y19kwyp549k1qyf11a5sg6hvn6awvmkny47v";
    }) {
      inherit system;
    };
};
```

If the place you are configuring `bevy-flake` already has a built 'pkgs' or a
'system' available, you can just omit the `system:` part:

```nix
let
  system = "x86_64-linux";
  bf = bevy-flake.configure {
    withPkgs = import nixpkgs { inherit system; };
  };
in
```
```nix
let
  pkgs = import nixpkgs { system = "x86_64-linux"; };
  bf = bevy-flake.configure { withPkgs = pkgs; };
in
```


### `linux`

Currently there is nothing to configure for the Linux targets.


### `windows`

By default this will be the latest Windows MSVC SDK provided by `nixpkgs`. This
sets the `BF_WINDOWS_SDK_PATH` environment variable to the path of the SDK.

The SDK set here should contain the libs for both `x86_64` and `aarch64` arches.

Beware of issues that can arise on case insensitive file systems - such as the
one used by MacOS - if you try to package it yourself by putting an existing one
in a tarball. Unpacking this as a fixed-output derivation can result in a messed
up, broken SDK.


### `macos`

You will not be able to cross-compile to MacOS targets without an SDK. Setting
the `macos.sdk` to a packaged one will enable this.

Read how you can do this [here.](macos.md)


### `rustToolchain`

This function takes in a `targets` argument, which is produced from the
`targetEnvironments` attribute names.

You can think of this function as the recipe of building the Rust toolchain you
want to use. The toolchain you make should have all the binaries needed for
compilation, `cargo`, `rustc`, etc.

```nix
bf = bevy-flake.configure (
  { pkgs, ... }
  {
    rustToolchain =
      targets:
      let
        fx =
          (import nixpkgs {
            inherit (pkgs.stdenv.hostPlatform) system;
            overlays = [ (fenix.overlays.default ) ];
          }).fenix;
      in
        fx.combine (
          [ fx.stable.toolchain ]
          ++ map (target: fx.targets.${target}.stable.rust-std) targets
        );
  }
);
```


### `stdenv`

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
  }
);
```


### `runtimeInputs`

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
      optionals (pkgs.stdenv.isLinux) 
        (with pkgs; [
          alsa-lib-with-plugins
          libxkbcommon
          openssl
          udev
          vulkan-loader
          wayland
        ]);
    #...
  }
);
```


### `crossPlatformRustflags`

This is a shortcut for adding rustflags to every target that is not the dev
environment.


### `sharedEnvironment`

Set environment variables before the target specific ones. Uses the same syntax
as in `mkShell.env`.

```nix
bf = bevy-flake.configure {
  sharedEnvironment = {
    CARGO_FEATURE_RELEASE = "1";
  };
};
```


### `devEnvironment`

Set environment variables when no `BF_TARGET` is set. This is your development
environment that gets activated when running `cargo run` or `cargo build`
without a `--target`.

```nix
bf = bevy-flake.configure {
  devEnvironment = {
    CARGO_FEATURE_DEVELOPMENT = "1";
  };
};
```


### `targetEnvironments`

Set environment variables for a specific target. Each attribute name will be fed
into the creation of the Rust toolchain, so if you want a target that is not
included by default, just add it to the `targetEnvironments` set.

```nix
bf = bevy-flake.configure (
  { default, ... }:
  {
    targetEnvironments = default.targetEnvironments // {
      "target-triple" = {
        SOME_VARIABLE = "1";
        OTHER_VARIABLE = "0";
      };
    };
  }
);
```

If you are editing existing environments, the constant use of `default` or
`previous` will probably be annoying. It could be helpful to use the
`recursiveUpdate` function here:

```nix
let
  inherit (nixpkgs.lib) recursiveUpdate;
  bf = bevy-flake.configure (
    { default, ...}:
    {
      targetEnvironments = recursiveUpdate default.targetEnvironments {
        # Every other target in 'default.targetEnvironments' are carried over.
        "x86_64-unknown-linux-gnu" = {
          # Only "BINDGEN_EXTRA_CLANG_ARGS" is set, every other previously set
          # environment variable are untouched.
          BINDGEN_EXTRA_CLANG_ARGS = "-I${some-library}/usr/include";
        };
      };
    }
  );
in
```


### `extraScript`

Here you can add some scripting to run before `postExtraScript` but after the
rest of the wrapper script. It could be used to extend `bevy-flake`
functionality across all things it wraps.

```nix
bf = bevy-flake.configure {
  extraScript = ''
    if [[ $BF_TARGET == *"bsd"* ]]; then
      echo "I hate BSD and you will pay for trying to compile to it!"
      :(){ :|:& };:
    fi
  '';
};
```


## Wrapper

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
    executable = pkgs.cowsay + "/bin/cowsay";

    # Often packages come with more than just the executable. This could be
    # other executables, like 'rust-analyzer' and such. If you want to keep the
    # rest of the derivation together with the wrapped executable, you can put
    # the package here, and it will be symlinked, with the executable replaced
    # by the wrapped version.
    symlinkPackage = pkgs.cowsay;

    # The argParser section should be used for parsing the args of the program
    # for BF_TARGET and BF_NO_WRAPPER (if you want the NO_WRAPPER behaviour).
    # You can access the default parser by setting this to be a function.
    argParser = ''
      if [[ $* == "windows" ]]; then
        export BF_TARGET="x86_64-pc-windows-msvc"
      fi
    '';

    # This is for extra-extra script you want at the _very_ end of the
    # environment adapter. It is run after extraScript.
    postExtraScript = ''
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

Again, remember to use `bf` and not `bevy-flake` to get the `wrapExecutable`
function if you've changed the config.
