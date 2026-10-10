---
id: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
state: draft
type: feature
base_commit: e18f35e2c0c2c11c202342c5bf84b514ee12fe58
---

# Share Edit, Preview, and Cubes in one viewer workspace

## Intent

Files stay on the left while Edit, Preview, and Cubes share the document panel. Cubes opens first with a small sculpture and matches Sculpt’s stage semantics. Leif’s continuation request asks for clearer controls and more room for the stage on desktop and phone screens.

## Affected Canonical Specs

- `ThreeMDViewer`

## Acceptance Criteria

- Keep the cube-stage geometry, colors, axes, rendering caps, and reuse contract.
- Keep document identity visible and group exports and conversions under Document; show insert tools in Edit.
- Add Fit and zoom controls below the canvas, keyboard orbiting, and a scrolling slice row with keyboard navigation.
- Offer Preview for documents without cubes and unavailable WebGL2. Show and recover GitHub loading controls.
- Preserve local and public GitHub open, every-line search, composition entries, sections, pack, and text/kind 2 download. The element stays a text renderer.

## Authority and lifecycle

Leif requested continued UI and UX implementation on 2026-10-09. This artifact remains an unapproved definition draft. Agent implementation and validation do not record Leif’s diff review or authorize a merge, tag, release, or deployment.

## No-spec Rationale

Not applicable
