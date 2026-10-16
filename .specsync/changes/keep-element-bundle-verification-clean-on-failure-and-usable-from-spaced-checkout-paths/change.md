---
id: keep-element-bundle-verification-clean-on-failure-and-usable-from-spaced-checkout-paths
state: draft
type: bug_fix
base_commit: c19963be38ec9843b738c1dc335c53809bb99207
---

# Keep element bundle verification clean on failure and usable from spaced checkout paths

## Intent

Keep element bundle verification clean on failure and usable from spaced checkout paths

## Affected Canonical Specs

- `ThreeMD`
- `ThreeMDElement`

## Acceptance Criteria

- Matching bundles pass; stale web/package bundles, storage leakage, oversized output and compiler errors fail without modifying bundles or leaving scratch directories; checkouts containing spaces work; all seven subprocess regressions and the actual bundle check run in the existing native lane.

## No-spec Rationale

Not applicable
