> [!WARNING]
> This flake will remain stable until January 1st 2025, where will be an update
> that may have breaking changes, based on feedback on this initial release.
> After that, you can again count on the flake being stable.

<div align="center"> <img src="bevy-flake.svg" width="200"/> </div>

# bevy-flake

A flake for painless development and distribution of [Bevy][bevy] programs.

With `bevy-flake` you can easily compile and run your project on NixOS and
MacOS, as well as reproducibly[^1] cross-compile portable binaries for non-Nix
Linux, Windows and MacOS targets.

[bevy]: https://github.com/bevyengine/bevy
[^1]: This requires extra setup for Windows targets. Read more
      [here.](docs/windows.md#packaging-the-sysroot)

> [!NOTE]
> By compiling to the `*-pc-windows-msvc` targets, you are likely considered to
> be accepting the [Microsoft Software License Terms.][license]

[license]: https://go.microsoft.com/fwlink/?LinkId=2086102


## Quick setup

First, navigate to your Bevy project root:

```sh
cd /path/to/bevy/project
```

Then, use the template with your preferred rust toolchain provider (switching
to a different one later is super easy):

```sh
# The default with no cross-compilation, but faster evaluation:
nix flake init --template github:swagtop/bevy-flake/dev#nixpkgs

# The one using oxalica's rust-overlay:
nix flake init --template github:swagtop/bevy-flake/dev#rust-overlay

# The one using nix-community's fenix:
nix flake init --template github:swagtop/bevy-flake/dev#fenix
```

If you get your toolchain from elsewhere, you should very easily be able to slot
it in. More on this [here.][config-toolchain]

[config-toolchain]: docs/config.md#mkrusttoolchain


## How to use

Add the `rust-toolchain` package to your environment, either through
`nix develop`, `nix shell .#rust-toolchain`, or your own preferred way.

Then, you can just use `cargo` like so:

```sh
# For your own Nix system:
cargo build
cargo run

# For other targets, just use '--target':
cargo build --target x86_64-unknown-linux-gnu
cargo build --target x86_64-pc-windows-msvc
cargo build --target aarch64-apple-darwin # <-- Read docs/macos.md!
cargo build --target wasm32-unknown-unknown
# (...and so on. )
```

You can compile to every target with a `config.targetEnvironment` entry.
If the target you want isn't in the config, you can add it, and set up the
environment needed for it yourself. More on that [here.](docs/config.md)

- [Configuration](docs/config.md)
- [Pitfalls](docs/pitfalls.md)
- [Windows](docs/windows.md)
- [MacOS](docs/macos.md)
- [Details](docs/details.md)
