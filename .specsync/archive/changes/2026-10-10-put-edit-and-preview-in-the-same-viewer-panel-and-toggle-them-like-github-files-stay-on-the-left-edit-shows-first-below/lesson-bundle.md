# Lesson bundle — put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Put Edit and Preview in the same viewer panel and toggle them like GitHub. Files stay on the left. Edit shows first. Below 900px, Files and the document take turns, and the document panel still switches Edit and Preview.
- **Kind**: Feature
- **Specs**: ThreeMDViewer
- **Paths**: web/viewer.html, uitests/viewer.spec.mjs, hi/tools.md, specs/ThreeMDViewer
- **Acceptance**: Files stay beside one document panel on desktop; Edit, Preview, and Cubes switch with exactly one visible. Cubes opens first with the framed small sculpture. Below 900px Files and the document take turns.
- **Acceptance**: The page WebGL2 stage preserves Sculpt-style full outward-wound cubes, neighbor-face suppression, glyph fill and gold selected-slice edges, document axes, rendering caps, cached geometry, and one instanced draw. Camera and slice controls work with pointer and keyboard input.
- **Acceptance**: The compact workspace keeps document identity and edited state visible, groups exports under Document, shows insert tools in Edit, and offers Preview for nongrid documents or unavailable WebGL2. Camera controls remain below the drawing with usable phone framing.
- **Acceptance**: File and composition-entry switches preserve edits including invalid and empty drafts, caret, and selected plane. Linked entries share the corresponding file draft. File filtering and keyboard navigation retain focus; narrow-screen file and search opens reveal the document.
- **Acceptance**: Local and public GitHub open, search, sections, pack, and text/kind 2 export remain available. Search and packing use current drafts. Failed local opens preserve the collection. Explicit navigation clears stale source queries in favor of the current hash. Drafts last until refresh or opening another collection.
- **Acceptance**: The element and open-document bundles, Sculpt app, library APIs, format, package versions, fixtures, and trust policies remain unchanged. Complete verified SpecSync closure on the existing feature PR under Leif's 2026-10-10 approval; Leif retains merge authority.

## Evidence

- Verification commit: `47e18d32375406f98df343f4a580ea3e98f6d32d`
- Base commit: `e18f35e2c0c2c11c202342c5bf84b514ee12fe58`
- Verified by: `specsync check --spec ThreeMDViewer`

## From the change's context.md

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

## From the change's testing.md

# Testing

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-003 | REQ-ThreeMDViewer-003 | VIEWER-6 in `hi/tools.md`. `web/viewer.html` switches Edit and Preview in one panel and calls `render` for Preview. `uitests/viewer.spec.mjs` covers the desktop switch and the narrow Files and document switch. |
| REQ-ThreeMDViewer-004 | REQ-ThreeMDViewer-004 | VIEWER-6 in `hi/tools.md`. `web/viewer.html` holds the element on `mode="single"`, removes the render-mode menu and the play control, and draws cubes with WebGL2. `uitests/viewer.spec.mjs` covers no autoplay and about 1400 cubes. |

- `specsync check --spec ThreeMDViewer`
- `hi check` at the repository root
- Playwright `uitests/viewer.spec.mjs` passed 60 tests on Chromium and WebKit after the outline chip opens Preview first. The desktop and narrow layout tests passed again after the bar metadata hide.

The Sculpt parity pass runs `./node_modules/.bin/playwright test viewer.spec.mjs` in `uitests` on Chromium and WebKit. Added GPU pixel evidence for a full single cell from six viewpoints and gold edges with unchanged glyph fill; nearest-Z picking; 1600 cells with zero camera/selection geometry uploads and one instanced draw per redraw. Live screenshots for Character orb and the starter geometry are in `docs/evidence/viewer-sculpt-parity/`. This is agent verification and was completed while definition approval remained open.

Final parity browser verification: 70 passed on Chromium and WebKit. Strict ThreeMDViewer SpecSync check: 1 passed, zero warnings or failures. `hi check`: 85 criteria, no problems. Element bundle: current, 48840 bytes, no storage code.

## Continuing UI and UX pass

The Chromium/WebKit suite covers camera controls, phone layout and non-overlapping controls, Document disclosure dismissal, text and kind 2 download fidelity, editor focus after the save shortcut, prose Preview and sample loading, 30-slice keyboard navigation, GitHub rate-limit recovery, and WebGL2-unavailable guidance. Inspect dark/light desktop, Edit, and phone views and preserve screenshots under docs/evidence/viewer-ui/.

## File navigation fix

The Chromium and WebKit viewer suite covers exact draft restoration, invalid and empty edits, the caret and slice, composition-entry independence, linked entry/file sharing, original-text edited markers, current-text download, search and pack, file filtering and keyboard selection, mobile document reveal, failed-open preservation, and stale source-query removal on navigation. Screenshots from live desktop and phone inspection are in `docs/evidence/viewer-navigation/`. These are agent checks and do not themselves record human definition approval.

## Closure verification

The initial PR 93 hosted UI run had three Linux WebKit failures: a 179px canvas at 320 by 740, slice 0 restored instead of 1, and file keyboard focus leaving the expected button. All three reproduced in the matching Linux Playwright environment. Keep the assertions and verify the fixes in Linux and macOS. Leif's subsequent "I approve" authorizes recording the current definition and closing approval, without claiming backdated approval or independent review.

Closure implementation checks: macOS viewer 98 passed; Linux hosted UI 190 passed and 8 existing skips; Bun helper suite 15 passed; strict SpecSync 4 specs passed with zero warnings and full configured coverage; Hi 85 criteria with no problems; pinned element bundle drift passed at 48840 bytes. Logs remain local under /private/tmp/3md-viewer-closure-*. The Trust and SpecSync closing gates are still pending.

## Full camera movement request

On 2026-10-10 Leif reported, "I can't rotate it fully 360 and easiy move it etc..." The same viewer fix now includes full horizontal and vertical orbit, stable orientation across the poles, visible Orbit/Pan tools, Shift/right/middle drag panning, Shift-arrow panning, two-finger pan and pinch zoom, and proportional wheel zoom. Fit resets camera position without changing the source or selected slice. Camera input keeps cached geometry and the single-draw renderer. These changes are pending implementation and verification; archiving remains pending.

Current camera implementation: Mac Chromium/WebKit viewer 106 passed; Linux projection/phone selection 4 passed; native camera/input and unchanged math preview selection 23 passed in four suites. Root/native strict specs and Hi pass. Full current Linux/native runs and pinned Trust remain pending. See `docs/evidence/viewer-camera/README.md`. The separately requested axis gizmo remains an unapproved draft.

Full native CI selection completed: 635 tests in 54 suites passed. Full Linux UI completed: 197 passed and one heavy-use WebKit test passed on retry, with eight existing skips; the heavy-use test passed alone on recheck. No new skips or relaxed assertions. Current camera implementation source matches commit c94e075164664cf724115f0a7e02cc53905a3114. Final pinned Trust, review and archive remain pending.

## Where these lessons go

- `specs/ThreeMDViewer/context.md`
