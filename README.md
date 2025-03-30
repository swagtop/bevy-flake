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
                                             $ cargo
                                                ▼
                              ╭──────────╴ cargo-wrapper ╶──────────╮
                              │                                     │
                              │                                     │
                              │   ╔═══════════target/═══════════╗   │
                              │────► debug/                     ║   │
                              ╰────► release/                   ║   │
                                  ║  x86_64-unknown-linux-gnu/ ◄────┤
                                  ║  x86_64-pc-windows-msvc/ ◄──────┤
                                  ║  aarch64-apple-darwin/ ◄────────╯
                                  ╚═════════════════════════════╝

                    Local NixOS System:                  Other Systems:

                    - RUSTFLAGS += localFlags            - RUSTFLAGS += crossFlags
                    - Runtime packages                   - Each targets libraries
                      provided through rpath               provided by cargo-wrapper
                    - cargo compiles for                 - cargo-zigbuild,
                      local system and runs                cargo-xwin cross compile
```
- [Details](docs/details.md)
