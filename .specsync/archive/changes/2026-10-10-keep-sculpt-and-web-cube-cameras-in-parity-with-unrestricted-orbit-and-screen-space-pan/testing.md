---
change: keep-sculpt-and-web-cube-cameras-in-parity-with-unrestricted-orbit-and-screen-space-pan
artifact: testing
---

# Testing

Browser regressions cover complete turns and finite matrices through both poles, screen-space pan with unchanged yaw/pitch/source/slice, mouse-button/modifier controls, proportional wheel input, touch pinch/pan and cancellation, translated nearest-cube picking, Fit, bounded zoom, no camera geometry upload, and 320-pixel phone layout. Native regressions cover finite sanitized camera inputs, scalar/prepared/live projection agreement across matching full-turn/panned cases, geometry reuse and native pointer forwarding. Retain actual verification receipts; no current camera suite result or final Trust verdict is claimed yet.

Current camera implementation: Mac Chromium/WebKit viewer 106 passed; Linux projection/phone selection 4 passed; native camera/input and unchanged math preview selection 23 passed in four suites. Root/native strict specs and Hi pass. Full current Linux/native runs and pinned Trust remain pending. See `docs/evidence/viewer-camera/README.md`. The separately requested axis gizmo remains an unapproved draft.

## Requirement evidence

| Requirement | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-006 | REQ-ThreeMDViewer-006 | `uitests/viewer.spec.mjs` full camera turns, pan tools, two-finger gesture and shared native parity fixture tests; `apps/sculpt/Tests/RookRenderingTests/CameraParityTests.swift`, `apps/sculpt/Tests/RookRenderingTests/SculptureLiveVoxelTests.swift` and `apps/sculpt/Tests/RookAppTests/SculptureCanvasPointerTests.swift`; shared `docs/evidence/viewer-camera/camera-parity.json` and actual receipts in `docs/evidence/viewer-camera/README.md`. |

Full native CI selection completed: 635 tests in 54 suites passed. Full Linux UI completed: 197 passed and one heavy-use WebKit test passed on retry, with eight existing skips; the heavy-use test passed alone on recheck. No new skips or relaxed assertions. Current camera implementation source matches commit c94e075164664cf724115f0a7e02cc53905a3114. Final pinned Trust, review and archive remain pending.
