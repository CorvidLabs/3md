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
- **REQ-ThreeMDViewer-003** The viewer page SHALL show Edit, Preview, and Cubes in one panel. Exactly one of them SHALL be visible. Cubes SHALL be the default, and the opening document SHALL be a small sculpture whose cubes are inside the window. Files SHALL stay in the column beside that panel. Below 900px, Files and the document SHALL take turns, and the document panel SHALL still switch Edit, Preview, and Cubes. Choosing Preview SHALL render the live plane view. The workspace SHALL keep infrequent export and conversion actions in the Document disclosure, show insert tools only in Edit, and show the document title in every view. Tabs and the single-row plane outline SHALL provide one tab stop per group, with arrow, Home, and End navigation. File and composition-entry navigation SHALL preserve current edits, caret, and selected plane within the open collection. Edited documents SHALL be identified in every view. Opened files SHALL support filtering and keyboard navigation. Choosing a file or search result on a narrow screen SHALL reveal the document. Search and packing SHALL use current drafts. Failed local opens SHALL preserve the current collection. Explicit document navigation SHALL replace a stale source query with the current document hash.
- **REQ-ThreeMDViewer-004** The viewer page SHALL NOT offer a render-mode switch and SHALL NOT autoplay. Preview SHALL stay on one plane. Cubes SHALL draw complete, nearly cell-sized cubes with WebGL2, lit glyph-colored fill at 0.5 opacity and visible glyph-colored edges. The selected Z slice SHALL have gold edges at 0.8 opacity while retaining its glyph fill. The background SHALL be rgb(0.065, 0.085, 0.10). X SHALL be the column, Y the text row with row 0 toward the top, and Z the plane index. Orbit, zoom, and slice selection SHALL reuse the installed geometry. Each redraw SHALL use one instanced draw. Orbit SHALL rotate through full horizontal and vertical turns with a continuous camera basis at the poles. Pan mode, Shift-drag, and middle/right-drag SHALL move the view in screen space. Shift-arrow keys SHALL pan the focused canvas. Two-finger touch gestures SHALL pan and pinch to zoom. Wheel zoom SHALL respond proportionally to the gesture. Fit SHALL restore yaw 0.6, pitch 0.35, zoom 1, and zero pan without changing source or the selected slice. Camera buttons and the focused canvas SHALL support bounded zoom, and arrow keys SHALL orbit the focused canvas. Camera controls SHALL sit below the drawing without covering cubes. A document without a cube grid and an unavailable WebGL2 context SHALL offer Preview while preserving the source. The element bundle SHALL stay a text renderer.

## Constraints

- The element bundle stays text-only and is not rebuilt for this page.
- Package versions stay 2.2.1. Tag `v2.2.1` stays where it is.
- The page fetches public GitHub only. The library does the parse and the kind 2 encode.

## Out of Scope

- Parser, CLI, and element behavior.
- Cube painting or erasing into source, 256 cubed volumes, sparse worlds, OBJ export, and Sculpt app changes.
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

The viewer page SHALL show Edit, Preview, and Cubes in one panel. Exactly one of them SHALL be visible. Cubes SHALL be the default, and the opening document SHALL be a small sculpture whose cubes are inside the window. Files SHALL stay in the column beside that panel. Below 900px, Files and the document SHALL take turns, and the document panel SHALL still switch Edit, Preview, and Cubes. Choosing Preview SHALL render the live plane view. The workspace SHALL keep infrequent export and conversion actions in the Document disclosure, show insert tools only in Edit, and show the document title in every view. Tabs and the single-row plane outline SHALL provide one tab stop per group, with arrow, Home, and End navigation. File and composition-entry navigation SHALL preserve current edits, caret, and selected plane within the open collection. Edited documents SHALL be identified in every view. Opened files SHALL support filtering and keyboard navigation. Choosing a file or search result on a narrow screen SHALL reveal the document. Search and packing SHALL use current drafts. Failed local opens SHALL preserve the current collection. Explicit document navigation SHALL replace a stale source query with the current document hash.

Acceptance Criteria:

