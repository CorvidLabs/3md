---
change: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
artifact: tasks
---

# Tasks

- [x] Put Edit and Preview in one panel in `web/viewer.html`, with Cubes first.
- [x] On a narrow window, switch Files and the document, and keep Edit and Preview inside the document.
- [x] Call `render` when Preview is shown.
- [x] Update VIEWER-6 and `specs/ThreeMDViewer/`.
- [x] Update the desktop and narrow Playwright tests.
- [x] Reconcile the final definition under Leif's direct 2026-10-10 approval; record that approval through SpecSync.

- [x] Run Sculpt and compare the same sculpture in both live cube stages.
- [x] Match lit glyph fill and gold selected-slice edges, full faces, background, axes, and framing.
- [x] Keep camera, zoom, and selection on cached geometry with one instanced draw.

## Continuing UI and UX pass

- [x] Compact the workspace and group document actions.
- [x] Keep document titles visible and insert tools in Edit.
- [x] Add Fit, bounded zoom, keyboard orbiting, and scrolling slice navigation.
- [x] Explain nongrid/GPU-unavailable states and recover GitHub loading controls.
- [x] Verify the final browser suite and capture visual evidence.

Pinned Trust runs after the feature head is committed and pushed; its result is recorded in the PR and local verification output.

Leif approved the final scope and verified closure on 2026-10-10. This records direct human authorization, without claiming human diff review.

- [x] Preserve file, linked-entry, invalid, and empty drafts with caret and selected plane across navigation.
- [x] Mark edits, filter files, navigate by keyboard, reveal phone documents, and avoid stale source queries.
- [x] Search and pack current drafts, and preserve the collection after a failed open.

## Hosted WebKit closure fixes

- [x] Correct delayed-render slice preservation, stable alphabetical file navigation, and small-phone drawing space.
- [x] Verify the implemented viewer behavior in macOS Chromium/WebKit, the full Linux hosted UI suite, strict specs, Hi, helper tests, and bundle drift.

Targeted lifecycle verification, pinned Trust, provenance recording, acceptance, and archive remain pending. The verified implementation tasks above do not claim these later gates have completed.
