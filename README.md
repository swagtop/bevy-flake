<div align="center"> <img src="bevy-flake.webp" alt="bevy-flake" width="200"/> </div>

# bevy-flake

A simple and easy to edit Nix development flake,
for painless Bevy development and cross-compilation on NixOS.
This flake is meant to help new NixOS users to hit the ground running,
and get started quickly, with as little hassle as possible.

*This is accomplished using [rust-overlay][overlay] for the rust toolchain,
and [cargo-zigbuild][zigbuild] for cross-compilation with the Zig linker.*

[overlay]: https://github.com/oxalica/rust-overlay/
[zigbuild]: https://github.com/rust-cross/cargo-zigbuild

## Quick setup
Fetch `flake.nix` into your project root directory:
```
wget https://github.com/swagtop/bevy-flake/raw/refs/heads/main/flake.nix
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

## Detailed setup
**Setup**

Copy the `flake.nix` and `flake.lock` into your project root. 

If you want to cross-compile to MacOS, you should add a link plus hash of a
tarball of the SDK. I'm unsure if distributing the SDK is legal, so I won't be
providing a link, but you can find it hosted on github in several different
repos.

**Updating**

If you want to get newer packages, perhaps to update the Rust toolchain, run:
```
nix flake update
```
...or simply remove `flake.lock`, and a new one will be generated.

**Developing**

Enter the development shell by running:
```
nix develop
```
Now you can run your project while developing it, by running `cargo run`.
You should not be using `cargo build --target some-example-arch-and-system`
here, as the binaries made here will not be portable, and might not even
compile if targeting other platforms.

**Building**

Enter the build shell, by running:
```
nix develop .#build
```
Now you can build your project, by running
`cargo zigbuild --target some-example-arch-and-system`.
Again you should not be using `cargo build`, but `cargo zigbuild`.

When building for generic Linux systems, you should be using the Wayland
feature in bevy (Bevy will fall back to x11 if needed), like so:
```
cargo zigbuild --target x86_64-unknown-linux-gnu --features bevy/wayland --release
```
If you're not having issues with Wayland on your own machine, you can also
simply enable the Wayland feature in your `Cargo.toml`.

When compiling for generic Linux systems you can also pick the specific GLIBC
version to target. I reccomend targeting the version used by debian-stable.
Doing so will look like this, 2.36 being the targeted version:
```
cargo zigbuild --target x86_64-unknown-linux-gnu.2.36
```

## Editing the flake
**Targets**

Instead of using `cargo target add`, add targets to the `targets` section of
the `rustToolchain` section:
```
rustToolchain = pkgs.rust-bin.stable.latest.default.override {
  extensions = [ "rust-src" "rust-analyzer" ];
    targets = [
      "aarch64-apple-darwin"
      "x86_64-apple-darwin"

      "x86_64-unknown-linux-gnu"

      "x86_64-pc-windows-gnu"

      "wasm32-unknown-unknown"
          
      # Add extra targets here!
    ];
  };
```
The ones already there have been tested, and are known to work.

**Wayland**

If you're having Wayland issues, Wayland can simply be turned
off in the development shell, by commenting out the list concatnation of
`waylandPackages`, in the runtimeLib section:
```
runtimeLib = "${pkgs.lib.makeLibraryPath (with pkgs; [
  alsa-lib-with-plugins
  libGL
  libxkbcommon
  udev
  vulkan-loader
]
++ xorgPackages
++ waylandPackages # <--- Comment out if you're having Wayland issues.
)}";
```
This will still allow you to use the Bevy Wayland feature for when
cross-compiling to generic Linux systems.

**Rustflags**

To add your own rustflags, add them to the `shellHook`, redefine `RUSTFLAGS`
with your flags, followed by `$RUSTFLAGS`, like so:
```
shellHook = ''
  export RUSTFLAGS="${anonymizeBuild}"
  export RUSTFLAGS="-C target-cpu=native $RUSTFLAGS"
  export RUSTFLAGS="**YOUR FLAGS HERE** $RUSTFLAGS"
  export RUSTFLAGS="-C link-args=-Wl,-rpath,${runtimeLib} $RUSTFLAGS"
