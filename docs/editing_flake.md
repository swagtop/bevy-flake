# Editing the flake
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
