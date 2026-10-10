---
change: add-matching-x-y-z-axis-rotation-gizmos-and-precise-camera-steps-to-sculpt-and-the-viewer
artifact: design
---

# Design

Show a compact orientation sphere with red X, green Y and blue Z rings. Click a ring or its labeled axis button to constrain rotation. Free restores ordinary orbit. Degree-step minus/plus buttons rotate only the selected axis; directional buttons use the cell-valued pan step. The controls use native SwiftUI and browser SVG, fit the existing stage design and remain accessible by keyboard. Default steps are 15 degrees and 0.25 cells. Preserve browser controls below the drawing and compact phone layout.
