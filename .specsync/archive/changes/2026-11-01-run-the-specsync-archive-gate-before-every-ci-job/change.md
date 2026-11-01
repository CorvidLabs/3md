---
id: run-the-specsync-archive-gate-before-every-ci-job
state: archived
type: operations
base_commit: c19963be38ec9843b738c1dc335c53809bb99207
---

# Run the SpecSync archive gate before every CI job

## Intent

Run the SpecSync archive gate before every CI job

## Affected Canonical Specs

- None

## Acceptance Criteria

- Every pull_request and push workflow (linux, pages, sculpt, trust, ui) starts with a job named Archive that runs CorvidLabs/spec-sync pinned to 106aaa43d0bcf049f19b173ddb63815a25c3f931 with archive-gate-only true, and every other job in those workflows needs it, so no other job runs while any change under .specsync/changes/ is open.

## No-spec Rationale

CI workflow ordering only; no canonical spec owns .github/workflows
