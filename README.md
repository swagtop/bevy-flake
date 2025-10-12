<div align="center"> <img src="bevy-flake.svg" width="200"/> </div>

# bevy-flake

A flake for painless development and distribution of [Bevy][bevy] programs.

With bevy-flake you can easily compile and run the same project on NixOS and
MacOS, while being able to cross-compile portable binaries for non-Nix Linux,
Windows and MacOS targets.

[bevy]: https://github.com/bevyengine/bevy

> [!NOTE]
> By fetching the Windows SDK and CRT, and compiling to the `*-pc-windows-msvc`
> targets, you are accepting the [Microsoft Software License Terms.][license]

[license]: https://go.microsoft.com/fwlink/?LinkId=2086102

## Quick setup

First, navigate to your Bevy project root:

```sh
cd /path/to/bevy/project
```
#### Option 1: Use the template with your preferred rust toolchain provider

Read more on the benefits and drawbacks of each option [here.](docs/details.md)

```sh
# The default with no cross-compilation:
nix flake init --template github:swagtop/bevy-flake/dev#nixpkgs

# The one using oxalica's rust-overlay:
nix flake init --template github:swagtop/bevy-flake/dev#rust-overlay

# The one using nix-community's fenix:
nix flake init --template github:swagtop/bevy-flake/dev#fenix
```

If you get your toolchain from elsewhere, you should very easily be able to slot
it in. More on this [here.](docs/tweaks.md)

#### Option 2: Copy flake

Fetch `flake.nix` and `flake.lock`, and add them to the git index:

```sh
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/dev/flake.nix
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/dev/flake.lock
git add flake.nix flake.lock
```

You can read edits to the flake you'd like to do

## How to use

Add the `wrapped-rust-toolchain` package to your environment, either through
`nix develop`, `nix shell .#wrapped-rust-toolchain`, or your own preferred way.

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
```

You can compile to every target with a `targetSpecificEnvironment` entry. If
you'd like to add one that no longer exists, you can work on setting it up by
adding its environment to the attribute set.
More on this [here.](docs/tweaks.md)

- [Tweaks](docs/tweaks.md)
- [Pitfalls](docs/pitfalls.md)
- [Windows](docs/windows.md)
- [MacOS](docs/macos.md)

--------------------------------------------------------------------------------

> [!NOTE]
> This flake is still under development, and is not stabilized yet.
>
> I'm constantly trying new things to get the smoothest experience with Bevy on
> Nix systems as possible.

```
                                            $ cargo
                                                ▼
                            ╭────1───╴ wrapped-rust-toolchain ╶───2────╮
                            │                                          │
                            │                                          │
                            │     ╔════════════target/═══════════╗     │
                            ├──────► debug/                      ║     │
                            ╰──────► release/                    ║     │
                                  ║  x86_64-unknown-linux-gnu/ ◄───────┤
                                  ║  x86_64-pc-windows-msvc/ ◄─────────┤
                                  ║  aarch64-apple-darwin/ ◄───────────╯
                                  ╚══════════════════════════════╝

                    (1) Local Nix System:             (2) Other Systems:

                    - Runtime packages                - Each targets libraries
                      provided through rpath            provided by cargo-wrapper
                    - cargo compiles for              - cargo-zigbuild,
                      local system and runs             cargo-xwin cross-compile
```

- [Details](docs/details.md)
