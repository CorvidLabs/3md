# Fledge integration

Fledge stays a development tool. The app does not link it, ship it, or ask a person to install it.

Use `/opt/homebrew/bin/fledge` 1.7.2. `~/.cargo/bin/fledge` reports a different version and is the wrong binary.

`fledge.toml` calls the Swift `RookTool` commands. Those commands refuse a `hi` or `specsync` binary that is not the pinned version. `.github/workflows/ci.yml` runs `lanes run verify` with Homebrew `hi` 0.8.0 and Homebrew `specsync` 6.0.0 for pushes to main. Pull requests run the Trust gate in `.github/workflows/trust.yml`, whose lifecycle step is the same lane, so only one lane runs per pull request on the shared self-hosted Mac. This note does not say a runner has accepted a job.

The app does not load plugins, user scripts, or a hosted model. The sculpture editor does not link Fledge.
