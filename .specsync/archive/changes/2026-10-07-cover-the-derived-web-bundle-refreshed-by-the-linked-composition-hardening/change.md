---
id: cover-the-derived-web-bundle-refreshed-by-the-linked-composition-hardening
state: archived
type: operations
base_commit: 17d81597cc361ea885ea0e38112e3ec1e11e21f4
---

# Cover the derived web bundle refreshed by the linked composition hardening

## Intent

Cover the derived web bundle refreshed by the linked composition hardening

## Affected Canonical Specs

- None

## Acceptance Criteria

- web/assets/three-md.js equals the drift gate's fresh build of element/src after the linked composition hardening; element/dist is not built or committed

## No-spec Rationale

web/assets/three-md.js is a derived bundle of element/src and js/src; the drift gate requires it to match the hardened TypeScript sources, and no canonical contract changes
