---
hi: 1
families: [WORLD]
---

# World

## Intent

I want to place reusable models in a sparse world without a fixed cube or empty space stored between them, and I want exact distant positions to survive save and reopen.

I want to explore with WASD and drag-to-look, then return to Orbit, while large maps stay responsive and a 1024 case study measures a real dense buffer without changing the editing limits of one model.

## Criteria

- **WORLD-31**  I can place reusable models in a sparse world without a fixed cube boundary or allocating empty space between them. Exact distant positions survive save/reopen. A render-distance control shows nearby models in detail, farther models as simple bounds, and preserves hidden placements outside the view. I can move the viewing focus, select/place/remove/rotate instances and undo placement edits while individual editable models remain bounded.
- **WORLD-33**  Large maps prepare without blocking my editor, reuse geometry while I move the camera or arrange world instances, and keep precise cell editing while showing only the visible slice region. Animation exports reuse prepared geometry; optimization is measured and checked against unchanged cells, colors and picking.
- **WORLD-36**  I want a reproducible 1024 by 1024 by 1024 case study that measures a real dense buffer and reusable worlds, with honest storage, loading, memory and Metal rendering results. I can inspect the landscape in Sculpt while its individual editing limits stay unchanged.
- **WORLD-37**  I can explore a world with WASD, drag to look, and move up or down, then return to an Orbit overview. Clear controls show how to move; distant terrain keeps a recognizable colored shape. Moving the camera keeps my saved models, exact positions and editing history unchanged.
