---
change: keep-sculpt-and-web-cube-cameras-in-parity-with-unrestricted-orbit-and-screen-space-pan
artifact: design
---

# Design

Keep the current stage colors, glyph fills, edges and selected-slice gold. Orbit and Pan are camera tools in the existing control strip. Browser controls stay below the drawing and keep phone touch targets usable. Native Shift, middle and right dragging provide pan even while Paint is selected; such gestures must never paint. A native Pan toggle applies to the Orbit canvas. Use native local points and browser CSS pixels. Both cameras use 0.008 radians per drag point, zoom 0.5 through 2, and default pitch 0.35. Native yaw -0.6 maps to browser yaw +0.6. Native ASCII and exports follow the same session camera.
