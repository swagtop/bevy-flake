# Cross-compiling for Windows

## Adding the Windows SDK to the config

By default the SDK is pulled from nixpkgs.


## Using a packaged SDK

The SDK is carefully packaged to include all symlinks at the very end of the
archive, such that it can be properly unpacked on any systems. This flake
includes a helper function to unpack these carefully packaged tarballs, which
you can use like so:
```nix
{ helpers, ... }:
{
   windows.sdk = helpers.fetchWindowsSDK {
     url = "https://website.com/path/to/windows/sdk/WindowsMSVC<version>.sdk.tar.xz";
     sha256 = "sha256:some-long-hash-string-goes-here";
   };
}
```
> [!NOTE]
> By packaging and using the Windows MSVC SDK, you are agreeing with the
> [Microsoft Software License Terms.][license]

[license]: https://go.microsoft.com/fwlink/?LinkId=2086102

## Packaging 

> ![IMPORTANT]
> This can only be run on Linux systems, as the Windows MSVC SDK produced by
> nixpkgs on MacOS systems are missing critical symlinks needed on
> case-sensitive systems.

Run:
```sh
nix run github:swagtop/bevy-flake#tools.package-windows-sdk
```
This will fetch the latest Windows MSVC SDK from the nixpkgs repository, and
package it into a 


## Structure of the SDK

The base directory of the SDK should look something like this:

```
sdk/
crt/
```

If the root directory of the tarball you've unpacked doesn't look like this, and
this structure is found inside of subpath of the SDK, you can scope in on it
like so:

```nix
helpers.fetchWindowsSDK {
  url = "https://website.com/path/to/windows/sdk/WindowsMSVC<version>.sdk.tar.xz";
  sha256 = "sha256:some-long-hash-string-goes-here";
} + "/sub-path";
```


## General advice

You should never add the SDK tarball to your projects git repo. Flakes copy the
repository they are in to the Nix store on evaluation, and you will therefore
end up with very long evaluation times, and many wasteful copies of the SDK.
