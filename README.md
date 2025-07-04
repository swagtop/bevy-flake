<div align="center"> <img src="bevy-flake.svg" width="200"/> </div>

# bevy-flake

A simple and easy-to-edit Nix development flake,
for painless [Bevy][bevy] development and cross-compilation on NixOS.
This flake is meant to help new NixOS users hit the ground running,
and get started quickly, with as little hassle as possible.

```sh
nix develop github:swagtop/bevy-flake
```

*Using [rust-overlay][overlay] for the rust toolchain,
and [cargo-zigbuild][zigbuild], [cargo-xwin](xwin) to assist in
cross-compilation.*

[bevy]: https://github.com/bevyengine/bevy
[overlay]: https://github.com/oxalica/rust-overlay/
[zigbuild]: https://github.com/rust-cross/cargo-zigbuild
[xwin]: https://github.com/rust-cross/cargo-xwin

## Quick setup

Navigate to your Bevy project root:

```sh
cd /path/to/bevy/project
```

Fetch `flake.nix` and `flake.lock`, and add them to the git index:

```sh
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/main/flake.nix
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/main/flake.lock
git add flake.nix flake.lock
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

--------------------------------------------------------------------------------

> [!NOTE]
> This flake is still under development.
>
> I'm constantly trying new things to get the smoothest NixOS experience with
> Bevy possible.

```
                                             $ cargo
                                                 ▼
                             ╭─────1─────╴ cargo-wrapper ╶─────2─────╮
                             │                                       │
                             │                                       │
                             │    ╔═══════════target/═══════════╗    │
                             ├─────► debug/                     ║    │
                             ╰─────► release/                   ║    │
                                  ║  x86_64-unknown-linux-gnu/ ◄─────┤
                                  ║  x86_64-pc-windows-msvc/ ◄───────┤
                                  ║  aarch64-apple-darwin/ ◄─────────╯
                                  ╚═════════════════════════════╝

                    (1) Local NixOS System:           (2) Other Systems:

                    - RUSTFLAGS += localFlags         - RUSTFLAGS += crossFlags
                    - Runtime packages                - Each targets libraries
                      provided through rpath            provided by cargo-wrapper
                    - cargo compiles for              - cargo-zigbuild,
                      local system and runs             cargo-xwin cross-compile
```

- [Details](docs/details.md)
