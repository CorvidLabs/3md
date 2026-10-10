---
spec: ThreeMDViewer.spec.md
---

## User Stories

- As a reader, I want files on the left, and Edit and Preview switching in the same panel.
- As a reader, I want to point the page at a public GitHub repo, folder, or file, or at a file or folder on this computer.
- As a reader, I want search to read every line and open that plane.

## Acceptance Criteria

- **REQ-ThreeMDViewer-001** The viewer page SHALL present files, source, and the live plane view. It SHALL open a public GitHub repo, folder, or file, or a file or folder from this computer. Search SHALL read every opened line and open that plane. Markdown headings SHALL become planes. Opened files SHALL pack into one text document, and that document SHALL download as uncompressed kind 2. The `<three-md>` element SHALL stay a text renderer.
- **REQ-ThreeMDViewer-002** The page SHALL accept a GitHub locator only when the host is `github.com`, `www.github.com`, or `raw.githubusercontent.com`, or when the input is an `owner/repo` name. It SHALL NOT treat those names as a match when they appear only as a substring. A public load SHALL skip `node_modules`, SHALL keep at most 400 files, and SHALL skip a file larger than 1.5 MB. The line index SHALL keep at most 12,000 rows. Apple LZFSE SHALL be refused. The ThreeMD library SHALL stay free of filesystem and network I/O.
- **REQ-ThreeMDViewer-003** The viewer page SHALL show Edit, Preview, Cubes, and Slice in one panel. Exactly one main view SHALL be visible; Slice SHALL include a live 3D reference within its workspace. Cubes SHALL be the default, and the opening document SHALL be a small sculpture whose cubes are inside the window. Files SHALL stay in the column beside that panel. Below 900px, Files and the document SHALL take turns, and the document panel SHALL still switch Edit, Preview, Cubes, and Slice. Choosing Preview SHALL render the live plane view. The workspace SHALL keep infrequent export and conversion actions in the Document disclosure, show insert tools only in Edit, and show the document title in every view. Tabs and the single-row plane outline SHALL provide one tab stop per group, with arrow, Home, and End navigation. File and composition-entry navigation SHALL preserve current edits, caret, and selected plane within the open collection. Edited documents SHALL be identified in every view. Opened files SHALL support filtering and keyboard navigation. Choosing a file or search result on a narrow screen SHALL reveal the document. Search and packing SHALL use current drafts. Failed local opens SHALL preserve the current collection. Explicit document navigation SHALL replace a stale source query with the current document hash. The Slice workspace SHALL preserve the current selected plane, camera and source when entering or leaving the view.
- **REQ-ThreeMDViewer-004** The viewer page SHALL NOT offer a render-mode switch and SHALL NOT autoplay. Preview SHALL stay on one plane. Cubes SHALL draw complete, nearly cell-sized cubes with WebGL2, lit glyph-colored fill at 0.5 opacity and visible glyph-colored edges. The selected Z slice SHALL have gold edges at 0.8 opacity while retaining its glyph fill. The background SHALL be rgb(0.065, 0.085, 0.10). X SHALL be the column, Y the text row with row 0 toward the top, and Z the plane index. Orbit, zoom, and slice selection SHALL reuse the installed geometry. Each redraw SHALL use one instanced draw. Orbit SHALL rotate through full horizontal and vertical turns with a continuous camera basis at the poles. Pan mode, Shift-drag, and middle/right-drag SHALL move the view in screen space. Shift-arrow keys SHALL pan the focused canvas. Two-finger touch gestures SHALL pan and pinch to zoom. Wheel zoom SHALL respond proportionally to the gesture. Fit SHALL restore yaw 0.6, pitch 0.35, zoom 1, and zero pan without changing source or the selected slice. Camera buttons and the focused canvas SHALL support bounded zoom, and arrow keys SHALL orbit the focused canvas. Camera controls SHALL sit below the drawing without covering cubes. A document without a cube grid and an unavailable WebGL2 context SHALL offer Preview while preserving the source. The element bundle SHALL stay a text renderer.

## Constraints

- The element bundle stays text-only and is not rebuilt for this page.
- Package versions stay 2.2.1. Tag `v2.2.1` stays where it is.
- The page fetches public GitHub only. The library does the parse and the kind 2 encode.

## Out of Scope

- Parser, CLI, and element behavior.
- Browser 3D cube painting, structural slice actions, volume resizing, 256 cubed volumes, sparse worlds and OBJ export. Sculpt changes are limited to the approved volume camera parity scope.
- Gallery cards, which stay the curated text set.
- Private GitHub repos, remote folder indexes beyond the public git tree, and Apple LZFSE.

