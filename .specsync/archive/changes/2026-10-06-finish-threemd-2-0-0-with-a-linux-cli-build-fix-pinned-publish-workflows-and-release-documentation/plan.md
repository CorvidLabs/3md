---
change: finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation
artifact: plan
---

# Plan

1. Record the definition approval for this scope.
2. Apply the CLI fix and the two workflow edits; commit.
3. Run the Linux container suites (Swift 6.0.3 and 6.3.3 build and test, Rust, TypeScript, nine-pair interchange) and the pinned Trust 1.2.2 gate on that tip; keep the logs under docs/evidence/release-2.0.0/.
4. Update the release documentation with the observed numbers and regenerate docs.3md; commit.
5. `specsync change check --commit`, pinned Trust on the exact tip, push, open the PR and wait for CI.
6. Scoped review, then finalize on the same PR, then merge with Leif's bypass.
7. Tag v2.0.0 on the merge commit and publish the GitHub release; verify npm, crates.io and Homebrew outcomes.
