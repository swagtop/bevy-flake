# `aarch64-compatible`

This version of `bevy-flake` allows the user to enter the devshell on both
`x86_64-linux` and `aarch64-linux`.

I want this to make its way into the main version, but I think it looks a little
ugly and unintuitive. I want it to be easy to figure out how the flake works by
a glance, and I feel this does not achieve that quite yet.

There seems to be an issue with compiling to `x86_64-pc-windows-msvc` from
the `aarch64-linux` shell. I'm trying to work this out, and haven't tested all
targets yet. This is more of a proof of concept for now.
