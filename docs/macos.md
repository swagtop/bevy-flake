# Cross-compiling for MacOS

## Adding the MacOS SDK to the `build` shell

First, you will have to acquire said SDK. This is either done by packaging it
yourself with [osxcross][osxcross], or finding it pre-packaged in a tarball
somewhere on the internet.

[osxcross]: https://github.com/tpoechtrager/osxcross

When acquired, you should first get the hash of the tarball, with
`nix-prefetch-url`:

```sh
nix-prefetch-url "https://website.com/path/to/macos/sdk/MacOSX(Version).tar.xz"
```

Then, enter the URL and hash into the `macSdk*` section of the flake:

```nix
# To compile to Apple targets, provide a link to a MacOSX*.sdk.tar.xz:
macSdkUrl = "https://website.com/path/to/macos/sdk/MacOSX(Version).tar.xz";
# ... and the sha-256 hash of said tarball. Just the hash, no 'sha-'.
macSdkHash = "3846886941d2d3d79b2505 !! EXAMPLE HASH !! 627cf65f692934b19b916c";
```

... or, to avoid re-downloading it every time your /nix/store is garbage
collected, download the tarball, and reference it on your local system:

```nix
macSdkUrl = "file:///home/user/Downloads/MacOSX(Version).tar.xz";
#                   ^ Notice the extra forward-slash.
```

If you no longer have any issues when entering the `build` shell, you should
now be able to compile to MacOS targets like so:

```sh
cargo zigbuild --target x86_64-apple-darwin
```

## Why not include the SDK in my Git repository?

The SDK tarball can take up a lot of space, and will increase the time spent
entering the `build` shell. It is also legally dubious if distributing the SDK
is allowed or not.

Regardless, I've found it to be faster when done this way, and users who don't
care about MacOS as a target, need not change or look into anything.
