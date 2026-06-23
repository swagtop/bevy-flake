# Cross-compiling for MacOS

## Why do you need the MacOS SDK

Regardless of if you are on MacOS or not, you need to add a MacOS SDK to your
bevy-flake instance to compile a portable MacOS binary for non-Nix systems.

This is because Apple makes it hard to build for MacOS outside of their own
hardware. They disallow the distribution of their SDK by anyone other than
themselves, and therefore nixpkgs no longer has it in their repo. This is
also why there is no MacOS SDK pre-configured in `bevy-flake` by default.

You can find or make your own MacOS SDK quite easily, and after you have done
that, configuring it in `bevy-flake` is trivial.

You will not find a link to a MacOS SDK in this repo.

> [!NOTE]
> By building and developing with the MacOS SDK, you are agreeing with the
> [Xcode and Apple SDKs Agreement.][license]

[license]: https://www.apple.com/legal/sla/docs/xcode.pdf


## Adding the MacOS SDK to the config

1. Get your hands on a MacOS SDK tarball.

   You can find one online, or package and make it available to yourself,
   such that Nix can download it from a URL. Referencing a different user or
   websites tarball is not recommended, as your MacOS builds stop working,
   should you lose access to it.

2. Add it to your config like so:
   ```nix
   { pkgs, ... }:
   {
     macos.sdk = pkgs.fetchzip {
       url = "https://website.com/path/to/macos/sdk/MacOSX<version>.sdk.tar.xz";
       sha256 = "sha256:some-long-hash-string-goes-here";
     };
   };
   ```

3. If Nix complains about a hash mismatch, simply replace the 'sha256' value
   with what Nix actually got.


## Packaging 

Packaging the MacOS SDK yourself is made easy by a helper script powered by
[osxcross.][osxcross]

[osxcross]: https://github.com/tpoechtrager/osxcross

1. Download Xcode (version 8.0 or above) from
   [here.](https://developer.apple.com/download/all/?q=xcode)
   You will need an Apple ID to do this.

2. Run:
   ```sh
   nix run github:swagtop/bevy-flake#rust-toolchain.package-macos-sdk <xcode.xip>
   ```
   ... where `<xcode.xip>` is the path to the Xcode archive you have downloaded.

3. You now have a `MacOSX<version>.sdk.tar.xz` file in the directory you are in,
   which unpacks into the MacOS SDK.


## Structure of the SDK

The base directory of the SDK should look something like this:

```
Entitlements.plist
SDKSettings.json
SDKSettings.plist
System/
usr/
```

If the root directory of the tarball you've unpacked doesn't look like this, and
this structure is found inside of subpath of the SDK, you can scope in on it
like so:

```nix
pkgs.fetchzip {
  url = "https://website.com/path/to/macos/sdk/MacOSX<version>.sdk.tar.xz";
  sha256 = "sha256:some-long-hash-string-goes-here";
} + "/sub-path";
```


## General advice

You should never add the SDK tarball to your projects git repo. Flakes copy the
repository they are in to the Nix store on evaluation, and you will therefore
end up with very long evaluation times, and many wasteful copies of the SDK.
