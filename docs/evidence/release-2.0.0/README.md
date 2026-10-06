# ThreeMD 2.0.0 release verification

Verified commit: `d6eb66f23641e2f7fb7e7dc6ea6dd8e324bd17f6`, the last source change on the 2.0.0 release pull request (CLI Linux build fix and pinned publish workflows on top of main `87edafb`). Later commits on that branch change only documentation, these evidence files and SpecSync records. The repository merges by squash, so the `v2.0.0` tag is the squash merge of the pull request: a different commit with the same source.

## macOS, pinned Trust 1.2.2

`trust-d6eb66f.log` starts with a header naming the commit and tool versions and ends with the exit status: `fledge trust verify` with Trust 1.2.2 and the pinned Fledge 1.7.2 on PATH, exit 0 in 48 seconds. 268 Swift tests, 157 TypeScript tests with typecheck and package build, 49 Rust tests plus 3 doctests, strict Clippy, editor grammar and element bundle drift passed. The nine-pair interchange passed 479 cases and 17,451 imports, 1,939 per writer/reader pair. Augur returned proceed (risk 27). Provenance is reported as degraded under the soft policy; no permitted signature exists.

`trust-761f473-docs-tip.log` repeats the gate on documentation commit `761f473` (same source as `d6eb66f`): exit 0 in 44 seconds with the same counts and augur risk 33.

## CLI behaviour

`cli-parity/cases.sh` runs 39 CLI cases against a `threemd` binary: every subcommand with valid, missing, invalid and dangling-link inputs, the JSON variants, standard input, a missing file argument, closed standard error and a broken pipe with SIGPIPE ignored. It records stdout, stderr and the exit code of each case.

| Transcript | Binary | Result |
| --- | --- | --- |
| `cli-parity/macos-main-87edafb.txt` | main before this release change | Baseline |
| `cli-parity/macos-d6eb66f.txt` | verified commit | Byte-identical to the baseline |
| `cli-parity/macos-b1f5937-before-fix.txt` | an earlier commit on the branch that used `FileHandle.write(_:)` | Aborted with exit 134 whenever standard error could not be written; kept to show the check detects the regression |

The Linux Swift logs below also run the same cases on the verified commit; every closed-standard-error case exits 1.

## Linux aarch64, Docker

All runs used a fresh `git archive` copy of the verified commit (never a working tree) on Docker 29.8.1, `linux/aarch64`. Each log starts with the commit and image ID. The scripts are in `linux-scripts/`; `drive.sh` runs them with `cli-parity/cases.sh` and `cli-parity/fixtures/` mounted.

| Log | Image | Result |
| --- | --- | --- |
| `linux-swift-6.0.3.log` | `swift:6.0-noble` (Swift 6.0.3) | `swift build` exit 0; `swift test` 262 tests, 0 failures; CLI cases exit as expected |
| `linux-swift-6.3.3.log` | `swift:6.3-noble` (Swift 6.3.3) | `swift build` exit 0; `swift test` 262 tests, 0 failures; CLI cases exit as expected |
| `linux-rust.log` | `rust:1.95-bookworm` (rustc 1.95.0) | `cargo test --all-targets --locked` 49 passed; `cargo test --doc --locked` 3 passed |
| `linux-typescript.log` | `oven/bun:1.4` (bun 1.4.2) | `bun install --frozen-lockfile`, typecheck, build, `bun test` 157 passed |
| `linux-interchange.log`, `linux-interchange-receipt.json` | Local image from `linux-scripts/Dockerfile.interchange` (Swift 6.3.3, Node 20.20.2, bun 1.4.2, rustc 1.95.0) | `swift run threemd-interchange`: 479 cases, 17,451 imports, 1,939 for each of the nine pairs, passed |

Linux runs 262 Swift tests rather than 268 by design: the Apple Compression (LZFSE) tests compile only on Apple platforms, and the explicit unsupported-LZFSE test runs instead. LZFSE was not exercised on Linux. The interchange ran on Swift 6.3.3 only.

## Not covered

- x86_64 Linux: tried only under Rosetta emulation during readiness checks, with no retained log for this release.
- Windows was not executed.
- These are agent-run technical checks. They are not independent human review and not a signature.
