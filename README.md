<div align="center"> <img src="bevy-flake.svg" alt="bevy-flake" width="200"/> </div>

# bevy-flake

A simple and easy-to-edit Nix development flake,
for painless Bevy development and cross-compilation on NixOS.
This flake is meant to help new NixOS users hit the ground running,
and get started quickly, with as little hassle as possible.

*Using [rust-overlay][overlay] for the rust toolchain,
and [cargo-zigbuild][zigbuild] for cross-compilation.*

[overlay]: https://github.com/oxalica/rust-overlay/
[zigbuild]: https://github.com/rust-cross/cargo-zigbuild

## Quick setup
Fetch `flake.nix` into your project root directory, and add it to the git index:
```sh
cd /path/to/project
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/main/flake.nix
git add flake.nix
```

Compile and run Bevy project on your NixOS machine:
```sh
nix develop
cargo run
```
... or:
```sh
nix develop
cargo build
/path/to/project/targets/debug/executable
```

Cross compile for Linux, Windows, MacOS and WASM:
```sh
nix develop .#build
cargo zigbuild --target x86_64-unknown-linux-gnu.2.36 --release --features bevy/wayland
cargo zigbuild --target x86_64-pc-windows-gnu --release
cargo zigbuild --target aarch64-apple-darwin --release # Needs SDK!
cargo zigbuild --target wasm32-unknown-unknown --release
```

- [Tweaks](docs/tweaks.md)
- [Pitfalls](docs/pitfalls.md)
- [MacOS](docs/macos.md)

---

## How does it work?

**bevy-flake** provides two different shells, `default` and `build`.

The `default` shell is allowed to use `cargo run`, and `cargo build`, but never
specify a target with `--target`.

The `build` shell is allowed to use the `cargo build` with the `--target` flag,
but never without it, and never `cargo run`.

```
default                                    build
   │                                         │
   │                                         │
   │     ╔═══════════/target/══════════╗     │
   ├─────── debug/                     ║     │
   └─────── release/                   ║     │
         ║  x86_64-unknown-linux-gnu/ ───────┤
         ║  x86_64-pc-windows-gnu/ ──────────┤
         ║  aarch64-apple-darwin/ ───────────┘
         ╚═════════════════════════════╝
```

This results in the two shells interacting with each others targets, and
therefore we don't have to worry about them flushing eachothers compilation
cache, when they meet different environment variables.

By switching out the Rust linker with `cargo-zigbuild`, we also gain the
ability to cross-compile to Windows and MacOS targets.
