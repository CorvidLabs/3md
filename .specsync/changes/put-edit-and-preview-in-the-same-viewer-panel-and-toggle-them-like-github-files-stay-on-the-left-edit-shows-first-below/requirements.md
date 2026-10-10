---
change: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
artifact: requirements
---

# Requirements

- **REQ-ThreeMDViewer-003** The viewer page SHALL show Edit, Preview, and Cubes in one panel. Exactly one of them SHALL be visible. Cubes SHALL be the default, and the opening document SHALL be a small sculpture whose cubes are inside the window. Files SHALL stay in the column beside that panel. Below 900px, Files and the document SHALL take turns, and the document panel SHALL still switch Edit, Preview, and Cubes. Choosing Preview SHALL render the live plane view.
- **REQ-ThreeMDViewer-004** The viewer page SHALL NOT offer a render-mode switch and SHALL NOT autoplay. Preview SHALL stay on one plane. Cubes SHALL draw a fenced character grid as lit cubes with WebGL2. Orbit and zoom SHALL move the camera. The element bundle SHALL stay a text renderer.

REQ-ThreeMDViewer-001 and REQ-ThreeMDViewer-002 stay. GitHub open, search, sections, pack, kind 2, hostname checks, and the text-only element stay.
