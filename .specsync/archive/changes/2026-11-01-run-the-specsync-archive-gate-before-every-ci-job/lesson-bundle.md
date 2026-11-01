# Lesson bundle — run-the-specsync-archive-gate-before-every-ci-job

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Run the SpecSync archive gate before every CI job
- **Kind**: Operations
- **Paths**: .github/workflows/linux.yml, .github/workflows/pages.yml, .github/workflows/sculpt.yml, .github/workflows/trust.yml, .github/workflows/ui.yml
- **Acceptance**: Every pull_request and push workflow (linux, pages, sculpt, trust, ui) starts with a job named Archive that runs CorvidLabs/spec-sync pinned to 106aaa43d0bcf049f19b173ddb63815a25c3f931 with archive-gate-only true, and every other job in those workflows needs it, so no other job runs while any change under .specsync/changes/ is open.

## Evidence

- Verification commit: `b318917517fa4b616e64d933c9abd79d8596666f`
- Base commit: `c19963be38ec9843b738c1dc335c53809bb99207`
- Verified by: `specsync check (no spec in scope)`

## From the change's context.md

# Context

CorvidLabs is rolling out the SpecSync archive gate across the organization.
CorvidLabs/spec-sync#832 (merged as 106aaa43d0bcf049f19b173ddb63815a25c3f931)
added an `archive-gate-only` input to the spec-sync GitHub Action. With it set
to `'true'` the action runs only `.github/scripts/archive-readiness.sh`, which
needs bash and python3 and no binary download, and fails while any change under
`.specsync/changes/` is still open. 0xLeif approved the org-wide rollout. Branch
protection through an org ruleset that requires a check named Archive is
configured separately and is not part of this change.

Published releases v6.1.1 and older ignore the input, so the step pins the
merge commit. Move the pin to the first release that ships the gate.

At the base commit six earlier changes are open under `.specsync/changes/`.
They belong to other sessions and are not touched here. Until their owners
archive them, the Archive job on this pull request (and on every pull request)
stays red, which is the intended behavior of the gate.

The same recipe already landed on CorvidLabs/chough (pull request 18).

## From the change's design.md

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

## From the change's testing.md

# Testing

- Each edited workflow parses with Ruby Psych `safe_load`, and the printed job
  graph shows `archive-gate` with no needs and every other job needing it.
- `bash .github/scripts/archive-readiness.sh .` from CorvidLabs/spec-sync at the
  pinned commit lists the open changes and fails while any is open, and passes
  once all are archived.
- `specsync change audit --strict` no longer reports the workflow paths as
  uncovered.
- On the pull request, the Archive job runs first in each workflow and the
  other jobs are skipped while changes are open.

## Where these lessons go

This change declared no affected specs, so there is no module context to fold into.
