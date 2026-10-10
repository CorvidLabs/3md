---
change: repair-blurry-cubes-and-slice-canvases-after-view-and-display-size-changes-while-retaining-the-webgl-context-and-camera
artifact: testing
---

# Testing

At device pixel ratios 1 and 2, initialize a phone-sized Cubes stage, switch through Slice's small reference and expand/resize to desktop and larger-than-cap layouts. Check actual drawable width/height against proportional 2048-edge/2x bounds, the same context/program/mesh, zero context-loss events and zero subsequent geometry uploads. Preserve source, selected slice, camera pose and nearest picking. Run existing projection, pixel, Slice and navigation regressions on Chromium and WebKit and inspect the actual in-app WebKit output. Root strict specs and pinned Trust must pass; actual unsigned agent:codex provenance remains separate from a permitted signature or human diff review.

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-004 | REQ-ThreeMDViewer-004 | New actual drawable-density and context-retention regression, existing GPU pixel/projection/picking tests, in-app browser before/after measurements and screenshot. |

## Current results

The complete post-resize UI suite passed 230 tests. After final display-density listeners, the viewer suite passed 130 tests. The final media-query/window-resize density regressions passed 4 tests. All ran on Chromium and WebKit without skips or retries. Actual in-app bitmap/display measurements and screenshots, test logs and implementation digests are in `docs/evidence/viewer-resolution/`. Pinned Trust, actual provenance and finalization remain separately evidenced.
