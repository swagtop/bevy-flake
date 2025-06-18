# `aarch64-compatible`

This version of `bevy-flake` allows the user to enter the devshell on both
`x86_64-linux` and `aarch64-linux`.

I want this to make its way into the main version, but I think it looks a little
ugly and unintuitive. I want it to be easy to figure out how the flake works by
a glance, and I feel this does not achieve that quite yet.

I have tested the compilation of the same project to the same target from both
`aarch64-linux` and `x86_64-linux`, and can get binaries of the exact same size,
but with different internal structure, and therefore different hashes. I'm not
sure if we can achieve truly pure and preproducible platform-agnostic builds
from this setup, but we sure can get close.

Was last tested on Bevy version: `16.1`
