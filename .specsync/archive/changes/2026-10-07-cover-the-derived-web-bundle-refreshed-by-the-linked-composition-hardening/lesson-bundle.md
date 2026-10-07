# Lesson bundle — cover-the-derived-web-bundle-refreshed-by-the-linked-composition-hardening

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Cover the derived web bundle refreshed by the linked composition hardening
- **Kind**: Operations
- **Paths**: web/assets/three-md.js
- **Acceptance**: web/assets/three-md.js equals the drift gate's fresh build of element/src after the linked composition hardening; element/dist is not built or committed

## Evidence

- Verification commit: `1e22b5f6de388c070d3db3285e6a903be57ca14d`
- Base commit: `17d81597cc361ea885ea0e38112e3ec1e11e21f4`
- Verified by: `specsync check (no spec in scope)`

## From the change's context.md

# Context

The element bundles `js/src`, so the linked composition hardening changed the derived `web/assets/three-md.js`, and the drift gate failed until it was regenerated. Commit 4a0f8de regenerated it with the drift gate's own `bun build` command and did not build `element/dist`. A read-only audit then found that this path was outside the hardening change's approved paths, so `specsync change audit` reported it as uncovered. This change records that derived update; it adds no behavior or canonical contract of its own. It is recorded after the regeneration, and that order is stated here rather than hidden.

## From the change's testing.md

# Testing

Run `bun scripts/check-element-bundle.mjs` (through the pinned Trust lane) and `specsync change audit`. No product tests change.

## Where these lessons go

This change declared no affected specs, so there is no module context to fold into.
