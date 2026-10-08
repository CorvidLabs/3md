# Explore a Sculpt world

The world sheet opens with an Orbit overview when its placements fit the view range. Use Whole World to return to it. Drag to orbit and scroll to zoom.

Choose Explore, then click the canvas. Hold W/S to move forward/back, A/D to move sideways, and Q/E to move down/up. Drag to look around. Shift moves four times faster. Escape releases movement focus. The movement buttons provide the same directions without keyboard focus. Visit jumps to the first placement of a model type, such as a castle, forest or floating island. Its starting eye is 32 cells across, 20 cells down and 96 cells in front of that placement, facing negative Z. WASD travel stays horizontal even when you look up or down.

This is free exploration of an editor scene. There is no gravity, collision, jumping, gameplay or automatic terrain following. You can move through solid models. Navigation stops when the canvas loses keyboard focus or its window closes. The camera and navigation pose are session state, preserving saved files and editing history.

Skyreach is a storage and rendering case study across a 1024 by 1024 by 1024 address domain. It has 280 placements from eight reusable chunk models, with 28,057,022 occupied cells. The address-domain size does not imply that every cell is occupied or that every building is unique. The separate solid case represents a billion occupied cells through 4096 shared placements. Both retain 256-cell editing bounds per model.

Nearby models use detailed shared geometry. Distant models use colored coarse silhouettes with bounded resolution. Bounds represent empty models or provide a fallback when preparation or rendering budgets are exhausted. The status shows visible, detailed, simplified, bounds, culled and capacity-omitted placements. Rendering remains limited to 512 visible instances and 500,000 faces, with 1,000,000 prepared faces across the shared model cache. When visible coarse models fit, their capacity is reserved before nearby models receive detailed upgrades. Orbit retains close-up cell edges; Explore hides those edges. An overview cannot show every instance of a world exceeding those caps or fit an arbitrarily distant Int64 span. Int64 positions do not allocate the empty space between models.

Tests, actual native interaction and screenshots are recorded separately under docs/evidence/world-exploration. They do not establish on-screen FPS. The direct file-reference composition request remains separate from this navigation work.
