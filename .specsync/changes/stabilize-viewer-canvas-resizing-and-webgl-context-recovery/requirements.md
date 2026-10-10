---
change: stabilize-viewer-canvas-resizing-and-webgl-context-recovery
artifact: requirements
---

# Requirements

REQ-ThreeMDViewer-004: The viewer SHALL defer/coalesce resize drawing, bound Slice bitmap allocation to the visible area, and pause GPU allocation/drawing during WebGL loss until the restoration event.

Acceptance criteria: browser resize/zoom/view-switch regressions report no observer loops; scrolled high-zoom cells paint and undo exactly; repeated draws during loss do not reacquire or resize the context; restoration rebuilds once and preserves source, pose and selected slice.
