---
change: limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows
artifact: context
---

# Context

CodeQL alerts 7, 8, and 9 on main reported `actions/missing-workflow-permissions` for `cargo-publish.yml`, `trust.yml`, and `ui.yml`. Those three workflows had no `permissions` key, so the job token inherited the repository default.

The other workflows already declare permissions. `pages.yml` and `post-release-formula.yml` do it at workflow scope. `publish.yml` does it per job because npm provenance needs `id-token: write`.

This change limits the three flagged workflows to `contents: read`. It does not change parser behavior or canonical specs. crates.io still uses `CRATES_IO_TOKEN`. SpecSync PR comments stay off. `upload-artifact@v4` uses the Actions runtime token.

The workflow edit is commit `fb70a0c` on PR 57. The repository was still on the SpecSync 5.0.1 change workflow, so this record also adopts the workflow-v2 baseline at cutoff `8712c68`. Existing accepted changes stay workflow v1. This change is workflow v2 and finalizes on the delivery PR.
