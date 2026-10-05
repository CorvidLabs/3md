---
change: limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows
artifact: plan
---

# Plan

1. Add workflow-level `contents: read` to `ui.yml`, `trust.yml`, and `cargo-publish.yml`.
2. Leave `pages.yml`, `publish.yml`, and `post-release-formula.yml` on their existing permissions.
3. Adopt the SpecSync 6 workflow-v2 baseline at `8712c68` without rewriting accepted workflow-v1 changes.
4. Approve this definition, run `change check`, record the scoped review, and `change finalize` on PR 57 before merge.
