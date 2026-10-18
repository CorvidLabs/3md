---
change: stabilize-viewer-canvas-resizing-and-webgl-context-recovery
artifact: plan
---

# Plan

1. Coalesce observer drawing outside notification delivery and isolate canvas intrinsic size from layout.
2. Render a viewport-sized Slice bitmap over a virtual scroll surface, preserving coordinates and sharp glyphs.
3. Latch context loss, preserve application state and rebuild only after restoration.
4. Verify regressions and the repository gate, publish a feature PR, then import its tested commit in a site follow-up PR.

5. Repair the startup failure/event gap and partial-resource initialization under the existing loss-suspension contract; verify actual Safari and import the tested follow-up in the site.

6. Reproduce the main Linux Slice gesture failures, synchronize helpers with deferred drawing and the virtual grid, verify repeated and full Linux/macOS suites, and publish a feature CI repair without another site import.

## Approach

Confine repair to browser drawables and scheduling: defer observer drawing, bound the Slice bitmap to the viewport, and latch context loss until restoration.

## Out of scope

Native camera mathematics, editing semantics, parser/storage and trust policies remain unchanged, as stated in context.md.

## Steps

Follow the six existing steps above. Retain exact edit/Undo assertions and runtime bytes while synchronizing gesture-test readiness with deferred drawing and the virtual grid.

## Risks

As recorded in context.md, null/already-lost contexts before event delivery and resource creation without null guards can break startup. Stale or empty rendered metadata can misdirect synthetic gestures; testing.md records the readiness checks and evidence limits.

## Constraints consulted

This normalization uses the existing plan.md, context.md and testing.md. It preserves the existing loss-suspension/restoration contract and adds no camera, loader, format or trust-policy scope, test result or review claim.
