---
change: add-matching-x-y-z-axis-rotation-gizmos-and-precise-camera-steps-to-sculpt-and-the-viewer
artifact: testing
---

# Testing

Test each document axis with positive, negative and full-turn rotations, including Z roll and pole crossings. Compare native live, scalar and browser projected points and nearest cube hits. Assert inverse steps restore the same basis, invalid inputs do not mutate the camera, camera adjustments preserve document and geometry, and mobile and keyboard controls stay usable. Run the relevant native and Chromium/WebKit regressions and current trust gate after implementation.

## Execution evidence

Implementation commit 8e9a0c4 has 226 passing macOS browser tests, 637 passing configured native tests and 11 passing final native parity tests. Expanded browser fixtures and phone checks each passed 4 cases. Pinned Trust passed; actual unsigned agent:codex provenance was recorded and fails the unchanged permitted-signature/reviewer policy as expected. Linux and final lifecycle receipts are recorded in docs/evidence/viewer-slice. Source and visual verification are distinct from Leif’s diff review.

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-007 | REQ-ThreeMDViewer-007 | Independent shared camera-parity.json matrix/projection values compared with browser GPU uniforms and nearest picks, native scalar/live basis and picks, full-turn/inverse normalization, ASCII Z picking and mesh installation reuse. Browser precise-input and phone tests pass; native/UI screenshots and logs are in docs/evidence/viewer-slice. |
