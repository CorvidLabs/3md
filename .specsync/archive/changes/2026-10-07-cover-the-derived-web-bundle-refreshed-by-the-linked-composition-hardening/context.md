---
change: cover-the-derived-web-bundle-refreshed-by-the-linked-composition-hardening
artifact: context
---

# Context

The element bundles `js/src`, so the linked composition hardening changed the derived `web/assets/three-md.js`, and the drift gate failed until it was regenerated. Commit 4a0f8de regenerated it with the drift gate's own `bun build` command and did not build `element/dist`. A read-only audit then found that this path was outside the hardening change's approved paths, so `specsync change audit` reported it as uncovered. This change records that derived update; it adds no behavior or canonical contract of its own. It is recorded after the regeneration, and that order is stated here rather than hidden.