- At a desktop width, files stay visible. Cubes shows first, and the lit cubes are inside the window. Edit shows the editor and hides the cubes. Preview shows the live plane view and hides the editor.
- At 800px, Files and the document take turns. The document panel still switches Edit, Preview, and Cubes.
- Evidence is VIEWER-6 and the layout tests in `uitests/viewer.spec.mjs`.

### REQ-ThreeMDViewer-004

The viewer page SHALL NOT offer a render-mode switch and SHALL NOT autoplay. Preview SHALL stay on one plane. Cubes SHALL draw complete, nearly cell-sized cubes with WebGL2, lit glyph-colored fill at 0.5 opacity and visible glyph-colored edges. The selected Z slice SHALL have gold edges at 0.8 opacity while retaining its glyph fill. The background SHALL be rgb(0.065, 0.085, 0.10). X SHALL be the column, Y the text row with row 0 toward the top, and Z the plane index. Orbit, zoom, and slice selection SHALL reuse the installed geometry. Each redraw SHALL use one instanced draw. Orbit SHALL rotate through full horizontal and vertical turns with a continuous camera basis at the poles. Pan mode, Shift-drag, and middle/right-drag SHALL move the view in screen space. Shift-arrow keys SHALL pan the focused canvas. Two-finger touch gestures SHALL pan and pinch to zoom. Wheel zoom SHALL respond proportionally to the gesture. Fit SHALL restore yaw 0.6, pitch 0.35, zoom 1, and zero pan without changing source or the selected slice. Camera buttons and the focused canvas SHALL support bounded zoom, and arrow keys SHALL orbit the focused canvas. Camera controls SHALL sit below the drawing without covering cubes. A document without a cube grid and an unavailable WebGL2 context SHALL offer Preview while preserving the source. The element bundle SHALL stay a text renderer.

Acceptance Criteria:

- The page has no render-mode menu and no page play control. A frame-axis document is not playing.
- A fenced grid draws on WebGL2, including about 1400 cubes. A single cell has filled faces from every side. Selection changes edge color while the face interior keeps its glyph color. Camera, zoom, and selection redraw without geometry uploads. Click picking selects the nearest visible cube’s Z slice.
- X is the column, Y is the text row with row 0 toward the top, and Z is the plane index. Space, dot, and tab are empty. Keep the 64 by 64 per-plane and 4000-cell caps.
- Evidence is VIEWER-6 and the cube tests in `uitests/viewer.spec.mjs`.

### REQ-ThreeMDViewer-006

The browser and Sculpt volume camera SHALL expose the same full-turn orbit, screen-space pan, bounded proportional zoom, default Fit pose and camera-correct nearest-cube picking, with matched camera basis and documented coordinate conversion.

Acceptance Criteria:

- Both the web cube viewer and Sculpt volume canvas orbit through complete horizontal and vertical turns, using the same continuous camera basis at the poles and upside down. Drag sensitivity is 0.008 radians per point; web yaw is the negative of native yaw to account for its coordinate convention.
- Both volume cameras support screen-space pan without changing the document, mesh, slice, paint history or geometry revision. Native Shift-left, middle and right dragging pan; an explicit Pan button works in Orbit. Native scroll zoom and trackpad magnification respond proportionally. Browser Pan, modified mouse dragging and two-finger pan/pinch provide the equivalent controls.
- Zoom stays between 0.5 and 2 in both views. Fit restores the default matched pose (native yaw -0.6 / web yaw 0.6, pitch 0.35), zoom 1 and zero pan. The native CPU cube/ASCII projection, live GPU camera and picking all honor the same orbit and pan.
- Shared asymmetric fixture receipts compare camera bases and screen projections across native and browser views, including pole crossings, upside-down and panned cameras. Picking chooses the nearest cube after those movements and camera changes reuse geometry. Mac native regressions and browser Chromium/WebKit regressions cover the controls.
- Keep native painting, stroke freezing, CPU/export budgets and the browser one-draw cube mesh, colors, axes and bounded grid behavior. Keep app and viewer specifications and human intent synchronized. Sparse-world Explore, storage formats, parser APIs, package releases and trust policies remain outside this camera change.
