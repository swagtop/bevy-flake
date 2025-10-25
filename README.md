<div align="center"> <img src="bevy-flake.svg" width="200"/> </div>

# bevy-flake

A flake for painless development and distribution of [Bevy][bevy] programs.

With `bevy-flake` you can easily configure, compile and run your project on
NixOS and MacOS, as well as cross-compile portable binaries for non-Nix Linux,
Windows and MacOS targets.

[bevy]: https://github.com/bevyengine/bevy

> [!NOTE]
> By compiling to the `*-pc-windows-msvc` targets, you are likely considered to
> be accepting the [Microsoft Software License Terms.][license]

[license]: https://go.microsoft.com/fwlink/?LinkId=2086102

> [!WARNING]
> This flake will remain stable until `2026-01-01`, where there will be an
> update that may have breaking changes, based on feedback on this initial
> release. After that, you can again count on the flake being stable.

## Quick setup

First, navigate to your Bevy project root:

```sh
cd /path/to/bevy/project
```

Then, use the template with your preferred rust toolchain provider (switching
to a different one later is super easy):

```sh
# The default with no cross-compilation, but faster evaluation:
nix flake init --template github:swagtop/bevy-flake#nixpkgs

# The one using oxalica's rust-overlay:
nix flake init --template github:swagtop/bevy-flake#rust-overlay

# The one using nix-community's fenix:
nix flake init --template github:swagtop/bevy-flake#fenix
```

If you get your toolchain from elsewhere, you should very easily be able to slot
it in. More on this [here.][config-toolchain]

[config-toolchain]: docs/config.md#mkrusttoolchain


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
  cargo build --target x86_64-unknown-linux-gnu
  cargo build --target x86_64-pc-windows-msvc
  cargo build --target aarch64-apple-darwin # <-- Read docs/macos.md!
  cargo build --target wasm32-unknown-unknown
  #  (...and so on. )

# With `dioxus-cli`, develop Bevy with hot-patching
  BEVY_ASSET_ROOT="." dx serve --hot-patch

# With `bevy-cli`, use the alpha CLI tooling that is useful for web builds:
  bevy run
  bevy run web --open

# If you've configured bevy-flake with 'buildSource = ./.', build with Nix:
  # Build all targets:
  nix build -j 3 # Restricting parallel builds with '-j 3' here.

  # Build individual targets:
  nix build .#default.x86_64-unknown-linux-gnu
  nix build .#default.x86_64-pc-windows-msvc # <-- Read docs/windows.md!
  #  (...and so on. )
```

You can compile to every target with a `config.targetEnvironment` entry.
If the target you want isn't in the config, you can add it, and set up the
environment needed for it yourself. More on that [here.](docs/config.md)

- [Configuration](docs/config.md)
- [Pitfalls](docs/pitfalls.md)
- [Windows](docs/windows.md)
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


           (1) Develop on your Nix system            (2) Cross-compile for other platforms
```

- [Details](docs/details.md)
