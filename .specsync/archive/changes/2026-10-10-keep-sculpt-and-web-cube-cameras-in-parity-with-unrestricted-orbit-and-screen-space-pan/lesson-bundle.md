# Lesson bundle — keep-sculpt-and-web-cube-cameras-in-parity-with-unrestricted-orbit-and-screen-space-pan

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Keep Sculpt and web cube cameras in parity with unrestricted orbit and screen-space pan
- **Kind**: Feature
- **Specs**: ThreeMDViewer
- **Paths**: ["web/viewer.html", "uitests/viewer.spec.mjs", "hi/tools.md", "specs/ThreeMDViewer", "apps/sculpt/Sources/RookSculpture/SculptureProjection.swift", "apps/sculpt/Sources/RookRendering/SculptureVoxelGeometry.swift", "apps/sculpt/Sources/RookRendering/SculptureLiveVoxelView.swift", "apps/sculpt/Sources/RookApp/SculptureCanvasPointer.swift", "apps/sculpt/Sources/RookApp/SculptureViewport.swift", "apps/sculpt/Sources/RookApp/SculptureEditor.swift", "apps/sculpt/Tests", "apps/sculpt/specs", "apps/sculpt/hi", "docs/evidence/viewer-camera"]
- **Acceptance**: Both the web cube viewer and Sculpt volume canvas orbit through complete horizontal and vertical turns, using the same continuous camera basis at the poles and upside down. Drag sensitivity is 0.008 radians per point; web yaw is the negative of native yaw to account for its coordinate convention.
- **Acceptance**: Both volume cameras support screen-space pan without changing the document, mesh, slice, paint history or geometry revision. Native Shift-left, middle and right dragging pan; an explicit Pan button works in Orbit. Native scroll zoom and trackpad magnification respond proportionally. Browser Pan, modified mouse dragging and two-finger pan/pinch provide the equivalent controls.
- **Acceptance**: Zoom stays between 0.5 and 2 in both views. Fit restores the default matched pose (native yaw -0.6 / web yaw 0.6, pitch 0.35), zoom 1 and zero pan. The native CPU cube/ASCII projection, live GPU camera and picking all honor the same orbit and pan.
- **Acceptance**: Shared asymmetric fixture receipts compare camera bases and screen projections across native and browser views, including pole crossings, upside-down and panned cameras. Picking chooses the nearest cube after those movements and camera changes reuse geometry. Mac native regressions and browser Chromium/WebKit regressions cover the controls.
- **Acceptance**: Keep native painting, stroke freezing, CPU/export budgets and the browser one-draw cube mesh, colors, axes and bounded grid behavior. Keep app and viewer specifications and human intent synchronized. Sparse-world Explore, storage formats, parser APIs, package releases and trust policies remain outside this camera change.

## Evidence

- Verification commit: `2cb08248efb492b03de8a2bb300b00383f732945`
- Base commit: `fefd8316adfff3af8bdb87d26b4a417650540b56`
- Verified by: `specsync check --spec ThreeMDViewer`

## From the change's context.md

# Context

Leif requested full 360-degree rotation and easier movement, then explicitly requested parity with Rook / Sculpt.3md. The viewer camera preview is prepared locally. Native source still has a vertical clamp and lacks volume pan. This draft extends the earlier viewer-only scope to the native volume camera. Human definition approval, native implementation, verification and closure remain pending.

Actor: agent:codex. No independent human diff review or signed provenance is claimed.

Current implementation and shared fixture receipts are in `docs/evidence/viewer-camera/`. Live pan and Fit preserved the native scene and slice. Default utility-camera framing preserves historical example images. Final full suites, Trust and lifecycle closure remain pending; the separate gizmo definition is not approved.

## From the change's design.md

# Design

Keep the current stage colors, glyph fills, edges and selected-slice gold. Orbit and Pan are camera tools in the existing control strip. Browser controls stay below the drawing and keep phone touch targets usable. Native Shift, middle and right dragging provide pan even while Paint is selected; such gestures must never paint. A native Pan toggle applies to the Orbit canvas. Use native local points and browser CSS pixels. Both cameras use 0.008 radians per drag point, zoom 0.5 through 2, and default pitch 0.35. Native yaw -0.6 maps to browser yaw +0.6. Native ASCII and exports follow the same session camera.

## From the change's testing.md

# Testing

Browser regressions cover complete turns and finite matrices through both poles, screen-space pan with unchanged yaw/pitch/source/slice, mouse-button/modifier controls, proportional wheel input, touch pinch/pan and cancellation, translated nearest-cube picking, Fit, bounded zoom, no camera geometry upload, and 320-pixel phone layout. Native regressions cover finite sanitized camera inputs, scalar/prepared/live projection agreement across matching full-turn/panned cases, geometry reuse and native pointer forwarding. Retain actual verification receipts; no current camera suite result or final Trust verdict is claimed yet.

Current camera implementation: Mac Chromium/WebKit viewer 106 passed; Linux projection/phone selection 4 passed; native camera/input and unchanged math preview selection 23 passed in four suites. Root/native strict specs and Hi pass. Full current Linux/native runs and pinned Trust remain pending. See `docs/evidence/viewer-camera/README.md`. The separately requested axis gizmo remains an unapproved draft.

## Requirement evidence

| Requirement | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-006 | REQ-ThreeMDViewer-006 | `uitests/viewer.spec.mjs` full camera turns, pan tools, two-finger gesture and shared native parity fixture tests; `apps/sculpt/Tests/RookRenderingTests/CameraParityTests.swift`, `apps/sculpt/Tests/RookRenderingTests/SculptureLiveVoxelTests.swift` and `apps/sculpt/Tests/RookAppTests/SculptureCanvasPointerTests.swift`; shared `docs/evidence/viewer-camera/camera-parity.json` and actual receipts in `docs/evidence/viewer-camera/README.md`. |

Full native CI selection completed: 635 tests in 54 suites passed. Full Linux UI completed: 197 passed and one heavy-use WebKit test passed on retry, with eight existing skips; the heavy-use test passed alone on recheck. No new skips or relaxed assertions. Current camera implementation source matches commit c94e075164664cf724115f0a7e02cc53905a3114. Final pinned Trust, review and archive remain pending.

## Where these lessons go

- `specs/ThreeMDViewer/context.md`
