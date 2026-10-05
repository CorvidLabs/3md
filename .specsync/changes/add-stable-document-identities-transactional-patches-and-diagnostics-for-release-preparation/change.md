---
id: add-stable-document-identities-transactional-patches-and-diagnostics-for-release-preparation
state: implementing
type: feature
base_commit: 0d345bb2ef7ec7cede572c24309761bec047301a
---

# Add stable document identities transactional patches and diagnostics for release preparation

## Intent

Add stable document identities transactional patches and diagnostics for release preparation

## Affected Canonical Specs

- `ThreeMD`

## Acceptance Criteria

- Optional stable plane IDs survive text and binary round trips without changing existing parsing or z links; immutable Sendable typed patches apply atomically with bounded operation counts and exact revision preconditions; duplicate IDs invalid coordinates missing targets stale revisions and cancellation return structured diagnostics with no partial document; release docs publish Swift-first capabilities migration examples and a compatibility matrix; the full pinned Trust lane and strict SpecSync pass with actual evidence; feature PRs remain open for Leif to merge and no release is published.

## No-spec Rationale

Not applicable