### REQ-ThreeMDViewer-001

The viewer page SHALL present files, source, and the live plane view. It SHALL open a public GitHub repo, folder, or file, or a file or folder from this computer. Search SHALL read every opened line and open that plane. Markdown headings SHALL become planes. Opened files SHALL pack into one text document, and that document SHALL download as uncompressed kind 2. The `<three-md>` element SHALL stay a text renderer.

Acceptance Criteria:

- The spec states files, the editable source, and the live plane view, plus GitHub and local open, every-line search, section planes, pack, kind 2 download, and the text-only element. REQ-ThreeMDViewer-003 states that Edit and Preview share one panel.
- Evidence is VIEWER-6, the bun tests in `web/gather.test.ts` and `web/open-document.test.ts`, and `uitests/viewer.spec.mjs`.

### REQ-ThreeMDViewer-002

The page SHALL accept a GitHub locator only when the host is `github.com`, `www.github.com`, or `raw.githubusercontent.com`, or when the input is an `owner/repo` name. It SHALL NOT treat those names as a match when they appear only as a substring. A public load SHALL skip `node_modules`, SHALL keep at most 400 files, and SHALL skip a file larger than 1.5 MB. The line index SHALL keep at most 12,000 rows. Apple LZFSE SHALL be refused. The ThreeMD library SHALL stay free of filesystem and network I/O.

Acceptance Criteria:

- `web/github-source.ts` and `web/github-source.test.ts` match hosts with `URL.hostname` and paths with `pathname`.
- The tree cap, the byte cap, the line cap, and the LZFSE refusal are named in the spec and covered by the existing tests.

### REQ-ThreeMDViewer-003

The viewer page SHALL show Edit, Preview, Cubes, and Slice in one panel. Exactly one main view SHALL be visible; Slice SHALL include a live 3D reference within its workspace. Cubes SHALL be the default, and the opening document SHALL be a small sculpture whose cubes are inside the window. Files SHALL stay in the column beside that panel. Below 900px, Files and the document SHALL take turns, and the document panel SHALL still switch Edit, Preview, Cubes, and Slice. Choosing Preview SHALL render the live plane view. The workspace SHALL keep infrequent export and conversion actions in the Document disclosure, show insert tools only in Edit, and show the document title in every view. Tabs and the single-row plane outline SHALL provide one tab stop per group, with arrow, Home, and End navigation. File and composition-entry navigation SHALL preserve current edits, caret, and selected plane within the open collection. Edited documents SHALL be identified in every view. Opened files SHALL support filtering and keyboard navigation. Choosing a file or search result on a narrow screen SHALL reveal the document. Search and packing SHALL use current drafts. Failed local opens SHALL preserve the current collection. Explicit document navigation SHALL replace a stale source query with the current document hash. The Slice workspace SHALL preserve the current selected plane, camera and source when entering or leaving the view.

Acceptance Criteria:

- Existing default Cubes, Files navigation and Edit/Preview behavior remain; Slice is the additional main workspace and retains current selection, camera and draft.
- Existing draft, composition, phone and disclosure checks continue to pass alongside Slice tests.

### REQ-ThreeMDViewer-004

The viewer page SHALL NOT offer a render-mode switch and SHALL NOT autoplay. Preview SHALL stay on one plane. Cubes SHALL draw complete, nearly cell-sized cubes with WebGL2, lit glyph-colored fill at 0.5 opacity and visible glyph-colored edges. The selected Z slice SHALL have gold edges at 0.8 opacity while retaining its glyph fill. The background SHALL be rgb(0.065, 0.085, 0.10). X SHALL be the column, Y the text row with row 0 toward the top, and Z the plane index. Orbit, zoom, and slice selection SHALL reuse the installed geometry. Each redraw SHALL use one instanced draw. Orbit SHALL rotate through full horizontal and vertical turns with a continuous camera basis at the poles. Pan mode, Shift-drag, and middle/right-drag SHALL move the view in screen space. Shift-arrow keys SHALL pan the focused canvas. Two-finger touch gestures SHALL pan and pinch to zoom. Wheel zoom SHALL respond proportionally to the gesture. Fit SHALL restore yaw 0.6, pitch 0.35, zoom 1, and zero pan without changing source or the selected slice. Camera buttons and the focused canvas SHALL support bounded zoom, and arrow keys SHALL orbit the focused canvas. Camera controls SHALL sit below the drawing without covering cubes. A document without a cube grid and an unavailable WebGL2 context SHALL offer Preview while preserving the source. The element bundle SHALL stay a text renderer.

