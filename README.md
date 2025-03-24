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

**bevy-flake** wraps `cargo` in a shell script that:
- Sets the appropriate `RUSTFLAGS` for the context you are compiling in.
- Swaps out the linker for the specific target you are compiling for.
- Provides the correct libraries needed for the target system.
```
                                ╭────────────────╴ cargo ╶────────────────╮
   Local NixOS System:          │                                         │   Other Systems:
                                │                                         │   
   1. RUSTFLAGS = localFlags    │     ╔═══════════target/═══════════╗     │   1. RUSTFLAGS = crossFlags
   2. RUSTFLAGS contain rpath   ├──────► debug/                     ║     │   2. cargo-zigbuild assists with
                                ╰──────► release/                   ║     │      Linux, Windows (GNULLVM), MacOS
                                      ║  x86_64-unknown-linux-gnu/ ◄──────┤   3. cargo-xwin assists with Windows (MSVC)
                                      ║  x86_64-pc-windows-msvc/ ◄────────┤   4. cargoWrapper provides aarch64-linux libraries
                                      ║  aarch64-apple-darwin/ ◄──────────╯
                                      ╚═════════════════════════════╝
```

- [Details](docs/details.md)
