---
change: run-the-specsync-archive-gate-before-every-ci-job
artifact: design
---

# Design

Each workflow that runs on `pull_request` or `push` (linux, pages, sculpt,
trust, ui) gets a first job with id `archive-gate` and display name `Archive`.
It runs on `ubuntu-latest` with a five minute timeout, checks out the pull
request head (or `github.sha` on push) without persisted credentials using the
same `actions/checkout@v4` the workflow already uses, and runs
`CorvidLabs/spec-sync@106aaa43d0bcf049f19b173ddb63815a25c3f931` with
`archive-gate-only: 'true'`.

Every existing job in those workflows had no `needs`, so each gets
`needs: archive-gate`. When the gate fails, GitHub skips the dependent jobs.
A skipped job counts as passing for required checks, so merge blocking relies
on the org ruleset requiring the Archive check itself.

The release and dispatch only workflows (cargo-publish, post-release-formula,
publish) do not run on pull requests or pushes and are left unchanged.
Everything else in the edited files is preserved byte for byte.
