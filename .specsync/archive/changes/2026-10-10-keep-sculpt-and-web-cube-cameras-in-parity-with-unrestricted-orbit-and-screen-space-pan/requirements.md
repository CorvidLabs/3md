---
change: keep-sculpt-and-web-cube-cameras-in-parity-with-unrestricted-orbit-and-screen-space-pan
artifact: requirements
---

# Requirements

### REQ-ThreeMDViewer-006

The browser and Sculpt volume camera SHALL expose the same full-turn orbit, screen-space pan, bounded proportional zoom, default Fit pose and camera-correct nearest-cube picking, with matched camera basis and documented coordinate conversion.

Acceptance Criteria:

- Both the web cube viewer and Sculpt volume canvas orbit through complete horizontal and vertical turns, using the same continuous camera basis at the poles and upside down. Drag sensitivity is 0.008 radians per point; web yaw is the negative of native yaw to account for its coordinate convention.
- Both volume cameras support screen-space pan without changing the document, mesh, slice, paint history or geometry revision. Native Shift-left, middle and right dragging pan; an explicit Pan button works in Orbit. Native scroll zoom and trackpad magnification respond proportionally. Browser Pan, modified mouse dragging and two-finger pan/pinch provide the equivalent controls.
- Zoom stays between 0.5 and 2 in both views. Fit restores the default matched pose (native yaw -0.6 / web yaw 0.6, pitch 0.35), zoom 1 and zero pan. The native CPU cube/ASCII projection, live GPU camera and picking all honor the same orbit and pan.
- Shared asymmetric fixture receipts compare camera bases and screen projections across native and browser views, including pole crossings, upside-down and panned cameras. Picking chooses the nearest cube after those movements and camera changes reuse geometry. Mac native regressions and browser Chromium/WebKit regressions cover the controls.
- Keep native painting, stroke freezing, CPU/export budgets and the browser one-draw cube mesh, colors, axes and bounded grid behavior. Keep app and viewer specifications and human intent synchronized. Sparse-world Explore, storage formats, parser APIs, package releases and trust policies remain outside this camera change.
