---
change: limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows
artifact: research
---

# Research

CodeQL rule `actions/missing-workflow-permissions` (CWE-275) requires an explicit `permissions` key on the workflow or on each job. The alert text names `contents: read` as the minimal starting point. Job-level permissions satisfy the query, which is why `publish.yml` was not flagged.

Token use in the three workflows:

- All three check out the repository. `actions/checkout` needs `contents: read`.
- `cargo-publish.yml` publishes with the `CRATES_IO_TOKEN` secret. It does not push or create a GitHub release.
- `trust.yml` downloads public CorvidLabs release assets and runs local gates. Nested augur and attest actions pass `github.token` to `gh release download` for public repositories. The pinned Trust action does not post pull-request comments. Atlas publication is off in `.trust.toml`.
- `ui.yml` uploads a Playwright report only after failure. `actions/upload-artifact@v4` authenticates with the Actions runtime token, so `actions: write` is not required.

Hosted evidence on `fb70a0c` already passed: CodeQL Analyze (actions), the trust workflow, and the UI lab. That run is the check that `contents: read` is sufficient for trust and the UI job.

`specsync change adopt` writes `.specsync/workflow-v2-baseline.json` with cutoff `8712c68` and refreshes `.specsync/adoption-report.json`. The requirement-id suggestions in that report were already satisfied by `REQ-threemd-*`, `REQ-threemdcli-*`, and `REQ-threemdelement-*`.
