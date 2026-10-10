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

- `web/viewer.html` keeps files on the left. Edit and Preview share one panel. Edit is the default. Choosing Preview calls `render`.
- Below 900px, Files and the document take turns. The document panel still switches Edit and Preview.
- `uitests/viewer.spec.mjs` covers the wide and narrow switches.
- The element bundle stays text-only and is not rebuilt. Package versions and tag `v2.2.1` stay.

## WP3. Spec

- Update `specs/ThreeMDViewer/` so the purpose, invariant, and REQ-ThreeMDViewer-003 match the panel.
- `specsync check --spec ThreeMDViewer`
- `hi check` at the repository root

No parser, fixture, package version, tag, or publish step is in this change.
