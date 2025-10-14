# Details

## Who is this for?

This flake is for Nix users, who want to work with Bevy. Its goal is to be as
ergonomic for power user as for beginners. The flake provides suite of packages
useful for Bevy development, that all are configured from a single place.

It is for the developer who wants to use a Nix environment to compile portable
binaries for the major desktop platforms on their own computer, instead of
having to resort to using Docker, GitHub actions, or the like.

## What is the schema of `bevy-flake`?

```nix
{
  config = <config>;

  systems = [ <strings> ];
  eachSystem = <function>;

  devShells."<system>".default = <derivation>;
  packages."<system>" = {
    rust-toolchain = <derivation>;
    dioxus-cli = <derivation>;
    bevy-cli = <derivation>;
  };

  templates."<name>" = <templates>;

  override = <function>;
}
```

## What does `bevy-flake` do?

The flake wraps programs

## How does `bevy-flake` work?



## How do I extend `bevy-flake` to wrap one of my own packages?

