# Alternate version: `no-zigbuild`

This version of `bevy-flake` uses no `cargo-zigbuild`. Everything is handled
manually with `RUSTFLAGS`.

An issue here however is that the flags commented out for removing your home
directory do not work properly, and as such information about your system will
always be found in the strings of the final binary.

Was last tested on Bevy version: `15.3`
