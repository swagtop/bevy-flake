<div align="center"> <img src="bevy-flake.svg" width="200"/> </div>

# bevy-flake

A simple and easy-to-edit Nix development flake, for painless [Bevy][bevy]
development and cross-compilation on Linux, MacOS and NixOS.

This flake provides the following:

1) A preconfigured wrapper for `cargo`, with all dependencies and environment
   variables needed for Bevy development on NixOS/Linux/MacOS preconfigured.

2) Cross-compilation to the `*-pc-windows-msvc` targets, with
   the ability to pin the version of the Windows SDK and CRT versions.

3) Cross-compilation to the `*-apple-darwin` targets, when provided with MacOS
   SDK.

4) Cross-compilation to the `*-unknown-linux-gnu` targets, with non-store linked
   dynamic loaders, allowing for non-Nix Linux systems to run the binaries.

```sh
nix develop github:swagtop/bevy-flake/dev
```

*Using [rust-overlay][overlay] for the rust toolchain,
and [cargo-zigbuild][zigbuild], [cargo-xwin][xwin] to assist in
cross-compilation.*

[bevy]: https://github.com/bevyengine/bevy
[overlay]: https://github.com/oxalica/rust-overlay/
[zigbuild]: https://github.com/rust-cross/cargo-zigbuild
[xwin]: https://github.com/rust-cross/cargo-xwin

> [!NOTE]
> By fetching the Windows SDK and CRT, and compiling to the `*-pc-windows-msvc`
> targets, you are accepting the [Microsoft Software License Terms.][license]

[license]: https://go.microsoft.com/fwlink/?LinkId=2086102

## Quick setup

First, navigate to your Bevy project root:

```sh
cd /path/to/bevy/project
```
#### Option 1: Use the template with your preferred rust toolchain provider.

```sh
nix flake init --template github:swagtop/bevy-flake/dev#rust-overlay
# ... or ...
nix flake init --template github:swagtop/bevy-flake/dev#fenix
```

#### Option 2: Wrap the toolchain used in your existing flake.

```sh
  
```

#### Option 3: Copy flake.

Fetch `flake.nix` and `flake.lock`, and add them to the git index:

```sh
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/dev/flake.nix
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/dev/flake.lock
git add flake.nix flake.lock
```

```sh
git add flake.nix
```

Remember to add the generated `flake.lock` file to your git index.

## How to use

Enter the development shell, and then run or compile your Bevy program:

```sh
nix develop

# Your Nix system
cargo build
cargo run

# Other systems
cargo build --target x86_64-unknown-linux-gnu
cargo build --target x86_64-pc-windows-msvc
cargo build --target aarch64-apple-darwin # <-- Read docs/macos.md!
cargo build --target wasm32-unknown-unknown
```

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
                             ╭──1───╴ wrapped-cargo-toolchain ╶───2──╮
                             │                                       │
                             │                                       │
                             │    ╔═══════════target/═══════════╗    │
                             ├─────► debug/                     ║    │
                             ╰─────► release/                   ║    │
                                  ║  x86_64-unknown-linux-gnu/ ◄─────┤
                                  ║  x86_64-pc-windows-msvc/ ◄───────┤
                                  ║  aarch64-apple-darwin/ ◄─────────╯
                                  ╚═════════════════════════════╝

                    (1) Local Nix System:             (2) Other Systems:

                    - RUSTFLAGS += localFlags         - RUSTFLAGS += crossFlags
                    - Runtime packages                - Each targets libraries
                      provided through rpath            provided by cargo-wrapper
                    - cargo compiles for              - cargo-zigbuild,
                      local system and runs             cargo-xwin cross-compile
```

- [Details](docs/details.md)
