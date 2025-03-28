<div align="center"> <img src="bevy-flake.svg" width="200"/> </div>

# bevy-flake

A simple and easy-to-edit Nix development flake,
for painless Bevy development and cross-compilation on NixOS.
This flake is meant to help new NixOS users hit the ground running,
and get started quickly, with as little hassle as possible.

```sh
nix develop github:swagtop/bevy-flake
```

*Using [rust-overlay][overlay] for the rust toolchain,
and [cargo-zigbuild][zigbuild], [cargo-xwin](xwin) to assist in
cross-compilation.*

[overlay]: https://github.com/oxalica/rust-overlay/
[zigbuild]: https://github.com/rust-cross/cargo-zigbuild
[xwin]: https://github.com/rust-cross/cargo-xwin

## Quick setup

Fetch `flake.nix` into your project root directory, and add it to the git index:

```sh
cd /path/to/project
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/main/flake.nix
git add flake.nix
```

Enter the development shell, and then run or compile your Bevy program:

```sh
nix develop

# Your NixOS system
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
- [MacOS](docs/macos.md)

---
```
                       ╔═══════════target/═══════════╗     Local NixOS System: 
                 ╭──────► debug/                     ║     
                 ├──────► release/                   ║     - RUSTFLAGS = localFlags
                 │     ║  x86_64-unknown-linux-gnu/  ║     - Runtime packages 
                 │     ║  x86_64-pc-windows-msvc/    ║       provided through rpath 
                 │     ║  aarch64-apple-darwin/      ║     - cargo builds for 
                 │     ╚═════════════════════════════╝       local system and runs
                 │
                 │
                 │                             $ cargo
                 │                                ▼
                 ╰─────────────────────────╴ cargo-wrapper ╶─────────────────────────╮
                                                                                     │
                                                                                     │
                                                                                     │
                                                                                     │
                    Other Systems:               ╔═══════════target/═══════════╗     │
                                                 ║  debug/                     ║     │
                    - RUSTFLAGS = crossFlags     ║  release/                   ║     │
                    - Each targets libraries     ║  x86_64-unknown-linux-gnu/ ◄──────┤
                      provided by cargo-wrapper  ║  x86_64-pc-windows-msvc/ ◄────────┤
                    - cargo-zigbuild,            ║  aarch64-apple-darwin/ ◄──────────╯
                      cargo-xwin build           ╚═════════════════════════════╝
```
- [Details](docs/details.md)
