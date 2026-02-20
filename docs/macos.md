# Cross-compiling for MacOS

## Adding the MacOS SDK to the config

Regardless of if you are on MacOS or not, you need to add a MacOS SDK to your
bevy-flake instance to compile a portable MacOS binary for non-Nix systems.

This is done by first getting your hands on an SDK. You can package one
yourself quite easily, using a helper script powered by [osxcross][osxcross],
included in this flake.

You will not find a link to one anywhere on this repo.

[osxcross]: https://github.com/tpoechtrager/osxcross

> [!NOTE]
> By packaging and using the MacOS SDK, you are agreeing with the
> [Xcode and Apple SDKs Agreement.][license]

[license]: https://www.apple.com/legal/sla/docs/xcode.pdf


## Using a packaged SDK

1. Acquire a URL to a packaged SDK. This can be done by packaging one yourself,
   or finding a pre-packaged one online. Regardless of where you find it, you
   should upload it yourself, so that you don't risk the one you are using
   becoming unavailable.

   The reproducability of your project is dependent on this SDK being available.

2. Add it to your config like so:
   ```nix
   bf = bevy-flake.configure {
     mac.sdk = fetchTarball {
       url = "https://website.com/path/to/macos/sdk/MacOSX__.tar.xz";
       sha256 = "sha256:some-long-hash-string-goes-here";
     };
   };
   ```


## Packaging 

1. Download Xcode (version 8.0 or above) from
   [here.](https://developer.apple.com/download/all/?q=xcode)
   You will need an Apple ID to do this.

2. Run:
   ```sh
   nix run github:swagtop/bevy-flake#rust-toolchain.package-macos-sdk <xcode.xip>
   ```
   ... where `<xcode.xip>` is the path to the Xcode archive you have downloaded.

3. Upload the resulting `MacOSX__.sdk.tar.xz` file somewhere Nix can fetch it
   from. This could be a fileserver, or the releases section of your repo
   (provided it is public). You could make an empty repo for the sole purpose of
   uploading these SDK's.


## Structure of the SDK

The base directory of the SDK should look something like this:

```
path/to/sdk/
         ├─ Entitlements.plist
         ├─ SDKSettings.json
         ├─ SDKSettings.plist
         ├─ System/
         ╰─ usr/
```

If the root directory of the tarball you've unpacked doesn't look like this, and
this structure is found inside of subpath of the SDK, you can scope in on it
like so:

```nix
macos.sdk = fetchTarball {
  url = "https://website.com/path/to/macos/sdk/MacOSX(Version).tar.xz";
  sha256 = "sha256:some-long-hash-string-goes-here";
} + "/sub-path";
```


## General advice

You should never add the SDK tarball to your projects git repo. Flakes copy the
repository they are in to the Nix store on evaluation, and you will therefore
end up with very long evaluation times, and many wasteful copies of the SDK.
