# Cross-compiling for MacOS

## Adding the MacOS SDK to inputs

Get your hands on a SDK packaged into a tarball. This is either done by
packaging it yourself with [osxcross][osxcross], or finding it pre-packaged
somewhere on the internet.

[osxcross]: https://github.com/tpoechtrager/osxcross

When acquired, add it to the flake inputs as mac-sdk like so:
```diff
{
  description = "A NixOS development flake for Bevy development.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
+   mac-sdk = {
+     url = "https://website.com/path/to/macos/sdk/MacOSX(Version).tar.xz";
+     flake = false;
+   };
  };
  ...
}
```

... or, download the tarball and reference it on your local system:

```
mac-sdk = {
  url = "file:///home/user/Downloads/MacOSX(Version).tar.xz";
              # ^ Notice the extra forward-slash.
  flake = false;
};
```
