---
change: finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation
artifact: testing
---

# Testing

| Acceptance outcome | Evidence |
| --- | --- |
| Whole Swift package builds and tests on Linux | `swift build` and `swift test` in swift:6.0-noble and swift:6.3-noble (linux/aarch64) on the product tip; logs in docs/evidence/release-2.0.0/ |
| Portable suites and interchange on Linux | `cargo test --all-targets --locked`, `cargo test --doc --locked`, `bun run typecheck`, `bun run build`, `bun test`, and `swift run threemd-interchange` receipt in a combined container |
| CLI output unchanged on macOS | Existing CLI tests and `fledge run build`/`fledge run test` within the pinned Trust lane |
| Workflow edits are exact and permission-neutral | Diff review of publish.yml and cargo-publish.yml; actionlint-equivalent YAML parse; `git diff` shows no `permissions:` change |
| Documentation states the release honestly | Scoped review of the documentation diff against the observed logs |
| Repository gates | `specsync change check` (strict ThreeMD), pinned Trust 1.2.2 `fledge trust verify` on the exact tip, and hosted trust, UI and CodeQL on the PR |
