# Pitfalls

This page contains common issues people run into when using `bevy-flake`, and
their solutions. If you're having an issue that is not listed here, post in the
issues section of this repo [here.][issues]

[issues]: https://github.com/swagtop/bevy-flake/issues

_There are none so far with the new version._

## Performance Degredation after updating to NixOS 26.05

Update the bevy flake.
If possible, you may want to just start fresh from one of the templates.
Dependencies pulled in by older versions of the bevy flake do not work well with 26.05 (at least not in my case).
