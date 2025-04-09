# `no-zigbuild`

This version of `bevy-flake` uses no `cargo-zigbuild`. Everything is handled
manually with `RUSTFLAGS`.

An issue here however is that the flags commented out for removing your home
directory do not work properly, and as such information about your system will
always be found in the strings of the final binary.

The MacOS SDK should be version 11.0 or later, as before they don't include a
json file used by this flake. If you still want to use an earlier version, you
will have to manually insert the minimum and current version of the SDK in the
MacOS target section of the cargo-wrapper.

Was last tested on Bevy version: `15.3`
