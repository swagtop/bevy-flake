# Details

## Who is this for?

Developers who just want to develop Bevy on their NixOS system, while also
having the ability to distribute their games to other operating systems,
without needing to rely on GitHub Actions, or the like.

This flake is not made for packaging your game for Nix. For that you should use
something like [Naersk.][naersk]

[naersk]: https://github.com/nix-community/naersk

## Inner workings of the shells

### The `default` shell

Bevy gains access to the correct libraries, through the `rpath` rust-flag:
```nix
let
  ...
  runtimePackages = (with pkgs; [
    alsa-lib-with-plugins
    libGL
    libxkbcommon
    udev
    vulkan-loader
  ]
  ++ xorgPackages
  ++ waylandPackages # <--- Comment out if you're having Wayland issues.
  );

  # Make '/path/to/lib:/path/to/another/lib' string from runtimePackages.
  rpathLibrary = "${lib.makeLibraryPath runtimePackages}";
  ...
in {
  devShells = {
    default = pkgs.mkShell {
      ...
      shellHook = ''
        ...
        export RUSTFLAGS="-C link-args=-Wl,-rpath,${rpathLibrary}"
      '';
    }
  }
  ...
}
```

Other shells do this through `LD_LIBRARY_PATH`, but this requires you to set it
every time you want to run the binary. Setting it with `rpath` lets you run the
binary even if you're no longer in the `default` shell.

More packages can be added to the `default` shell, by adding them to the
`devShellPackages` list. This is also where you can add `mold` as a linker, to
minimize time spent staring at the compilation progress bar while developing.
[More on that here.](tweaks.md#using-the-mold-linker)

### The `build` shell

Compiling Bevy to other systems with `cargo build`, requires you to have all
kinds of `pkgsCross` libraries in your Nix shell. That is, unless you use
`cargo-zigbuild`.

Turns out that the `Zig` linker can do this stuff out-of-the-box. It also
avoids the issue of Linux builds hardlinking the ELF interpreter to somewhere
in `/nix/store`.
