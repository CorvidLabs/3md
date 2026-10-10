---
change: stabilize-viewer-canvas-resizing-and-webgl-context-recovery
artifact: testing
---

# Testing

Exercise Fit/16x, scroll and selected-cell painting/undo; rapid Slice/Cubes and phone/desktop transitions; assert bounded bitmap dimensions and no ResizeObserver errors. Force a genuine loss via WEBGL_lose_context, issue repeated redraws and resize/view changes, restore and assert one initialization, valid WebGL drawing, unchanged source/camera/slice. Keep existing camera/projection and mesh reuse regressions. Browser visual QA uses an isolated tab, preserving user drafts.

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-004 | REQ-ThreeMDViewer-004 | uitests/viewer.spec.mjs genuine loss/restoration, bounded high-zoom scrolled-cell edit/undo and existing drawable/camera/picking tests: initially 234 passed; expanded complete suite 242 passed with no skips or retries. Actual source hashes, bitmap measurements, Trust and provenance limits are recorded in docs/evidence/viewer-context/README.md. |

## Expanded viewer coverage

The viewer suite now visits all 293 text examples across 48 axes through Cubes, Slice and Preview, opens all four binary samples through file input, retains embedded entries, and verifies four linked local-folder drafts. Desktop and phone boundary cases cover empty/single cells, 64-cell skinny grids, 4000/4096 occupied cells, 64/65 grid edges, 256/257 planes and the 1.5 MiB source limit. Unsupported Slice grids explain their refusal while preserving source and Preview. Details and actual live GitHub-folder/binary observations are in `docs/evidence/viewer-context/README.md`.

Safari follow-up: reproduce null/already-lost startup contexts before loss-event delivery, 256 redraws, safe null resource creation, and genuine early loss/restoration. Verify actual Safari alongside Playwright; record the independent native observations and the unresolved hardware cause honestly.

2026-10-10 Safari follow-up verification: complete Chromium/WebKit suite 256 passed without retries or skips (2 workers, 2.8 minutes), followed by the additional genuine early-loss test passing in both engines (2 checks). Native Safari 26.5.2 independently held at one context request while lost, retained Slice erase/Undo, and rebuilt exactly once after restoration. See docs/evidence/viewer-context/README.md for the proof boundaries.
