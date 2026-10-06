# ThreeMD 2.0.0 release verification

Product commit: `b1f5937` (CLI Linux build fix and pinned publish workflows on top of main `87edafb`). Later commits on the release branch change only documentation, these evidence files and SpecSync records.

## macOS, pinned Trust 1.2.2

`trust-b1f5937.log`: `fledge trust verify` with Trust 1.2.2 and the pinned Fledge 1.7.2 on PATH, exit 0 in 59 seconds. 268 Swift tests, 157 TypeScript tests with typecheck and package build, 49 Rust tests plus 3 doctests, strict Clippy, editor grammar and element bundle drift passed. The nine-pair interchange passed 479 cases and 17,451 imports, 1,939 per writer/reader pair. Augur returned proceed (risk 27). Provenance is reported as degraded under the soft policy; no permitted signature exists.

## Linux aarch64, Docker

All runs used an exact `git archive b1f5937` copy (never the working tree) on Docker 29.8.1, `linux/aarch64`, kernel 7.0.14-linuxkit. The scripts are in `linux-scripts/`; `drive.sh` runs them.

| Log | Image | Result |
| --- | --- | --- |
| `linux-swift-6.0.3.log` | `swift:6.0-noble` (Swift 6.0.3) | `swift build` exit 0; `swift test` 262 tests, 0 failures |
| `linux-swift-6.3.3.log` | `swift:6.3-noble` (Swift 6.3.3) | `swift build` exit 0; `swift test` 262 tests, 0 failures |
| `linux-rust.log` | `rust:1.95-bookworm` (rustc 1.95.0) | `cargo test --all-targets --locked` 49 passed; `cargo test --doc --locked` 3 passed |
| `linux-typescript.log` | `oven/bun:1.4` (bun 1.4.2) | `bun install --frozen-lockfile`, typecheck, build, `bun test` 157 passed |
| `linux-interchange.log`, `linux-interchange-receipt.json` | Local image from `linux-scripts/Dockerfile.interchange` (Swift 6.3.3, Node 20.20.2, bun 1.4.2, rustc 1.95.0) | `swift run threemd-interchange`: 479 cases, 17,451 imports, 1,939 for each of the nine pairs, passed |

Linux runs 262 Swift tests rather than 268 by design: the Apple Compression (LZFSE) tests compile only on Apple platforms, and the explicit unsupported-LZFSE test runs instead. LZFSE was not exercised on Linux.

## Not covered

- x86_64 Linux was exercised only during readiness checks on `9ac2454` with the same CLI change applied, under Rosetta emulation; not on native hardware or CI, and not on this exact commit.
- Windows was not executed.
- These are agent-run technical checks. They are not independent human review and not a signature.