'';
```
You should add them some place after `anonymizeBuild`.

## Common issues
**Failed to build event loop**
```
Failed to build event loop: Os(OsError { line: 787, file: "/home/user/.cargo/registry/src/index.crates.io-6f17d22bba15001f/winit-0.30.8/src/platform_impl/linux/mod.rs", error: XNotSupported(LibraryOpenError(OpenError { kind: Library, detail: "opening library failed (libX11.so.6: cannot open shared object file: No such file or directory); opening library failed (libX11.so: cannot open shared object file: No such file or directory)" })) })
```
You're attempting to `cargo run` in the build shell.
Enter the development shell by running `nix develop`.

**BadDisplay**
```
Encountered a panic in system `bevy_render::renderer::render_system`!
thread 'Async Compute Task Pool (1)' panicked at /home/user/.cargo/registry/src/index.crates.io-6f17d22bba15001f/wgpu-hal-23.0.1/src/gles/egl.rs:298:14:
called `Result::unwrap()` on an `Err` value: BadDisplay
```
You're having Wayland issues. Do one of the following:
1. [Set up graphics drivers properly.][graphics] If the drivers for your
specific GPU are borked (... [*cough*][390] ...), this might not be possible.
2. Remove the Bevy Wayland feature from your `Cargo.toml`, then re-add it to
the build command when compiling in the build shell with:
`--features bevy/wayland`

[graphics]: https://wiki.nixos.org/wiki/Graphics
[390]: https://wiki.archlinux.org/title/AMDGPU#R9_390_series_poor_performance_and/or_instability

**Invalid surface**
```
2025-02-03T09:46:28.336770Z ERROR wgpu_core::device::global: surface configuration failed: incompatible window kind
thread 'Compute Task Pool (5)' panicked at /home/user/.cargo/registry/src/index.crates.io-6f17d22bba15001f/wgpu-23.0.1/src/backend/wgpu_core.rs:719:18:
Error in Surface::configure: Validation Error

Caused by:
  Invalid surface
```
You're having Wayland issues. Do one of the following:
1. [Set up graphics drivers properly.][graphics]
2. Comment out `++ waylandPackages` in the `runtimeLib` section.

**\`x86_64-w64-mingw32-gcc` not found**
```
error: linker `x86_64-w64-mingw32-gcc` not found
  |
  = note: No such file or directory (os error 2)
```

You are trying to compile to Windows using `cargo build`. You should:
1. Double check that you are in the build shell with `echo $name`, the output
should be `bevy-build-env`. If not, enter the build shell by running
`nix develop .#build`.
2. Use `cargo zigbuild` instead of `cargo build`.

**failed to run custom build command for \`blake3`**
```
  error occurred in cc-rs: Command LC_ALL="C" "gcc" "-O3" "-ffunction-sections" "-fdata-sections" "-fPIC" "-gdwarf-2" "-fno-omit-frame-pointer" "-arch" "arm64" "-mmacosx-version-min=11.0" "-Wall" "-Wextra" "-std=c11" "-o" "/home/user/Documents/git/bevy-project/target/aarch64-apple-darwin/debug/build/blake3-7165bcba79fb06bd/out/a1edd97dd51cd48d-blake3_neon.o" "-c" "c/blake3_neon.c" with args gcc did not execute successfully (status code exit status: 1).
```
You are trying to compile to MacOS using `cargo build`. You should:
1. Double check that you are in the build shell with `echo $name`, the output
should be `bevy-build-env`. If not, enter the build shell by running
`nix develop .#build`.
2. Use `cargo zigbuild` instead of `cargo build`.

**Unable to find libclang**
```
error: failed to run custom build command for `coreaudio-sys v0.2.16`

Caused by:
  process didn't exit successfully: `/home/user/Documents/git/bevy-project/target/debug/build/coreaudio-sys-04a04c3e98276752/build-script-build` (exit status: 101)
  --- stdout
  cargo:rerun-if-env-changed=COREAUDIO_SDK_PATH
  cargo:rustc-link-lib=framework=AudioUnit
  cargo:rustc-link-lib=framework=CoreAudio
  cargo:rerun-if-env-changed=BINDGEN_EXTRA_CLANG_ARGS

  --- stderr
  thread 'main' panicked at /home/user/.cargo/registry/src/index.crates.io-6f17d22bba15001f/bindgen-0.70.1/lib.rs:622:27:
  Unable to find libclang: "couldn't find any valid shared libraries matching: ['libclang.so', 'libclang-*.so', 'libclang.so.*', 'libclang-*.so.*'], set the `LIBCLANG_PATH` environment variable to a path where one of these files can be found (invalid: [])"
```
You are trying to compile to MacOS without adding a link to the MacOS SDK.
You should add it to `flake.nix`, such that `appleSdkUrl` and `appleSdkHash`
are defined like so:
```
# To compile to Apple targets, provide a link to a MacOSX*.sdk.tar.xz:
appleSdkUrl = "https://website.com/path/to/macos/sdk/MacOSX(Version).tar.xz";
# ... and the sha-256 hash of said tarball. Just the hash, no 'sha-'.
appleSdkHash = "3846886941d2d3d79b2505 !! EXAMPLE HASH !! 627cf65f692934b19b916c";
```
The hash of the tarball can be found running `sha256 MacOSX(Version).tar.xz`,
but is usually provided by the user hosting it.
