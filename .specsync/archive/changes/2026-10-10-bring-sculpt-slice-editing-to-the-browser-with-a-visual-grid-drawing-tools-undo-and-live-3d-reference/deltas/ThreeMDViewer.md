# ThreeMDViewer delta

## MODIFIED

### REQUIREMENT REQ-ThreeMDViewer-003

The viewer page SHALL show Edit, Preview, Cubes, and Slice in one panel. Exactly one main view SHALL be visible; Slice SHALL include a live 3D reference within its workspace. Cubes SHALL be the default, and the opening document SHALL be a small sculpture whose cubes are inside the window. Files SHALL stay in the column beside that panel. Below 900px, Files and the document SHALL take turns, and the document panel SHALL still switch Edit, Preview, Cubes, and Slice. Choosing Preview SHALL render the live plane view. The workspace SHALL keep infrequent export and conversion actions in the Document disclosure, show insert tools only in Edit, and show the document title in every view. Tabs and the single-row plane outline SHALL provide one tab stop per group, with arrow, Home, and End navigation. File and composition-entry navigation SHALL preserve current edits, caret, and selected plane within the open collection. Edited documents SHALL be identified in every view. Opened files SHALL support filtering and keyboard navigation. Choosing a file or search result on a narrow screen SHALL reveal the document. Search and packing SHALL use current drafts. Failed local opens SHALL preserve the current collection. Explicit document navigation SHALL replace a stale source query with the current document hash. The Slice workspace SHALL preserve the current selected plane, camera and source when entering or leaving the view.

Acceptance Criteria:

- Existing default Cubes, Files navigation and Edit/Preview behavior remain; Slice is the additional main workspace and retains current selection, camera and draft.
- Existing draft, composition, phone and disclosure checks continue to pass alongside Slice tests.

## ADDED

### REQUIREMENT REQ-ThreeMDViewer-008

The browser SHALL offer a Sculpt-style Slice workspace that edits bounded character grids in the current document, preserves the surrounding source, and produces the same supported cell edits as Sculpt.

Acceptance Criteria:

- Add Slice beside Edit, Preview and Cubes while keeping Cubes as the default. Slice presents selectable thumbnails, a large editable grid, current one-based X/Y and slice coordinates, an interactive live 3D reference, and Expand back to Cubes. Selection and camera survive view switches; the reference reuses the existing WebGL context.
- Draw, Erase and Fill use the native palette # @ * + o x : = - and period for erased cells. Square brushes of size 1, 3 and 5 clip to the grid. Fast pointer movement follows the same integer line interpolation as SculptureWorkspace, with no gaps. Fill uses four-neighbor connectivity on the selected slice and ignores brush size.
- A drag is one undo step; no-op edits add no history. Undo and redo restore exact source and synchronize the grid and reference. Source typing and visual edits use coherent history, retained with each draft and shared by linked file/entry views. A new edit clears redo. History is bounded to 100 entries per draft and an 8 MiB collection budget without dropping the current source. Pointer release, cancel, lost capture or navigation finish the current accepted stroke and prevent late writes into another document.
- Arrow keys move the selected cell within bounds; Space applies the current tool. Explicit X/Y controls and Apply support precise keyboard editing. Grid zoom offers Fit, 2x, 4x, 8x and 16x with internal scrolling. Show previous slice overlays occupied cells only behind empty current cells, is unavailable on the first slice, and never mutates source.
- Eligible documents contain complete rectangular fenced ASCII grids with common dimensions, the native palette and period/space empty cells. Empty grids remain editable. Keep the viewer limits of 64 columns, 64 rows, 4000 occupied cells and 12 distinct render glyphs; visual editing additionally limits eligible documents to 256 slices and 1.5 MiB of source. Prose, invalid, ragged, tabbed, unsupported-glyph or over-budget documents retain Edit/Preview/Cubes as appropriate and explain why Slice editing is unavailable. A proposed edit that exceeds a limit is rejected without committing a partial transaction or adding undo history.
- Source edits replace only targeted grid characters, preserving frontmatter, plane coordinates, labels, other body content, fence markers and newline style byte for byte. Visual edits immediately participate in Edited markers, source download, kind 2 export, search and packing. They do not write original files, persist browser storage or rewrite a composition profile.
- Slice remains usable at 390x844 and 320x740 with touch targets, visible keyboard focus, named controls, an accessible selected-cell description and no page overflow. The 2D editor works without WebGL2; the reference explains GPU unavailability and preserves edits. The existing camera, file, composition, export and accessibility regressions continue to pass.
- Shared asymmetric edit fixtures verify native/browser Draw, Erase, Fill, clipped brushes, sparse diagonal input and undo/redo against independently specified final cells. Chromium and WebKit tests exercise actual pointer and keyboard flows, exact source preservation, empty grids, history boundaries, composition switching, downloads and phone layout. Evidence distinguishes automated checks, agent visual inspection, local Trust, remote CI and provenance limitations.
