# `hot-reload`

This version of `bevy-flake` provides a wrapper of the `0.7.0-alpha.1` version
of `dioxus`.

This lets one use hot-reloading for bevy, by running the `hot` command in
the terminal. Right now that means you'll have to build it locally. When this
version of `dioxus` comes out, and makes its way into `nixpkgs`, I'll get rid of
this alternate, and have its funcitonality included in the main flake.

Remember to use the `bevy_simple_subsecond_system` crate in your project to get
hot-reloading, if using a pre-0.17 Bevy version.

Was last tested on Bevy version: `16.1`
