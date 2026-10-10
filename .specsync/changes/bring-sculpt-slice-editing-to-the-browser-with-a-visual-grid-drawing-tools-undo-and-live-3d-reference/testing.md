---
change: bring-sculpt-slice-editing-to-the-browser-with-a-visual-grid-drawing-tools-undo-and-live-3d-reference
artifact: testing
---

# Verification

Shared fixtures under docs/evidence/viewer-slice state initial rectangular native-compatible cells, tool/glyph/size, integer sampled path, selected slice and independently written final rows. Include an asymmetric 9x7x5 case, horizontal/diagonal strokes, repeated points, starts on unchanged cells, size-3/5 corner clipping, erase, four-neighbor fill without crossing diagonals or slice boundaries, no-op fill, and undo/redo. Native SculptureWorkspaceTests run the real workspace; browser tests use actual pointer/key actions.

Exact-source cases include frontmatter, distinct z positions and labels, body prose around a closed fence, CRLF, space/period empties, and another untouched plane. Require exact non-target bytes after drawing and exact restoration after undo. Invalid/ragged/tabbed/unsupported grids and all budget boundaries keep their source. Empty native-compatible grids must enter Slice and accept drawing.

History checks mix source typing, insert tools, grid strokes and undo/redo; switch between two files and linked entry/file views; use canceled/lost pointers; exercise trimming and redo invalidation; export/search/pack during pending redraw. No late event may write into a newly activated document. Source download and kind 2 decoding must contain the final edit.

Chromium/WebKit checks cover desktop and 390x844/320x740 layouts, primary touch drawing, keyboard cell movement and Space, explicit X/Y validation, every zoom option and previous-slice visibility. Require internal grid scrolling, visible controls and meaningful accessibility names. GPU-unavailable Slice editing remains usable. Existing one-context, no camera-only geometry upload, nearest picking and pole-crossing tests run unchanged.

Run the complete viewer suite on macOS and the complete UI suite in the existing Linux Playwright environment. Run the focused native workspace fixture selection and broaden native tests only if behavior or failures warrant it. Run strict root and nested app specs with full configured coverage, root/native Hi and pinned Trust 1.2.2 with Fledge 1.7.2. Record actual actor, tested source commit, retries/skips and unchanged provenance limits. No tests or visual approval are claimed yet.
