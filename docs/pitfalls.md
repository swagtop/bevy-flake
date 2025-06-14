# Pitfalls

If nothing on this page helps you, feel free to open an issue [here][github],
and I will try to help you as best as I can!

[github]: https://github.com/swagtop/bevy-flake/issues

## Errors

### Failed to build event loop

```
Failed to build event loop: Os(OsError { line: 787, file: "/home/user/.cargo/registry/src/index.crates.io-6f17d22bba15001f/winit-0.30.8/src/platform_impl/linux/mod.rs", error: XNotSupported(LibraryOpenError(OpenError { kind: Library, detail: "opening library failed (libX11.so.6: cannot open shared object file: No such file or directory); opening library failed (libX11.so: cannot open shared object file: No such file or directory)" })) })
```
You are trying to `cargo run`, without the `rpath` flag in `localFlags`.
Re-add it, and try again.

### BadDisplay

```
Encountered a panic in system `bevy_render::renderer::render_system`!
thread 'Async Compute Task Pool (1)' panicked at /home/user/.cargo/registry/src/index.crates.io-6f17d22bba15001f/wgpu-hal-23.0.1/src/gles/egl.rs:298:14:
called `Result::unwrap()` on an `Err` value: BadDisplay
```
You're having Wayland issues. Do one of the following:
1. [Set up graphics drivers properly.][graphics] If the drivers for your
specific GPU are borked, this might not be possible.
2. Remove the Bevy Wayland feature from your `Cargo.toml`. You can re-add it
while compiling for other systems, with the flag: `--features bevy/wayland`

[graphics]: https://wiki.nixos.org/wiki/Graphics

### Invalid surface

```
2025-02-03T09:46:28.336770Z ERROR wgpu_core::device::global: surface configuration failed: incompatible window kind
thread 'Compute Task Pool (5)' panicked at /home/user/.cargo/registry/src/index.crates.io-6f17d22bba15001f/wgpu-23.0.1/src/backend/wgpu_core.rs:719:18:
Error in Surface::configure: Validation Error

Caused by:
  Invalid surface
```
You're having Wayland issues. Do one of the following:
1. [Set up graphics drivers properly.][graphics]
2. Comment out `++ waylandPackages` in the `runtimePackages` section.

### \`x86_64-w64-mingw32-gcc` not found
```
error: linker `x86_64-w64-mingw32-gcc` not found
  |
  = note: No such file or directory (os error 2)
```

You are trying to compile to Windows-GNU using `cargo build`. You should:
1. Use the MSVC target instead. `bevy-flake` no longer supports this target.
2. Refrain from using the `--no-wrapper` flag here.
3. Use `cargo zigbuild` instead of `cargo build`.

### failed to run custom build command for \`blake3`

```
  error occurred in cc-rs: Command LC_ALL="C" "gcc" "-O3" "-ffunction-sections" "-fdata-sections" "-fPIC" "-gdwarf-2" "-fno-omit-frame-pointer" "-arch" "arm64" "-mmacosx-version-min=11.0" "-Wall" "-Wextra" "-std=c11" "-o" "/home/user/Documents/git/bevy-project/target/aarch64-apple-darwin/debug/build/blake3-7165bcba79fb06bd/out/a1edd97dd51cd48d-blake3_neon.o" "-c" "c/blake3_neon.c" with args gcc did not execute successfully (status code exit status: 1).
```
You are trying to compile to MacOS without using `cargo-zigbuild`. You should:
1. Refrain from using the `--no-wrapper` flag here.
2. Use `cargo zigbuild` instead of `cargo build`.

### Unable to find libclang

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

You have removed the exporting of `LIBCLANG_PATH` in the shellscript. Re-add it.

## Mimalloc

Currently you cannot compile with mimalloc on WASM or MacOS targets.

If you still want to use it in your project for the other targets, you can
disable it from these targets like so:

Only add the `mimalloc` crate as a dependency only if not `wasm32` or `macos` in
your `Cargo.toml`.

```toml
[target.'cfg(all(not(target_arch = "wasm32"), not(target_os = "macos")))'.dependencies.mimalloc]
version = "0.1.45"
```

Then, only assign the global allocator in your `main.rs` if not these targets
as well.

```rust
#[cfg(all(not(target_arch = "wasm32"), not(target_os = "macos")))]
mod init_mimalloc {
    use super::*;
    use mimalloc::MiMalloc;

    #[global_allocator]
    static GLOBAL: MiMalloc = MiMalloc;
}
```
