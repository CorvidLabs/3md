---
spec: ThreeMDCLI.spec.md
---

# ThreeMDCLI Tasks

This document tracks the tasks and implementation progress of the command line interface tool.

## Done

- [x] Command-line entry point defined in `Sources/CLI/main.swift` and wired as `threemd` executable in `Package.swift`.
- [x] Implemented `validate` subcommand to parse files and report syntax status.
- [x] Implemented `info` subcommand to display structured plane and axis metadata.
- [x] Implemented `html` subcommand to render documents to stdout via HTMLRenderer.
- [x] Implemented `links` subcommand to list all document cross-plane references.
- [x] Implemented `check-links` subcommand to validate links and exit non-zero on dangling references.
- [x] Integrated `--json` flag support across subcommands for machine-readable output.
- [x] Verified build correctness under Swift 6 strict concurrency.

## Next

- [ ] Read every subcommand's input as bytes and decode binary input (payload kind 1 or 2) with `DocumentStorageCodec.decode`, keeping the text path byte-identical.
- [ ] Add the storage branch to `ErrorOutput` (`code`, `message`, `detail`, `line`) and the `threemd: <path>: <code>: <description>` stderr line.
- [ ] Add `convert` with format inference, usage exits, `--lzfse`, `--force` and the atomic write.
- [ ] Add `inspect` with plain output and the three JSON shapes.
- [ ] Update the usage text and the README CLI section.
- [ ] Add CLI integration tests in `Tests/ThreeMDTests/CLITests.swift` that run the built `threemd` binary with `Process` on macOS and Linux.
- [ ] Add bash/zsh autocomplete templates for the CLI subcommands.
