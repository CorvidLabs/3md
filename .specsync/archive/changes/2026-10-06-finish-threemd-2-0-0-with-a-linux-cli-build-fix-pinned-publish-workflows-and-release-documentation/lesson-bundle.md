# Lesson bundle — finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Finish ThreeMD 2.0.0 with a Linux CLI build fix, pinned publish workflows and release documentation
- **Kind**: Operations
- **Specs**: ThreeMDCLI, ThreeMD, ThreeMDElement
- **Paths**: Sources/CLI/main.swift, .github/workflows/publish.yml, .github/workflows/cargo-publish.yml, CHANGELOG.md, docs/RELEASE-2.0.0.md, README.md, SPEC.md, docs/FILE-COMPOSITION.md, docs/EDITING-RELEASE.md, ROADMAP.md, AGENTS.md, js/README.md, element/README.md, editor/vscode/README.md, conformance/interchange/README.md, Examples/LinkedVillage/README.md, docs.3md, web/docs.3md, docs/evidence/release-2.0.0/
- **Acceptance**: The full Swift package (including the threemd CLI) builds and its tests pass on Linux aarch64 in official Swift 6.0 and 6.3 containers at the release tip, with Rust, TypeScript and the nine-pair interchange also passing there and logs retained under docs/evidence/release-2.0.0/; CLI output is unchanged on macOS. publish.yml upgrades npm with npm@^11.5.1 instead of npm@latest, and cargo-publish.yml checks that the committed crate version equals the release tag instead of rewriting it, uses CARGO_REGISTRY_TOKEN, fails clearly when the secret is missing and refuses non-tag dispatch, with no permission changes. CHANGELOG, the release guide, README, SPEC and FILE-COMPOSITION status, EDITING-RELEASE, ROADMAP, package READMEs, the interchange README and the LinkedVillage README describe 2.0.0 as released on 2026-10-06, include linked file composition, cite the exact-tip verification and keep explicit limits (unverified Windows, emulated-only x86_64 Linux, soft unsigned provenance, Swift/Apple-only LZFSE, text-only element and VS Code, separate Sculpt adoption, follow-up parity hardening). AGENTS.md records the Finish 2.0.0 authority outside the managed block. Strict SpecSync and the pinned Trust 1.2.2 gate pass on the exact tip, and no human review or signature is claimed.

## Evidence

- Verification commit: `2233452155c7056a84a49f70699ac7c375dfd025`
- Base commit: `87edafb2f47b4d73e47441ae754ad955b6d49f44`
- Verified by: `specsync check --spec ThreeMD --spec ThreeMDCLI --spec ThreeMDElement`

## From the change's context.md

# Context

On 2026-10-06 Leif directly instructed "Finish 2.0.0" and then chose, in chat with the executing agent (Claude): publish the release as soon as everything is green; run Linux checks in Docker and record Windows and unsigned provenance as known limits; release even if the crate publish fails and re-run it after the token is fixed; merge release-prep PRs with his admin bypass. He approved this change's scope as written. That is scope approval, not a review of this diff.

State at 87edafb: PR65/PR66 landed linked file composition and PR68 finalized its SpecSync change. Main CI (trust, UI, pages, CodeQL) is green. No v2.0.0 tag or release exists; v1.8.1 is the latest. Package manifests are already 2.0.0 (PR64).

Readiness checks on 9ac2454 found:
- Linux aarch64 (Docker): the ThreeMD and ThreeMDInterop targets build, Rust/TypeScript suites and the nine-pair interchange pass, but the ThreeMDCLI target does not compile: Glibc exposes `stderr` as shared mutable state, which Swift 6 strict concurrency rejects (Sources/CLI/main.swift). So `swift build`/`swift test` of the whole package fail on Linux.
- publish.yml runs `npm install -g npm@latest` on Node 20. npm@latest is now 12.2.0, whose engines exclude Node 20; v1.8.1 published with npm 11.
- cargo-publish.yml rewrote rust/Cargo.toml with sed to the tag version, which dirtied the tree, so `cargo publish` exited 101 for v1.7.17 through v1.8.1. crates.io still shows threemd 1.0.0. The CRATES_IO_TOKEN repository secret is also absent; only Leif can add it.
- Release docs still say "prepared and unreleased" and omit linked file composition.

