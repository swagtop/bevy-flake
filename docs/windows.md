# Cross-compiling for Windows

## Information

This flake primarily focuses on using the MSVC ABI. It is generally said that
if you are building for Windows, you should be using `*-msvc`. Compiling to the
`*-gnu` targets is viable as well, and you can configure `bevy-flake` to use
these targets with a little extra setup.

To support the `-msvc` targets, `bevy-flake` uses `cargo-xwin` configured to
use [windows-msvc-sysroot.](https://github.com/trcrsired/windows-msvc-sysroot)

## Fetching the SDK and CRT

The sysroot is fetched automatically when you compile to a `*-msvc` target, when
you don't have one defined. It gets put into your
`$XDG_CACHE_DIR/bevy-flake/xwin` directory, or just
`$HOME/.cache/bevy-flake/xwin` if you do not have the former configured.

If you are on MacOS, it will be in the `$HOME/Library/Caches/bevy-flake`
directory.

## Packaging the SDK and CRT

To make sure you're always using the same sysroot, you can package the one
you've fetched. Go to the directory where the sysroot has been fetched to. It
should look something like this:

```
path/to/cache/bevy-flake/xwin/
  ├─ clang_cl
  ├─ cmake/
  ├─ lld-link
  ├─ llvm-dlltool
  ├─ llvm-lib
  ╰─ windows-msvc-sysroot/
```

Make a tarball from the `windows-msvc-sysroot` directory. It could be useful for
you to mark when you've packaged it with the current date:

```bash
tar cJf "windows-msvc-sysroot-$(date '+%Y-%m-%d').tar.xz" ./windows-msvc-sysroot
```

Then upload this tarball somewhere, and it in your `config.windows`
configuration like so:

```nix
bf = bevy-flake.override {
  # ...
  windows.sysroot = pkgs.fetchTarball {
    url = "https://website.com/path/to/sysroot/windows-msvc-sysroot-date.tar.xz";
    sha256 = "sha256:some-long-hash-string-goes-here";
  };
  # ...
};
```

When unpacked into the store, the contents should look like this:

```
/nix/store/<hash>-windows-msvc-sysroot/
  ├─ DONE
  ╰─ windows-msvc-sysroot/
       ├─ bin/
       ├─ include/
       ├─ lib/
       ├─ LICENSE
       ├─ README.md
       ╰─ share/
```
