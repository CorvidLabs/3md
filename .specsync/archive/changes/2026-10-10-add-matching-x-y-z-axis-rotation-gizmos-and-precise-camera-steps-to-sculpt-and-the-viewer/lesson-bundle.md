# Lesson bundle — add-matching-x-y-z-axis-rotation-gizmos-and-precise-camera-steps-to-sculpt-and-the-viewer

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Add matching X Y Z axis rotation gizmos and precise camera steps to Sculpt and the viewer
- **Kind**: Feature
- **Specs**: ThreeMDViewer
- **Paths**: web/viewer.html, uitests/viewer.spec.mjs, hi/tools.md, specs/ThreeMDViewer, apps/sculpt/Sources/RookSculpture/SculptureProjection.swift, apps/sculpt/Sources/RookApp/SculptureViewport.swift, apps/sculpt/Sources/RookRendering/SculptureLiveVoxelView.swift, apps/sculpt/Sources/RookRendering/SculptureVoxelGeometry.swift, apps/sculpt/Tests, apps/sculpt/hi, apps/sculpt/specs
- **Acceptance**: Both volume views show a small sphere with colored X, Y and Z rotation rings and accessible axis buttons. Choosing an axis constrains dragging and step buttons to rotation around that document axis; Free restores unconstrained orbit.
- **Acceptance**: Three-axis rotation preserves an orthonormal camera orientation and supports Z rotation without changing model cells, slice, Undo, files, or installed geometry. Native and browser use the same document-axis convention, including row Y and plane Z.
- **Acceptance**: Both views offer an editable rotation step in degrees (default 15 degrees) with minus and plus nudges, and an editable pan step in cells (default 0.25) with directional nudges. Values must be finite and positive; invalid input leaves the current camera unchanged. Fit resets the default pose and pan.
- **Acceptance**: Tests compare shared asymmetric projection and picking cases including Z rotation, full X/Y/Z turns, negative nudges and exact inverse steps; native live and scalar renderers agree. Camera controls remain usable on narrow screens and have keyboard labels and focus indication.
- **Acceptance**: Synchronize viewer and Sculpt contracts and intent, record actual current tests, complete verified lifecycle closure under Leif’s approved PR 93 camera scope, and preserve storage, rendering budgets, parser APIs, releases and trust policy.

## Evidence

- Verification commit: `60055f7806a4d46964b766672784be45713e3c3a`
- Base commit: `fefd8316adfff3af8bdb87d26b4a417650540b56`
- Verified by: `specsync check --spec ThreeMDViewer --strict`

## From the change's context.md

# Context

Leif directly requested a Unity/Godot-style three-axis rotation sphere and precise movement. This is a new addition to the approved full orbit and pan work. The user wants matching native Sculpt and browser behavior. This definition is pending human approval; no implementation, verification, acceptance or archive is claimed.

## From the change's design.md

# Design

Show a compact orientation sphere with red X, green Y and blue Z rings. Click a ring or its labeled axis button to constrain rotation. Free restores ordinary orbit. Degree-step minus/plus buttons rotate only the selected axis; directional buttons use the cell-valued pan step. The controls use native SwiftUI and browser SVG, fit the existing stage design and remain accessible by keyboard. Default steps are 15 degrees and 0.25 cells. Preserve browser controls below the drawing and compact phone layout.

## From the change's testing.md

# Testing

Test each document axis with positive, negative and full-turn rotations, including Z roll and pole crossings. Compare native live, scalar and browser projected points and nearest cube hits. Assert inverse steps restore the same basis, invalid inputs do not mutate the camera, camera adjustments preserve document and geometry, and mobile and keyboard controls stay usable. Run the relevant native and Chromium/WebKit regressions and current trust gate after implementation.

## Execution evidence

Implementation commit 8e9a0c4 has 226 passing macOS browser tests, 637 passing configured native tests and 11 passing final native parity tests. Expanded browser fixtures and phone checks each passed 4 cases. Pinned Trust passed; actual unsigned agent:codex provenance was recorded and fails the unchanged permitted-signature/reviewer policy as expected. Linux CI passed 218 functional tests with 8 existing platform-snapshot skips and no retries; all macOS snapshots passed. Current receipts are in docs/evidence/viewer-slice; final lifecycle receipts are separate. Source and visual verification are distinct from Leif’s diff review.

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-007 | REQ-ThreeMDViewer-007 | Independent shared camera-parity.json matrix/projection values compared with browser GPU uniforms and nearest picks, native scalar/live basis and picks, full-turn/inverse normalization, ASCII Z picking and mesh installation reuse. Browser precise-input and phone tests pass; native/UI screenshots and logs are in docs/evidence/viewer-slice. |

## Where these lessons go

- `specs/ThreeMDViewer/context.md`
