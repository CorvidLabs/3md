---
change: add-matching-x-y-z-axis-rotation-gizmos-and-precise-camera-steps-to-sculpt-and-the-viewer
artifact: research
---

# Research

Native document coordinates map X to horizontal, Y to downward grid rows and Z to plane depth. Native render Y is inverted, and native yaw is the negative of browser yaw for the same pose. Existing two-angle cameras cannot represent independent document-Z rotation, so a third session-only angle and orthonormal basis are needed. Use explicit document-axis rotation to avoid relabeling camera yaw/pitch as world axes. Storage codecs never encode camera state.
