# Edit and Preview share one panel

## ADDED

### REQUIREMENT REQ-ThreeMDViewer-003

The viewer page SHALL show Edit, Preview, and Cubes in one panel. Exactly one of them SHALL be visible. Cubes SHALL be the default, and the opening document SHALL be a small sculpture whose cubes are inside the window. Files SHALL stay in the column beside that panel. Below 900px, Files and the document SHALL take turns, and the document panel SHALL still switch Edit, Preview, and Cubes. Choosing Preview SHALL render the live plane view.

Acceptance Criteria:

- At a desktop width, files stay visible. Cubes shows first, and the lit cubes are inside the window. Edit shows the editor and hides the cubes. Preview shows the live plane view and hides the editor.
- At 800px, Files and the document take turns. The document panel still switches Edit, Preview, and Cubes.
- Evidence is VIEWER-6 and the layout tests in `uitests/viewer.spec.mjs`.

### REQUIREMENT REQ-ThreeMDViewer-004

The viewer page SHALL NOT offer a render-mode switch and SHALL NOT autoplay. Preview SHALL stay on one plane. Cubes SHALL draw complete, nearly cell-sized cubes with WebGL2, lit glyph-colored fill at 0.5 opacity and visible glyph-colored edges. The selected Z slice SHALL have gold edges at 0.8 opacity while retaining its glyph fill. The background SHALL be rgb(0.065, 0.085, 0.10). X SHALL be the column, Y the text row with row 0 toward the top, and Z the plane index. Orbit, zoom, and slice selection SHALL reuse the installed geometry. Each redraw SHALL use one instanced draw. The element bundle SHALL stay a text renderer.

Acceptance Criteria:

- The page has no render-mode menu and no page play control. A frame-axis document is not playing.
- A fenced grid draws on WebGL2, including a volume of about 1400 cubes.
- Evidence is VIEWER-6 and the cube tests in `uitests/viewer.spec.mjs`.
