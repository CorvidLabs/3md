---
change: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
artifact: docs
---

# Docs

- Human intent for the page is VIEWER-6 in `hi/tools.md`. It now says files stay on the left, Edit, Preview, and Cubes share one panel, and the page does not autoplay.
- The canonical contract is `specs/ThreeMDViewer/ThreeMDViewer.spec.md`, version 7, including REQ-ThreeMDViewer-003 and REQ-ThreeMDViewer-004.
- The page lead in `web/viewer.html` says Edit, the plane preview, and Cubes share the panel beside the files.
- The public README, package versions, and release notes stay as they are. This change does not publish and does not move `v2.2.1`.

Sculpt parity and the caps are recorded in the canonical spec and VIEWER-6. Live comparison screenshots and verification results are in `docs/evidence/viewer-sculpt-parity/`. Definition approval remains open; no lifecycle approval, finalization, or archive was performed.

## Continuing UI and UX pass

Synchronize VIEWER-6 and the canonical ThreeMDViewer contract and companions with the compact workspace, Document actions, camera controls, keyboard navigation, and empty/loading feedback. Record visual evidence under docs/evidence/viewer-ui/. Definition approval and permitted signed provenance remain separate gaps.
