---
change: finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation
artifact: testing
---

# Testing

| Acceptance outcome | Evidence |
| --- | --- |
| Whole Swift package builds and tests on Linux | `swift build` and `swift test` in swift:6.0-noble and swift:6.3-noble (linux/aarch64) on an exact archive of `d6eb66f`: docs/evidence/release-2.0.0/linux-swift-*.log |
| Portable suites and interchange on Linux | `cargo test --all-targets --locked`, `cargo test --doc --locked`, `bun run typecheck`, `bun run build`, `bun test`, and the `swift run threemd-interchange` receipt: docs/evidence/release-2.0.0/linux-*.log and linux-interchange-receipt.json |
| CLI output unchanged | docs/evidence/release-2.0.0/cli-parity/cases.sh runs 39 cases (all subcommands, valid/missing/invalid/dangling inputs, JSON variants, stdin, closed standard error, broken pipe). The macOS transcripts for main `87edafb` and `d6eb66f` are byte-identical; the Linux Swift logs run the same cases. The repository has no CLI executable tests, so this transcript comparison is the evidence. |
| Workflow edits are exact and permission-neutral | Diff review of publish.yml and cargo-publish.yml; YAML parse; no `permissions:` line changes; the cargo tag/version check simulated locally for `v2.0.0` and a branch ref; `cargo publish --dry-run --locked` on a clean clone during review |
| Documentation states the release honestly | Scoped review of the documentation diff against the committed evidence |
| Repository gates | `specsync change check` (strict ThreeMD), pinned Trust 1.2.2 `fledge trust verify` on `d6eb66f` and on the delivery tip, and hosted trust, UI and CodeQL on the pull request |
