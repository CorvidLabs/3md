# Lesson bundle — bring-sculpt-slice-editing-to-the-browser-with-a-visual-grid-drawing-tools-undo-and-live-3d-reference

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Bring Sculpt slice editing to the browser with a visual grid, drawing tools, undo and live 3D reference
- **Kind**: Feature
- **Specs**: ThreeMDViewer
- **Paths**: web/viewer.html, uitests/viewer.spec.mjs, apps/sculpt/Tests/RookAppTests/SculptureWorkspaceTests.swift, docs/evidence/viewer-slice, hi/tools.md
- **Acceptance**: Add a Sculpt-style Slice workspace with thumbnails, an editable grid, Draw Erase Fill, the native glyph palette, square brush sizes 1 3 5, gap-free strokes, one undo step per drag, redo, keyboard cell controls, previous-slice overlay, grid zoom and live 3D reference; preserve exact source outside edited grid cells and existing drafts downloads and camera behavior; verify shared native/browser edit fixtures and Chromium WebKit desktop phone interaction checks.

## Evidence

- Verification commit: `6e8d0bb72dec11684d501cf5cbdc25b2f276b853`
- Base commit: `fa61988c163583e5e03cbe00f301b036f37dd7b2`
- Verified by: `specsync check --spec ThreeMDViewer --strict`

## From the change's context.md

# Context

Leif asked to keep making the browser as good as Sculpt.3md after showing the native Slice workspace and hearing the current camera/editor distinction. This definition ports the central slice-authoring loop. The current viewer and camera changes are archived in PR 93; the new feature is an unapproved definition, not a retroactive expansion of those records.

Sources of truth are SculptureEditor.sliceWorkspace/drawingTools, LayerGrid, SculptureWorkspace.paint/line/floodFill/undo/redo and Sculpture.palette. The screenshot shows a 9 by 7 scene with five slices, a teal selected cell and a small 3D reference. Native behavior is reused as the oracle through shared fixtures rather than reimplemented in the native app.

The page owns exact source, parsed document, active file/entry drafts and the single GPU stage. Native tests receive an additive fixture assertion in their existing workspace test file. Library, parser, bundles, format, releases and native editing behavior stay unchanged. X/Y/Z camera controls have a separate complete draft; neither definition is approved yet. Leif retains merge authority. Actual implementation/review actors are agent:codex, never a different agent or an independent human.

## From the change's design.md

# Slice workspace design

Use the supplied Sculpt screenshot as the visual reference and the current CorvidLabs tokens as the browser identity. The main hierarchy is document title, view selector, Slice canvas and tools. The editable grid gets the largest area; the small reference answers where the selected slice sits in the volume. No new page theme or decorative cards.

Color uses existing paper/ink/surface/hairline/accent tokens, with the fixed cube background #11161a, teal cell selection near #39cbbb, quieter previous-layer glyphs and gold selected-slice cube edges #ffca70. Schibsted Grotesk remains the UI face; Spline Sans Mono serves grid glyphs and source. Browser light/dark themes remain supported.

Desktop arrangement inside the existing document panel:

```text
Document title                         Edited
Edit   Preview   Cubes   Slice
Slices          Slice 1           X 7  Y 4
[thumb] 1       Fit  2x 4x 8x 16x    3D reference  Expand
[thumb] 2       +----------------+    [current GPU stage]
[thumb] 3       | editable cells |    Draw  Erase  Fill
[thumb] 4       |                |    # @ * + o x : = -
[thumb] 5       +----------------+    Size  1  3  5
9 x 7 cells     Show previous slice   Selected cell / Apply
                 keyboard hint       Undo  Redo
```

Files remain the existing outer navigation. Slice thumbnails are compact inner navigation; on phones they become a horizontal scroll strip. The reference and tools flow below the grid at narrow widths, with the reference collapsible so it does not crowd drawing. Grid zoom scrolls inside the editor; it never widens the page. Tools keep large touch targets, pressed state and visible focus. One grid focus target plus coordinate controls avoids thousands of cell tab stops.

The subject-specific decision is the glyph grid beside its volumetric context. Review against the screenshot: no hero content, new gradients, overlaid toolbars or generic dashboard cards. Expand moves the same GPU view back to Cubes; edits and camera are preserved.

## From the change's testing.md

# Verification

Shared fixtures under docs/evidence/viewer-slice state initial rectangular native-compatible cells, tool/glyph/size, integer sampled path, selected slice and independently written final rows. Include an asymmetric 9x7x5 case, horizontal/diagonal strokes, repeated points, starts on unchanged cells, size-3/5 corner clipping, erase, four-neighbor fill without crossing diagonals or slice boundaries, no-op fill, and undo/redo. Native SculptureWorkspaceTests run the real workspace; browser tests use actual pointer/key actions.

Exact-source cases include frontmatter, distinct z positions and labels, body prose around a closed fence, CRLF, space/period empties, and another untouched plane. Require exact non-target bytes after drawing and exact restoration after undo. Invalid/ragged/tabbed/unsupported grids and all budget boundaries keep their source. Empty native-compatible grids must enter Slice and accept drawing.

History checks mix source typing, insert tools, grid strokes and undo/redo; switch between two files and linked entry/file views; use canceled/lost pointers; exercise trimming and redo invalidation; export/search/pack during pending redraw. No late event may write into a newly activated document. Source download and kind 2 decoding must contain the final edit.

Chromium/WebKit checks cover desktop and 390x844/320x740 layouts, primary touch drawing, keyboard cell movement and Space, explicit X/Y validation, every zoom option and previous-slice visibility. Require internal grid scrolling, visible controls and meaningful accessibility names. GPU-unavailable Slice editing remains usable. Existing one-context, no camera-only geometry upload, nearest picking and pole-crossing tests run unchanged.

Run the complete viewer suite on macOS and the complete UI suite in the existing Linux Playwright environment. Run the focused native workspace fixture selection and broaden native tests only if behavior or failures warrant it. Run strict root and nested app specs with full configured coverage, root/native Hi and pinned Trust 1.2.2 with Fledge 1.7.2. Record actual actor, tested source commit, retries/skips and unchanged provenance limits. Actual execution evidence is recorded under docs/evidence/viewer-slice. No independent human review or permitted signature is claimed.

## Execution evidence

Implementation commit 8e9a0c4 has 226 passing macOS browser tests, 637 passing configured native tests and 11 passing final native parity tests. Expanded browser fixtures and phone checks each passed 4 cases. Pinned Trust passed; actual unsigned agent:codex provenance was recorded and fails the unchanged permitted-signature/reviewer policy as expected. Linux CI passed 218 functional tests with 8 existing platform-snapshot skips and no retries; all macOS snapshots passed. Current receipts are in docs/evidence/viewer-slice; final lifecycle receipts are separate. Source and visual verification are distinct from Leif’s diff review.

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-003 | REQ-ThreeMDViewer-003 | Actual four-view layout in web/viewer.html; full Chromium/WebKit viewer regressions and desktop/phone screenshots in docs/evidence/viewer-slice. |
| REQ-ThreeMDViewer-008 | REQ-ThreeMDViewer-008 | Shared slice-parity.json cases run by browser pointer gestures and native browserSliceFixturesMatchNativeWorkspaceToolsAndWholeStrokeHistory. Source preservation, bounded history, navigation, keyboard, downloads, GPU refusal and phone tests pass; actual logs are in docs/evidence/viewer-slice. |

## Where these lessons go

- `specs/ThreeMDViewer/context.md`
