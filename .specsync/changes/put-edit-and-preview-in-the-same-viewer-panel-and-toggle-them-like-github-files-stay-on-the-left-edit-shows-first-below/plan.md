---
change: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
artifact: plan
---

# Plan

## WP1. Definition

- Keep this change in draft until Leif approves the definition.
- The semantic delta is `deltas/ThreeMDViewer.md`.
- Hi for this behavior is VIEWER-6 in `hi/tools.md`.

## WP2. Page

- `web/viewer.html` keeps files on the left. Edit, Preview, and Cubes share one panel. Cubes is the default. Choosing Preview calls `render`.
- Below 900px, Files and the document take turns. The document panel still switches Edit and Preview.
- `uitests/viewer.spec.mjs` covers the wide and narrow switches.
- The element bundle stays text-only and is not rebuilt. Package versions and tag `v2.2.1` stay.

## WP3. Spec

- Update `specs/ThreeMDViewer/` so the purpose, invariant, and REQ-ThreeMDViewer-003 match the panel.
- `specsync check --spec ThreeMDViewer`
- `hi check` at the repository root

No parser, fixture, package version, tag, or publish step is in this change.

The cube parity follow-up uses the live Sculpt view as reference: 0.5 lit glyph fill, 0.4 glyph edges, 0.8 gold selected-slice edges, matching background and axes, full outward-wound cubes, neighbor-face suppression, and one instanced draw. Geometry is cached per document. Camera and selection changes use uniforms. The input caps stay 64 by 64 and 4000 cells. Sculpt app edits, painting, large worlds, and OBJ export stay out of scope.
