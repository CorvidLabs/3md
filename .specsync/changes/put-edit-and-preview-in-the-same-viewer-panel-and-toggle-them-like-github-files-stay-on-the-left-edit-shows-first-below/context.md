---
change: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
artifact: context
---

# Context

## What led here

The hosted page shipped in PR 90 and the ThreeMDViewer spec shipped in PR 91. That page showed files, source, and the live view side by side. Leif asked for Edit and Preview to share one panel and toggle, like GitHub's Write and Preview.

## What a later session needs

- PR 92 merged; follow-up PR 93 uses branch `leif/viewer-draft-navigation` in `/Users/leif/Development/_CorvidLabs/3md-edit-preview`, based on `e18f35e`. Do not push to main. Do not merge.
- Files stay on the left. Edit, Preview, and Cubes share `.pane.stage`. Default is Cubes. Below 900px, `.fileswitch` swaps Files and the document.
- Choosing Preview calls `lab.render()` so the element measures the panel. The element still receives source while Edit is showing.
- Cubes is the first view of that panel, and the opening document is a small sculpture so the cubes are in the window. It reads the parsed planes and draws a fenced character grid as lit WebGL2 cubes. Orbit and zoom move the camera. The page does not offer a render-mode switch and does not autoplay. Preview stays on one plane. The element bundle is not a voxel engine and is not rebuilt.
- The element bundle is not rebuilt. Do not bump versions or move tag `v2.2.1`.
- Leif approved the final scope and verified lifecycle closure on 2026-10-10. Record this approval at the current time; earlier implementation was kept in draft.
- Do not finalize the kind 2, GDScript, storage-ceiling, or 2.1 docs-coverage changes.

The cube parity follow-up uses the live Sculpt view as reference: 0.5 lit glyph fill, 0.4 glyph edges, 0.8 gold selected-slice edges, matching background and axes, full outward-wound cubes, neighbor-face suppression, and one instanced draw. Geometry is cached per document. Camera and selection changes use uniforms. The input caps stay 64 by 64 and 4000 cells. Sculpt app edits, painting, large worlds, and OBJ export stay out of scope.

## Continuing UI and UX pass

Leif requested continued UI and UX work on 2026-10-09. Preserve the cube-stage and publication limits. The draft lifecycle restriction was superseded by Leif's explicit 2026-10-10 approval of verified closure. The compact layout keeps the existing CorvidLabs tokens and typography; the stage is the focus.

## Full camera movement request

On 2026-10-10 Leif reported, "I can't rotate it fully 360 and easiy move it etc..." The same viewer fix now includes full horizontal and vertical orbit, stable orientation across the poles, visible Orbit/Pan tools, Shift/right/middle drag panning, Shift-arrow panning, two-finger pan and pinch zoom, and proportional wheel zoom. Fit resets camera position without changing the source or selected slice. Camera input keeps cached geometry and the single-draw renderer. These changes are pending implementation and verification; archiving remains pending.

Current implementation and shared fixture receipts are in `docs/evidence/viewer-camera/`. Live pan and Fit preserved the native scene and slice. Default utility-camera framing preserves historical example images. Final full suites, Trust and lifecycle closure remain pending; the separate gizmo definition is not approved.
