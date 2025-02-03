# Detailed setup
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
