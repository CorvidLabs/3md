---
change: limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows
artifact: tasks
---

# Tasks

- [x] Declare `permissions: contents: read` on `ui.yml`, `trust.yml`, and `cargo-publish.yml`.
- [x] Keep parser sources, canonical specs, and the other workflows unchanged.
- [x] Confirm CodeQL Analyze (actions), trust, and the UI lab passed on `fb70a0c`.
- [x] Adopt the workflow-v2 baseline at cutoff `8712c68`.
