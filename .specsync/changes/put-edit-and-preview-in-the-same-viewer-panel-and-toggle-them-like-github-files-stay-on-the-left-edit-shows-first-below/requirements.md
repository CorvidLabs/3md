---
change: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
artifact: requirements
---

# Requirements

- **REQ-ThreeMDViewer-003** The viewer page SHALL show Edit, Preview, and Cubes in one panel. Exactly one of them SHALL be visible. Cubes SHALL be the default, and the opening document SHALL be a small sculpture whose cubes are inside the window. Files SHALL stay in the column beside that panel. Below 900px, Files and the document SHALL take turns, and the document panel SHALL still switch Edit, Preview, and Cubes. Choosing Preview SHALL render the live plane view.
- **REQ-ThreeMDViewer-004** The viewer page SHALL NOT offer a render-mode switch and SHALL NOT autoplay. Preview SHALL stay on one plane. Cubes SHALL draw complete, nearly cell-sized cubes with WebGL2, lit glyph-colored fill at 0.5 opacity and visible glyph-colored edges. The selected Z slice SHALL have gold edges at 0.8 opacity while retaining its glyph fill. The background SHALL be rgb(0.065, 0.085, 0.10). X SHALL be the column, Y the text row with row 0 toward the top, and Z the plane index. Orbit, zoom, and slice selection SHALL reuse the installed geometry. Each redraw SHALL use one instanced draw. The element bundle SHALL stay a text renderer.

REQ-ThreeMDViewer-001 and REQ-ThreeMDViewer-002 stay. GitHub open, search, sections, pack, kind 2, hostname checks, and the text-only element stay.
