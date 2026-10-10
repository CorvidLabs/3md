---
change: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
artifact: plan
---

# Plan

## WP1. Definition

- Record Leif's 2026-10-10 approval of the reconciled final definition, then verify and close this change on PR 93.
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

## Continuing UI and UX pass

Compact the identity row and toolbar. Use a native Document disclosure for export and conversion tools, keep composition entry selection in the stage, and show insertion tools only in Edit. Place camera controls below the canvas and use the canvas dimensions for camera framing. Add keyboard camera, tab, and slice navigation, with one tab stop in each navigation group. Explain nongrid documents and unavailable GPU support with a Preview action. Add busy/recovery feedback around the existing GitHub loader.

## File navigation fix

Keep a page-owned draft for each opened file and composition entry, including invalid or empty edits. Share linked entry drafts with their corresponding source file. Refresh the line index from drafts when searching, use draft text when packing, and preserve selection and caret when returning. Validate a local open before replacing the collection. Show filenames and edited state across views, add a file filter with an explicit empty result, and reveal opened documents on narrow screens. Replace stale source queries on explicit navigation.

## Hosted WebKit closure fixes

Reproduce the three PR 93 UI failures with Linux Playwright 1.61.1. Preserve the selected slice through delayed source rendering and navigation, keep file-filter keyboard focus stable across native search events, and provide usable cube drawing space at a 320 by 740 viewport. Keep the existing assertions, then run the browser suites, strict contract checks, Hi, the pinned Trust lane, and provenance verification before closing the lifecycle.

## Full camera movement request

On 2026-10-10 Leif reported, "I can't rotate it fully 360 and easiy move it etc..." The same viewer fix now includes full horizontal and vertical orbit, stable orientation across the poles, visible Orbit/Pan tools, Shift/right/middle drag panning, Shift-arrow panning, two-finger pan and pinch zoom, and proportional wheel zoom. Fit resets camera position without changing the source or selected slice. Camera input keeps cached geometry and the single-draw renderer. These changes are pending implementation and verification; archiving remains pending.
