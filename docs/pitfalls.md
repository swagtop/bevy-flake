# Pitfalls

## Failed to build event loop
```
Failed to build event loop: Os(OsError { line: 787, file: "/home/user/.cargo/registry/src/index.crates.io-6f17d22bba15001f/winit-0.30.8/src/platform_impl/linux/mod.rs", error: XNotSupported(LibraryOpenError(OpenError { kind: Library, detail: "opening library failed (libX11.so.6: cannot open shared object file: No such file or directory); opening library failed (libX11.so: cannot open shared object file: No such file or directory)" })) })
```
You're attempting to `cargo run` in the build shell.
Enter the development shell by running `nix develop`.

## BadDisplay
```
Encountered a panic in system `bevy_render::renderer::render_system`!
thread 'Async Compute Task Pool (1)' panicked at /home/user/.cargo/registry/src/index.crates.io-6f17d22bba15001f/wgpu-hal-23.0.1/src/gles/egl.rs:298:14:
called `Result::unwrap()` on an `Err` value: BadDisplay
```
You're having Wayland issues. Do one of the following:
1. [Set up graphics drivers properly.][graphics] If the drivers for your
specific GPU are borked, this might not be possible.
2. Remove the Bevy Wayland feature from your `Cargo.toml`, then re-add it to
the build command when compiling in the build shell with:
`--features bevy/wayland`

[graphics]: https://wiki.nixos.org/wiki/Graphics

## Invalid surface
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

## \`x86_64-w64-mingw32-gcc` not found
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

## failed to run custom build command for \`blake3`
```
  error occurred in cc-rs: Command LC_ALL="C" "gcc" "-O3" "-ffunction-sections" "-fdata-sections" "-fPIC" "-gdwarf-2" "-fno-omit-frame-pointer" "-arch" "arm64" "-mmacosx-version-min=11.0" "-Wall" "-Wextra" "-std=c11" "-o" "/home/user/Documents/git/bevy-project/target/aarch64-apple-darwin/debug/build/blake3-7165bcba79fb06bd/out/a1edd97dd51cd48d-blake3_neon.o" "-c" "c/blake3_neon.c" with args gcc did not execute successfully (status code exit status: 1).
```
You are trying to compile to MacOS using `cargo build`. You should:
1. Double check that you are in the build shell with `echo $name`, the output
should be `bevy-build-env`. If not, enter the build shell by running
`nix develop .#build`.
2. Use `cargo zigbuild` instead of `cargo build`.

## Unable to find libclang
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
Check out the [MacOS section.](macos.md)
