# Edit and Preview share one panel

## ADDED

### REQUIREMENT REQ-ThreeMDViewer-003

The viewer page SHALL show Edit, Preview, and Cubes in one panel. Exactly one of them SHALL be visible. Cubes SHALL be the default, and the opening document SHALL be a small sculpture whose cubes are inside the window. Files SHALL stay in the column beside that panel. Below 900px, Files and the document SHALL take turns, and the document panel SHALL still switch Edit, Preview, and Cubes. Choosing Preview SHALL render the live plane view. The workspace SHALL keep infrequent export and conversion actions in the Document disclosure, show insert tools only in Edit, and show the document title in every view. Tabs and the single-row plane outline SHALL provide one tab stop per group, with arrow, Home, and End navigation. File and composition-entry navigation SHALL preserve current edits, caret, and selected plane within the open collection. Edited documents SHALL be identified in every view. Opened files SHALL support filtering and keyboard navigation. Choosing a file or search result on a narrow screen SHALL reveal the document. Search and packing SHALL use current drafts. Failed local opens SHALL preserve the current collection. Explicit document navigation SHALL replace a stale source query with the current document hash.

Acceptance Criteria:

- At a desktop width, files stay visible. Cubes shows first, and the lit cubes are inside the window. Edit shows the editor and hides the cubes. Preview shows the live plane view and hides the editor.
- At 800px, Files and the document take turns. The document panel still switches Edit, Preview, and Cubes.
- Evidence is VIEWER-6 and the layout tests in `uitests/viewer.spec.mjs`.

### REQUIREMENT REQ-ThreeMDViewer-004

The viewer page SHALL NOT offer a render-mode switch and SHALL NOT autoplay. Preview SHALL stay on one plane. Cubes SHALL draw complete, nearly cell-sized cubes with WebGL2, lit glyph-colored fill at 0.5 opacity and visible glyph-colored edges. The selected Z slice SHALL have gold edges at 0.8 opacity while retaining its glyph fill. The background SHALL be rgb(0.065, 0.085, 0.10). X SHALL be the column, Y the text row with row 0 toward the top, and Z the plane index. Orbit, zoom, and slice selection SHALL reuse the installed geometry. Each redraw SHALL use one instanced draw. Fit SHALL restore yaw 0.6, pitch 0.35, and zoom 1 without changing source or the selected slice. Camera buttons and the focused canvas SHALL support bounded zoom, and arrow keys SHALL orbit the focused canvas. Camera controls SHALL sit below the drawing without covering cubes. A document without a cube grid and an unavailable WebGL2 context SHALL offer Preview while preserving the source. The element bundle SHALL stay a text renderer.

Acceptance Criteria:

- The page has no render-mode menu and no page play control. A frame-axis document is not playing.
- A fenced grid draws on WebGL2, including a volume of about 1400 cubes.
- Evidence is VIEWER-6 and the cube tests in `uitests/viewer.spec.mjs`.
