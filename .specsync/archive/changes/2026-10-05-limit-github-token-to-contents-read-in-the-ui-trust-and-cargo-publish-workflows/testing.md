---
change: limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows
artifact: testing
---

# Testing

- `fledge lanes run verify` passed locally on `fb70a0c` (Swift lint, build, tests, TypeScript, Rust, element bundle, editor grammar).
- `cd js && bun run typecheck` passed.
- Augur on the staged workflow diff returned proceed, risk 29.7.
- PR 57 on `fb70a0c`: CodeQL Analyze (actions), Analyze (javascript-typescript), Analyze (rust), Analyze (swift), CodeQL, Interactive lab, and trust all passed.
- `cargo-publish.yml` does not run on pull requests. Its contract is the declared `contents: read` block plus checkout and `CRATES_IO_TOKEN` at release time.
- Canonical spec behavior is unchanged. `specsync check` remains the contract check because no spec is in scope.
- `specsync change status` must report workflow v2 for this change, and `change finalize` must archive it on PR 57 before merge.
