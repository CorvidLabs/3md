# ThreeMDViewer delta

## MODIFIED

### REQUIREMENT REQ-ThreeMDViewer-004

The viewer page SHALL NOT offer a render-mode switch and SHALL NOT autoplay. Preview SHALL stay on one plane. Cubes SHALL draw complete, nearly cell-sized cubes with WebGL2, lit glyph-colored fill at 0.5 opacity and visible glyph-colored edges. The selected Z slice SHALL have gold edges at 0.8 opacity while retaining its glyph fill. The background SHALL be rgb(0.065, 0.085, 0.10). X SHALL be the column, Y the text row with row 0 toward the top, and Z the plane index. Orbit, zoom, and slice selection SHALL reuse the installed geometry. Each redraw SHALL use one instanced draw. Orbit SHALL rotate through full horizontal and vertical turns with a continuous camera basis at the poles. Pan mode, Shift-drag, and middle/right-drag SHALL move the view in screen space. Shift-arrow keys SHALL pan the focused canvas. Two-finger touch gestures SHALL pan and pinch to zoom. Wheel zoom SHALL respond proportionally to the gesture. Fit SHALL restore yaw 0.6, pitch 0.35, zoom 1, and zero pan without changing source or the selected slice. Camera buttons and the focused canvas SHALL support bounded zoom, and arrow keys SHALL orbit the focused canvas. Camera controls SHALL sit below the drawing without covering cubes. A document without a cube grid and an unavailable WebGL2 context SHALL offer Preview while preserving the source. The element bundle SHALL stay a text renderer.

Acceptance Criteria:

- The page has no render-mode menu and no page play control. A frame-axis document is not playing.
- A fenced grid draws on WebGL2, including about 1400 cubes. A single cell has filled faces from every side. Selection changes edge color while the face interior keeps its glyph color. Camera, zoom, and selection redraw without geometry uploads. Click picking selects the nearest visible cube’s Z slice.
- X is the column, Y is the text row with row 0 toward the top, and Z is the plane index. Space, dot, and tab are empty. Keep the 64 by 64 per-plane and 4000-cell caps.
- Evidence is VIEWER-6 and the cube tests in `uitests/viewer.spec.mjs`.
- The same 3D context and geometry remain installed when moving between Cubes and the Slice reference or changing display size. The drawable follows the visible pane size and device pixel ratio, bounded to 2x and a proportional 2048-pixel edge cap; unchanged sizes avoid bitmap reallocations. Small-to-large, phone/desktop and Retina transitions remain sharp without changing source, camera, slice or nearest picking.
