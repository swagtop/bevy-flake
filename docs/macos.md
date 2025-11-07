# Cross-compiling for MacOS

## Adding the MacOS SDK to inputs

Regardless of if you are on MacOS or not, you need to add a MacOS SDK to your
bevy-flake instance to compile a portable MacOS binary for non-Nix systems.

This is done by first getting your hands on an SDK. You can make one yourself by
using [osxcross][osxcross], but you can probably find one already packaged for
you somewhere on the internet.

You will not find a link to one anywhere on this repo.

[osxcross]: https://github.com/tpoechtrager/osxcross

When acquired, you can add it to your `bevy-flake` configuration via. an
override:

```nix
bf = bevy-flake.override {
  # ...
  mac.sdk = builtins.fetchTarball {
    url = "https://website.com/path/to/macos/sdk/MacOSX(Version).tar.xz";
    sha256 = "sha256:some-long-hash-string-goes-here";
  };
  # ...
};
```


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
macos.sdk = builtins.fetchTarball {
  url = "https://website.com/path/to/macos/sdk/MacOSX(Version).tar.xz";
  sha256 = "sha256:some-long-hash-string-goes-here";
} + "/sub-path";
```


## General advice

You should never add the SDK tarball to your projects git repo. Flakes copy the
repository they are in to the Nix store on evaluation, and you will therefore
end up with very long evaluation times, and many wasteful copies of the SDK.

If you are getting the SDK prepackaged from somewhere, it could be a good idea
for you to upload it yourself somewhere, such that you are sure you can always
get your hands on it, should the original place you've gotten it from go down.