Out of scope (coordinated with the Sculpt session, which owns a follow-up PR after the tag): per-reference path work bounds in the resolvers, extra shared limit/cancellation interchange cases, FileBundleHost platform guards and path-naming host errors. Library source, fixtures, package and format versions, Trust policy, permissions and branch protections stay unchanged.

## From the change's design.md

# Design

- CLI: add a private `writeStandardError(_:)` helper in Sources/CLI/main.swift and replace each `fputs(<message>, stderr)` with it. The helper writes the UTF-8 bytes to `FileHandle.standardError`'s file descriptor with POSIX `write`, retrying partial writes and ignoring failures exactly as `fputs` did. `FileHandle.write(_:)` was rejected after review: it aborts (macOS) or traps (Linux) when standard error is closed or its reader is gone, which would turn exit 1 into a crash. Messages, ordering and exit codes are unchanged; only the write path changes.
- publish.yml: both "Upgrade npm for OIDC trusted publishing" steps install `npm@^11.5.1`; the stale element install comment is corrected. Permissions, triggers and publish commands are unchanged.
- cargo-publish.yml: replace the sed rewrite with a step that resolves the tag from the release event (or the dispatched ref), refuses anything that is not a vX.Y.Z tag, and fails unless `cargo metadata --locked` reports the same threemd version. Publish with `cargo publish --locked` using CARGO_REGISTRY_TOKEN from the existing CRATES_IO_TOKEN secret, failing with a clear error when it is empty. Permissions stay `contents: read`. Values from the event flow through `env:`.
- Documentation: status and evidence wording only, plus the LinkedVillage example's bundle command output path (macOS /tmp is a symlink that the host deliberately refuses). docs.3md and web/docs.3md are regenerated with scripts/build-docs-3md.mjs.
- Evidence: Linux container logs and the pinned Trust log for the product tip are committed under docs/evidence/release-2.0.0/ with image tags and tool versions.

## From the change's testing.md

# Testing

| Acceptance outcome | Evidence |
| --- | --- |
| Whole Swift package builds and tests on Linux | `swift build` and `swift test` in swift:6.0-noble and swift:6.3-noble (linux/aarch64) on an exact archive of `d6eb66f`: docs/evidence/release-2.0.0/linux-swift-*.log |
| Portable suites and interchange on Linux | `cargo test --all-targets --locked`, `cargo test --doc --locked`, `bun run typecheck`, `bun run build`, `bun test`, and the `swift run threemd-interchange` receipt: docs/evidence/release-2.0.0/linux-*.log and linux-interchange-receipt.json |
| CLI output unchanged | docs/evidence/release-2.0.0/cli-parity/cases.sh runs 39 cases (all subcommands, valid/missing/invalid/dangling inputs, JSON variants, stdin, closed standard error, broken pipe). The macOS transcripts for main `87edafb` and `d6eb66f` are byte-identical; the Linux Swift logs run the same cases. The repository has no CLI executable tests, so this transcript comparison is the evidence. |
| Workflow edits are exact and permission-neutral | Diff review of publish.yml and cargo-publish.yml; YAML parse; no `permissions:` line changes; the cargo tag/version check simulated locally for `v2.0.0` and a branch ref; `cargo publish --dry-run --locked` on a clean clone during review |
| Documentation states the release honestly | Scoped review of the documentation diff against the committed evidence |
| Repository gates | `specsync change check` (strict ThreeMD), pinned Trust 1.2.2 `fledge trust verify` on `d6eb66f` and on the delivery tip, and hosted trust, UI and CodeQL on the pull request |

## Where these lessons go

- `specs/ThreeMDCLI/context.md`
- `specs/ThreeMD/context.md`
- `specs/ThreeMDElement/context.md`
