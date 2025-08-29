<div align="center"> <img src="bevy-flake.svg" width="200"/> </div>

# bevy-flake

A simple and easy-to-edit Nix development flake, for painless [Bevy][bevy]
development and cross-compilation from Linux, MacOS and NixOS.

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
#### Option 1: Use the template with your preferred rust toolchain provider

```sh
nix flake init --template github:swagtop/bevy-flake/dev#rust-overlay
# ... or ...
nix flake init --template github:swagtop/bevy-flake/dev#fenix
```

#### Option 2: Wrap the toolchain used in your existing flake

```nix
{
  # Add bevy-flake to inputs.
  inputs = {
    # ...
    bevy-flake = {
      url = "github:swagtop/bevy-flake/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  # ...
}
```

```nix
  pkgs.mkShell {
    # ...
    packages = [
      # Override the `wrapped-rust-toolchain` package.
      (bevy-flake.packages.${system}.wrapped-toolchain.override {
        rust-toolchain = existing-rust-toolchain;
      })
      # ...
    ];
  };
```

#### Option 3: Copy flake

Fetch `flake.nix` and `flake.lock`, and add them to the git index:

```sh
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/dev/flake.nix
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/dev/flake.lock
git add flake.nix flake.lock
```

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
                             ╭────1───╴ wrapped-rust-toolchain ╶────2───╮
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

                    - RUSTFLAGS += localFlags         - RUSTFLAGS += crossFlags
                    - Runtime packages                - Each targets libraries
                      provided through rpath            provided by cargo-wrapper
                    - cargo compiles for              - cargo-zigbuild,
                      local system and runs             cargo-xwin cross-compile
```

- [Details](docs/details.md)