Acceptance Criteria:

- The page has no render-mode menu and no page play control. A frame-axis document is not playing.
- A fenced grid draws on WebGL2, including about 1400 cubes. A single cell has filled faces from every side. Selection changes edge color while the face interior keeps its glyph color. Camera, zoom, and selection redraw without geometry uploads. Click picking selects the nearest visible cube’s Z slice.
- X is the column, Y is the text row with row 0 toward the top, and Z is the plane index. Space, dot, and tab are empty. Keep the 64 by 64 per-plane and 4000-cell caps.
- Evidence is VIEWER-6 and the cube tests in `uitests/viewer.spec.mjs`.
- The same 3D context and geometry remain installed when moving between Cubes and the Slice reference or changing display size. The drawable follows the visible pane size and device pixel ratio, bounded to 2x and a proportional 2048-pixel edge cap; unchanged sizes avoid bitmap reallocations. Small-to-large, phone/desktop and Retina transitions remain sharp without changing source, camera, slice or nearest picking.
- Resize notifications SHALL schedule coalesced drawing outside observer delivery. Slice SHALL allocate only a visible-area bitmap at high zoom while preserving scroll coordinates and precise edits. A lost WebGL context SHALL remain suspended without bitmap allocation or context retries until restoration, then rebuild resources while preserving source, selected slice and camera.

### REQ-ThreeMDViewer-006

The browser and Sculpt volume camera SHALL expose the same full-turn orbit, screen-space pan, bounded proportional zoom, default Fit pose and camera-correct nearest-cube picking, with matched camera basis and documented coordinate conversion.

Acceptance Criteria:

- Both the web cube viewer and Sculpt volume canvas orbit through complete horizontal and vertical turns, using the same continuous camera basis at the poles and upside down. Drag sensitivity is 0.008 radians per point; web yaw is the negative of native yaw to account for its coordinate convention.
- Both volume cameras support screen-space pan without changing the document, mesh, slice, paint history or geometry revision. Native Shift-left, middle and right dragging pan; an explicit Pan button works in Orbit. Native scroll zoom and trackpad magnification respond proportionally. Browser Pan, modified mouse dragging and two-finger pan/pinch provide the equivalent controls.
- Zoom stays between 0.5 and 2 in both views. Fit restores the default matched pose (native yaw -0.6 / web yaw 0.6, pitch 0.35), zoom 1 and zero pan. The native CPU cube/ASCII projection, live GPU camera and picking all honor the same orbit and pan.
- Shared asymmetric fixture receipts compare camera bases and screen projections across native and browser views, including pole crossings, upside-down and panned cameras. Picking chooses the nearest cube after those movements and camera changes reuse geometry. Mac native regressions and browser Chromium/WebKit regressions cover the controls.
- Keep native painting, stroke freezing, CPU/export budgets and the browser one-draw cube mesh, colors, axes and bounded grid behavior. Keep app and viewer specifications and human intent synchronized. Sparse-world Explore, storage formats, parser APIs, package releases and trust policies remain outside this camera change.

### REQ-ThreeMDViewer-008

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

### REQ-ThreeMDViewer-007

The viewer and Sculpt volume view SHALL provide matched document-axis rotation constraints and numerical rotation/pan steps alongside the camera sphere.

Acceptance Criteria:

- Both volume views show a small sphere with colored X, Y and Z rotation rings and accessible axis buttons. Choosing an axis constrains dragging and step buttons to rotation around that document axis; Free restores unconstrained orbit.
- Three-axis rotation preserves an orthonormal camera orientation and supports Z rotation without changing model cells, slice, Undo, files, or installed geometry. Native and browser use the same document-axis convention, including row Y and plane Z.
- Both views offer an editable rotation step in degrees (default 15 degrees) with minus and plus nudges, and an editable pan step in cells (default 0.25) with directional nudges. Values must be finite and positive; invalid input leaves the current camera unchanged. Fit resets the default pose and pan.
- Tests compare shared asymmetric projection and picking cases including Z rotation, full X/Y/Z turns, negative nudges and exact inverse steps; native live and scalar renderers agree. Camera controls remain usable on narrow screens and have keyboard labels and focus indication.
- Synchronize viewer and Sculpt contracts and intent, record actual current tests, and complete verified lifecycle closure only under Leif’s explicit approval of this new definition. Leif retains PR merge authority. Preserve storage, rendering budgets, parser APIs, releases and trust policy.

