# Fledge integration

Fledge stays a development tool. The app does not link it, ship it, or ask a person to install it.

Use `/opt/homebrew/bin/fledge` 1.7.2. `~/.cargo/bin/fledge` reports a different version and is the wrong binary.

`fledge.toml` calls the Swift `RookTool` commands. Those commands refuse a `hi` or `specsync` binary that is not the pinned version. Public CI for this package is `.github/workflows/sculpt.yml`: Linux unit tests on the GitHub-hosted Swift 6.3.3 image. It does not use a self-hosted runner and it does not build the Mac app. The library Trust workflow stays the format gate.

The app does not load plugins, user scripts, or a hosted model. The sculpture editor does not link Fledge.
