# Linked composition parity hardening verification

Change: `harden-linked-composition-parity-across-swift-typescript-and-rust-after-2-0-0`. Base: released main `ca2d1e34f20be3c5100d0fd1474a8ee9cc78d2d4` (`v2.0.0`). Implementation commits: `8469daa` and `5024b87`, with `4a0f8de` refreshing the derived web bundle and contract exports.

## Pinned Trust gate on macOS

At `4a0f8de` the pinned Trust 1.2.2 gate passed with Fledge 1.7.2 and SpecSync 6.0.0 in [trust-4a0f8de.log](trust-4a0f8de.log). The eight-step verify lane completed in 1 minute 6.9 seconds:

- 283 Swift tests.
- 174 TypeScript tests, with typecheck and package build.
- 67 Rust tests plus 3 doctests, with rustfmt and strict Clippy.
- The nine-pair interchange: 568 cases and 17,991 imports, 1,999 for each writer/reader pair.
- Bundle drift and editor grammar checks.

Strict SpecSync reports 3 specs with zero warnings, 48/48 files and 14,815/14,815 lines. Augur returned review at risk 35, below the block threshold. Provenance is reported degraded under the soft policy because the commit had no attestation when the gate ran.

The first gate attempt at `a8e9cda` failed honestly at the bundle drift step, because the element bundles `js/src`, and strict SpecSync reported the new interop source and the additive Rust export as undocumented. `4a0f8de` regenerated `web/assets/three-md.js` with the drift gate's own command, without building `element/dist`, and updated the contract.

## Linux

An earlier commit of this work, `e96f932`, ran on Linux arm64 in an Ubuntu 24.04 container, recorded in [linux-e96f932-with-pr69-cli.log](linux-e96f932-with-pr69-cli.log). A separate command in the same image reported Swift 6.3.3, Bun 1.4.2, Node 20.20.2 and Rust 1.95.0; those versions are not in the log itself. `e96f932` was built on the pre-release base `9ac2454`, which lacked the Linux CLI build fix, so that run applied PR69's `Sources/CLI/main.swift` in a scratch copy. It is on an unpublished local branch and predates the repairs in `5024b87`, so it is supporting evidence, not a run of the final tree. 274 Swift tests passed; the six Apple-only LZFSE tests do not compile on Linux. 170 TypeScript tests, 63 Rust tests plus 3 doctests and the interchange (558 cases, 17,991 imports) passed. The file-bundle host bundled the LinkedVillage example, and its open error named the missing folder.

A Linux run of the exact `4a0f8de` tree could not complete locally: Docker Desktop stopped responding after the disk filled. The new `linux` workflow is meant to run the same suites and interchange on GitHub's ubuntu runner. Its first run at `17d8159` failed before any suite because the Swift image lacks `curl`; the workflow now installs it, and only a passing run of that workflow counts as Linux evidence for the final tree. Windows and musl execution remain unverified.

## Review and measurements

Two adversarial read-only reviews by Claude workflows examined the implementation. The first confirmed per-reference work that still grew with the containing directory, Rust limit literals that were rounded twice, a Rust adoption code that differed at the exact attribute bound, a shared surrogate case that carried no escape and a cached-subtree case that still passed without its check. `5024b87` repairs each of them.

With a containing directory of 1 MiB and 16,356 references to one leaf, run through the debug adapters, Swift went from 56.25 s and 16,240 MB peak RSS to 1.76 s and 69 MB. Rust went from 13.92 s and 13,662 MB to 1.08 s and 38 MB, and TypeScript from 1.54 s to 0.34 s. Both versions end in `referenceAttributesExceeded`: a 1 MiB directory exceeds the standard 16,384-byte attribute bound, so the new code refuses at the first edge, and the after timing measures that early refusal rather than resolving every reference. In-bound Rust edges still copy one path string per edge, bounded by the attribute limit. These are single local measurements, not a performance guarantee.

These are agent reviews and finite tests, not exhaustive proof, a human review, a GitHub approval or a signature.
