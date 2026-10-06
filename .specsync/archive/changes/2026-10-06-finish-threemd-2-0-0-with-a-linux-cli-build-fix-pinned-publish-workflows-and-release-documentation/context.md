---
change: finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation
artifact: context
---

# Context

On 2026-10-06 Leif directly instructed "Finish 2.0.0" and then chose, in chat with the executing agent (Claude): publish the release as soon as everything is green; run Linux checks in Docker and record Windows and unsigned provenance as known limits; release even if the crate publish fails and re-run it after the token is fixed; merge release-prep PRs with his admin bypass. He approved this change's scope as written. That is scope approval, not a review of this diff.

State at 87edafb: PR65/PR66 landed linked file composition and PR68 finalized its SpecSync change. Main CI (trust, UI, pages, CodeQL) is green. No v2.0.0 tag or release exists; v1.8.1 is the latest. Package manifests are already 2.0.0 (PR64).

Readiness checks on 9ac2454 found:
- Linux aarch64 (Docker): the ThreeMD and ThreeMDInterop targets build, Rust/TypeScript suites and the nine-pair interchange pass, but the ThreeMDCLI target does not compile: Glibc exposes `stderr` as shared mutable state, which Swift 6 strict concurrency rejects (Sources/CLI/main.swift). So `swift build`/`swift test` of the whole package fail on Linux.
- publish.yml runs `npm install -g npm@latest` on Node 20. npm@latest is now 12.2.0, whose engines exclude Node 20; v1.8.1 published with npm 11.
- cargo-publish.yml rewrote rust/Cargo.toml with sed to the tag version, which dirtied the tree, so `cargo publish` exited 101 for v1.7.17 through v1.8.1. crates.io still shows threemd 1.0.0. The CRATES_IO_TOKEN repository secret is also absent; only Leif can add it.
- Release docs still say "prepared and unreleased" and omit linked file composition.

Out of scope (coordinated with the Sculpt session, which owns a follow-up PR after the tag): per-reference path work bounds in the resolvers, extra shared limit/cancellation interchange cases, FileBundleHost platform guards and path-naming host errors. Library source, fixtures, package and format versions, Trust policy, permissions and branch protections stay unchanged.
