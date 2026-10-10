---
change: stabilize-viewer-canvas-resizing-and-webgl-context-recovery
artifact: testing
---

# Testing

Exercise Fit/16x, scroll and selected-cell painting/undo; rapid Slice/Cubes and phone/desktop transitions; assert bounded bitmap dimensions and no ResizeObserver errors. Force a genuine loss via WEBGL_lose_context, issue repeated redraws and resize/view changes, restore and assert one initialization, valid WebGL drawing, unchanged source/camera/slice. Keep existing camera/projection and mesh reuse regressions. Browser visual QA uses an isolated tab, preserving user drafts.

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-004 | REQ-ThreeMDViewer-004 | uitests/viewer.spec.mjs genuine loss/restoration, bounded high-zoom scrolled-cell edit/undo and existing drawable/camera/picking tests: all 234 passed. Actual source hashes, bitmap measurements, Trust and provenance limits are recorded in docs/evidence/viewer-context/README.md. |
