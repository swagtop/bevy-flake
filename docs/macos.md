# Cross-compiling for MacOS

## Adding the MacOS SDK to the `build` shell

First, you will have to acquire said SDK. This is either done by packaging it
yourself with [osxcross][osxcross], or finding it pre-packaged in a tarball
somewhere on the internet.

[osxcross]: https://github.com/tpoechtrager/osxcross

When acquired, add it to the flake inputs as mac-sdk like so:
```nix
  
{
  description = "A NixOS development flake for Bevy development.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mac-sdk = {
      url = "https://website.com/path/to/macos/sdk/MacOSX(Version).tar.xz";
      flake = false;
    };
  };
...
```

... or, download the tarball and reference it on your local system:

```nix
{
  inputs = {
    ...
    mac-sdk = {
      url = "file:///home/user/Downloads/MacOSX(Version).tar.xz";
                  # ^ Notice the extra forward-slash.
      flake = false;
    };
  };
  ...
}
```
