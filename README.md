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

Cross compile for Linux, Windows, MacOS and WASM:
```sh
nix develop
cargo build --target x86_64-unknown-linux-gnu.2.36 --release
cargo build --target x86_64-pc-windows-gnu --release
cargo build --target aarch64-apple-darwin --release # Needs SDK!
cargo build --target wasm32-unknown-unknown --release
```

- [Tweaks](docs/tweaks.md)
- [Pitfalls](docs/pitfalls.md)
- [MacOS](docs/macos.md)

---

**bevy-flake** wraps `cargo` in a shell script, setting the `RUSTFLAGS`
environment variable appropreate for the situation, and using `cargo-zigbuild`
to cross compile.

```
                          ╭────────────────╴ cargo ╶────────────────╮
                          │                                         │
            (localFlags)  │                                         │  (crossFlags)
                          │     ┏━━━━━━━━━━╸target/╺━━━━━━━━━━┓     │
                          ├──────► debug/                     ┃     │
                          ╰──────► release/                   ┃     │
                                ┃  x86_64-unknown-linux-gnu/ ◂──────┤
                                ┃  x86_64-pc-windows-gnu/  ◂────────┤
                                ┃  aarch64-apple-darwin/ ◂──────────╯
                                ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

- [Details](docs/details.md)
