# Details

## Who is this for?

This flake is for Nix users, who want to work with Bevy. Its goal is to be as
ergonomic for power user as for beginners. The flake provides suite of packages
useful for Bevy development, that all are configured from a single place.

It is for the developer who wants to use a Nix environment to compile portable
binaries for the major desktop platforms on their own computer, instead of
having to resort to using Docker, GitHub actions, or the like.

## What is the schema of `bevy-flake`?

```nix
{
  config = <config>;

  systems = [ <strings> ];
  eachSystem = <function>;

  devShells."<system>".default = <derivation>;
  packages."<system>" = {
    rust-toolchain = <derivation>;
    dioxus-cli = <derivation>;
    bevy-cli = <derivation>;
  };

  templates."<name>" = <templates>;

  override = <function>;
}
```

## What does `bevy-flake` do?

The flake provides 

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

# The environment wrapper uses this 
BF_TARGET
```


## How do I use `bevy-flake` to wrap one of my own packages?


## Where is `bevy-flake` lacking?

The weakest part of the flake, that makes some builds not fully deterministic,
are the `*-pc-windows-msvc` targets. The solution implemented now is a hack to
at least make the version you are using declarative. No hashes are checked, and
the Windows SDK and CRT are not sourced from a derivation.

The reason why we can't just put the SDK and CRT pulled by `cargo-xwin` in a
tarball and then put it in the store, is that `cargo-xwin` writes to the
directory it is reading the SDK and CRT from on usage. It updates some scripts,
and creates symlinks to your toolchain inside of the directory.

For this to be solved, we either need to find a different way to include the SDK
and CRT, like using [windows-msvc-sysroot,][sysroot] or getting a PR through to
`cargo-xwin` that lets it use read-only directories.

[sysroot]: https://github.com/trcrsired/windows-msvc-sysroot
