<div align="center"> <img src="bevy-flake.svg" alt="bevy-flake" width="200"/> </div>

# bevy-flake

A simple and easy-to-edit Nix development flake,
for painless Bevy development and cross-compilation on NixOS.
This flake is meant to help new NixOS users hit the ground running,
and get started quickly, with as little hassle as possible.

*This is accomplished using [rust-overlay][overlay] for the rust toolchain,
and [cargo-zigbuild][zigbuild] for cross-compilation with the Zig linker.*

[overlay]: https://github.com/oxalica/rust-overlay/
[zigbuild]: https://github.com/rust-cross/cargo-zigbuild

## Quick setup
Fetch `flake.nix` into your project root directory, and add to git index:
```
cd /path/to/project
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/main/flake.nix
git add flake.nix
```

Compile and run Bevy project for local machine:
```
nix develop
cargo run
```

Cross compile for Linux, Windows, MacOS and WASM:
```
nix develop .#build
cargo zigbuild --target x86_64-unknown-linux-gnu.2.36 --release --features bevy/wayland
cargo zigbuild --target x86_64-pc-windows-gnu --release
cargo zigbuild --target aarch64-apple-darwin --release # Needs SDK!
cargo zigbuild --target wasm32-unknown-unknown --release
```

- [Detailed setup](docs/detailed_setup.md)
- [Editing flake](docs/editing_flake.md)
- [Common issues](docs/common_issues.md)
