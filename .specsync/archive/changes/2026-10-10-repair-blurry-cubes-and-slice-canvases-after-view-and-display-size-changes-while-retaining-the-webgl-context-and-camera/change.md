---
id: repair-blurry-cubes-and-slice-canvases-after-view-and-display-size-changes-while-retaining-the-webgl-context-and-camera
state: archived
type: bug_fix
base_commit: dab4258541208f8bf6bb5a38f6200a5b348a858e
---

# Repair blurry Cubes and Slice canvases after view and display-size changes while retaining the WebGL context and camera parity

## Intent

Repair blurry Cubes and Slice canvases after view and display-size changes while retaining the WebGL context and camera parity

## Affected Canonical Specs

- `ThreeMDViewer`

## Acceptance Criteria

- The shared 3D canvas drawing buffer follows the displayed Cubes or Slice-reference size and device pixel ratio within the existing 2048-edge/2x limits; switching from a small reference or phone viewport to a large stage remains sharp; resizing retains the same WebGL context, geometry and camera/source/selection; Chromium, WebKit and the actual in-app browser verify transitions and picking.

## No-spec Rationale

Not applicable
