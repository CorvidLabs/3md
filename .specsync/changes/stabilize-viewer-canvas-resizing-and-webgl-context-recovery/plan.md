---
change: stabilize-viewer-canvas-resizing-and-webgl-context-recovery
artifact: plan
---

# Plan

1. Coalesce observer drawing outside notification delivery and isolate canvas intrinsic size from layout.
2. Render a viewport-sized Slice bitmap over a virtual scroll surface, preserving coordinates and sharp glyphs.
3. Latch context loss, preserve application state and rebuild only after restoration.
4. Verify regressions and the repository gate, publish a feature PR, then import its tested commit in a site follow-up PR.
