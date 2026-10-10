---
change: add-matching-x-y-z-axis-rotation-gizmos-and-precise-camera-steps-to-sculpt-and-the-viewer
artifact: testing
---

# Testing

Test each document axis with positive, negative and full-turn rotations, including Z roll and pole crossings. Compare native live, scalar and browser projected points and nearest cube hits. Assert inverse steps restore the same basis, invalid inputs do not mutate the camera, camera adjustments preserve document and geometry, and mobile and keyboard controls stay usable. Run the relevant native and Chromium/WebKit regressions and current trust gate after implementation.
