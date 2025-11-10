<div align="center"> <img src="bevy-flake.svg" width="200"/> </div>

# bevy-flake

A flake for painless development and distribution of [Bevy][bevy] programs.

With `bevy-flake` you can easily configure, compile and run your project on
NixOS and MacOS, as well as cross-compile portable binaries for non-Nix Linux,
Windows and MacOS targets.

[bevy]: https://github.com/bevyengine/bevy

> [!NOTE]
> By compiling to the Windows MSVC targets, you are accepting the
> [Microsoft Software License Terms.][license]

[license]: https://go.microsoft.com/fwlink/?LinkId=2086102

> [!WARNING]
> This flake will remain stable until `2026-01-01`, where there will be an
> update that may have breaking changes, based on feedback on this initial
> release. After that, you can again count on the flake being stable.

## Quick setup

Navigate to your Bevy project root, then pull the template with your preferred
Rust toolchain provider:

```sh
# The one using oxalica's rust-overlay:
nix flake init --template github:swagtop/bevy-flake#rust-overlay
```
```sh
# The one using nix-community's fenix:
nix flake init --template github:swagtop/bevy-flake#fenix
```
```sh
# The one from nixpkgs with no cross-compilation, but no extra inputs:
nix flake init --template github:swagtop/bevy-flake#nixpkgs
```

Switching later is very easy, and you should very easily be able to use any
other toolchain provider not listed here. More on this [here.][config-toolchain]

[config-toolchain]: docs/config.md#the-mk-functions


## How to use

Add the packages you want from `bevy-flake` to your environment with
`nix develop`, with `nix shell .#package-name`, or other means.

Then, you can use them like so:

```sh
# With 'rust-toolchain', run and compile both for yours and other platforms:
# For your Nix system you can run:
cargo build
cargo run

# For other targets, just use '--target':
cargo build --target x86_64-pc-windows-msvc
```
```sh
# With `dioxus-cli`, develop Bevy with hot-patching:
BEVY_ASSET_ROOT="." dx serve --hot-patch --features bevy/hotpatching
```
```sh
# With `bevy-cli`, use the alpha CLI tooling that is useful for web builds:
bevy run
bevy run web --open
```

If you've set `buildSource = ./.` in the config, you can build your project
using Nix:

```sh
# Build all targets:
nix build .#targets -j 1 # Restricting builds to one at a time with '-j 1'.

# Build individual targets:
nix build .#targets.x86_64-unknown-linux-gnu

# Build your project from any machine with access to your repo:
nix build github:username/repository/branch#targets -j 1
```

You can compile to every target with a `targetEnvironments` [entry.][entries]
If the target you want isn't in the config, you can add it, and set up the
environment needed for it yourself. More on that [here.][environments]

[entries]: flake.nix#L89
[environments]: docs/config.md#environments

- [Configuration](docs/config.md)
- [Pitfalls](docs/pitfalls.md)
- [MacOS](docs/macos.md)

--------------------------------------------------------------------------------

```
                                            $ cargo
                                                ▼
                                 [bevy-flake Environment Adapters]
                                                ▼
                             ╭─────1────╴ rust-toolchain ╶─────2──────╮
                             │                                        │
                             │                                        │
                             │    ╔═══════════target/═══════════╗     │
                             ├─────► debug/                     ║     │
                             ╰─────► release/                   ║     │
                                  ║  x86_64-unknown-linux-gnu/ ◄──────┤
                                  ║  x86_64-pc-windows-msvc/ ◄────────┤
                                  ║  aarch64-apple-darwin/ ◄──────────┤
                                  ║    (...and so on. )  ◄────────────╯
                                  ╚═════════════════════════════╝


      (1) Develop on your Nix systems                          Cross-compile for targets (2)
```

- [Details](docs/details.md)
