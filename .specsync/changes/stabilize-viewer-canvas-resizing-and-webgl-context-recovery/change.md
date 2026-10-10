---
id: stabilize-viewer-canvas-resizing-and-webgl-context-recovery
state: implementing
type: feature
base_commit: fc4944c134a8f351f3073bf4febcdebb87df2f81
---

# Stabilize viewer canvas resizing and WebGL context recovery

## Intent

Stabilize viewer canvas resizing and WebGL context recovery

## Affected Canonical Specs

- `ThreeMDViewer`

## Acceptance Criteria

- Resize notifications defer and coalesce redraws without ResizeObserver errors; Slice Fit and 16x scrolling/editing keep a bounded visible bitmap; real WebGL loss pauses GPU work until restoration, then restores geometry and the preserved camera/source/slice; site imports the exact tested revision.

## No-spec Rationale

Not applicable
