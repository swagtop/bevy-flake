# Details

## Who is this for?

This flake is for developers who just want to develop Bevy on their NixOS
system, while also having the ability to distribute their games to other
operating systems, without needing to rely on GitHub Actions, or the like.

It is designed to be as close to a drop-in solution as possible, such that users
can easily integrate it into their existing workflow.

*This flake is not made for packaging your Bevy project for Nix. For that you*
*should use something like [Naersk.][naersk]*

[naersk]: https://github.com/nix-community/naersk

## How does `cargo-wrapper` work?

The shell provided with the flake wraps `cargo` in a shell script, that adapts
your environment based on the target in 4 steps:

### Step 1: Check for a target

The script checks for the `--target` flag, and if found saves the following
arg string in the `BEVY_FLAKE_TARGET` variable.

```bash
# Check if cargo is being run with '--target', or '--no-wrapper'.
ARG_COUNT=0
for arg in "$@"; do
  ARG_COUNT=$((ARG_COUNT + 1))
  case $arg in
    --target)
      # Save next arg as target.
      eval "BEVY_FLAKE_TARGET=\$$((ARG_COUNT + 1))"
    ;;
    --no-wrapper)
      # Remove '--no-wrapper' from args, run cargo without changed env.
      set -- $(printf '%s\n' "$@" | grep -vx -- '--no-wrapper')
      exec ${rust-toolchain}/bin/cargo "$@"
    ;;
  esac
done
```

This is also where it checks for the `--no-wrapper` flag. If it encounters it
here, it removes it from the arguments, and calls `exec` on an unwrapped version
of `cargo` with said arguments. This replaces the current process with the
unwrapped version of `cargo`, and the script therefore stops dead in its tracks.

### Step 2: Swap out linker based on `BEVY_FLAKE_TARGET`

`bevy-flake` relies on `cargo-zigbuild` and `cargo-xwin` to cross-compile for
all non-NixOS targets. For convenience (and to save you from accidentally using
`cargo build`), the shell script edits your arguments to fit the target.

```bash
# Make sure first argument of 'cargo' is correct for target.
case $BEVY_FLAKE_TARGET in
  *-unknown-linux-gnu*);&
  *-apple-darwin);&
  wasm32-unknown-unknown)
    if [ "$1" = 'build' ]; then
      echo "bevy-flake: Aliasing 'build' to 'zigbuild'" 1>&2 
      shift
      set -- "zigbuild" "$@"
    fi
  ;;
  *-pc-windows-msvc)
    if [ "$1" = 'build' ] || [ "$1" = 'run' ]; then
      echo "bevy-flake: Aliasing 'build' to 'xwin build'" 1>&2 
      set -- "xwin" "$@"
    fi
  ;;
esac
```

### Step 3: Set environment variables for all targets

This is a small section, where we simply export environment variables that are
used - or could be used - by any target. You can add your own here!

```bash
# Environment variables for all targets.
## Stops 'blake3' from messing up.
export CARGO_FEATURE_PURE=1
## Needed for MacOS target, and many non-bevy crates.
export LIBCLANG_PATH="${pkgs.libclang.lib}/lib"
```

### Step 4: Set environment variables for individual targets

Finally individual targets each get their own environment variables. Here we see
the `aarch64-unknown-linux-gnu*` target editing the `PKG_CONFIG_PATH` variable
to push its own headers to the front of the search path. This allows us to
compile to both ARM and x86-64 linux in the same shell.

```bash
# Set final environment variables based on target.
case $BEVY_FLAKE_TARGET in
  # No target means local system, sets localFlags if running or building.
  "")
    if [ "$1" = 'zigbuild' ] || [ "$1 $2" = 'xwin build' ]; then
      echo "bevy-flake: Cannot use 'cargo $@' without a '--target'"
      exit 1
    elif [ "$1" = 'run' ] || [ "$1" = 'build' ]; then
      RUSTFLAGS="${localFlags} $RUSTFLAGS"
    fi
  ;;

  aarch64-unknown-linux-gnu*)
    PKG_CONFIG_PATH="${aarch64LinuxHeaders}:$PKG_CONFIG_PATH"
    RUSTFLAGS="${crossFlags} $RUSTFLAGS"
  ;;
  x86_64-unknown-linux-gnu*|wasm32-unknown-unknown|*-pc-windows-msvc)
    RUSTFLAGS="${crossFlags} $RUSTFLAGS"
  ;;
  *-apple-darwin)
    # Set up MacOS cross-compilation environment if SDK is in inputs.
    ${if (inputs ? mac-sdk) then macEnvironment else "# None found."}
  ;;
esac
```

This is where `localFlags` and `crossFlags` are added to RUSTFLAGS.

Here we also how the MacOS targets get their SDK and environment variables
exposed, when the `mac-sdk` input is available. Nix is lazily evaluated, so we
don't get any runtime errors for erronious references to a non-existing SDK, if
it is not available.

More on adding the MacOS SDK in: [MacOS](macos.md).

### Finally: Run cargo with adapted environment:

If no errors were encounted, we finally run the unwrapped `cargo` with our
new `RUSTFLAGS`, and other environment variables. I've set it up such that
`cargo-wrapper` builds the `RUSTFLAGS` upon any existing ones, allowing you to
do `RUSTFLAGS=foo` from outside the wrapper.

```bash
# Run cargo with relevant RUSTFLAGS.
RUSTFLAGS=$RUSTFLAGS exec ${rust-toolchain}/bin/cargo "$@"
```

More on tweaking the flake in: [Tweaks](tweaks.md).
