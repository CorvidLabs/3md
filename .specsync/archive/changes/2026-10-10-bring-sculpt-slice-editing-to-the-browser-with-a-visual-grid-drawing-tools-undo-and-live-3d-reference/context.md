---
change: bring-sculpt-slice-editing-to-the-browser-with-a-visual-grid-drawing-tools-undo-and-live-3d-reference
artifact: context
---

# Context

Leif asked to keep making the browser as good as Sculpt.3md after showing the native Slice workspace and hearing the current camera/editor distinction. This definition ports the central slice-authoring loop. The current viewer and camera changes are archived in PR 93; the new feature is an unapproved definition, not a retroactive expansion of those records.

Sources of truth are SculptureEditor.sliceWorkspace/drawingTools, LayerGrid, SculptureWorkspace.paint/line/floodFill/undo/redo and Sculpture.palette. The screenshot shows a 9 by 7 scene with five slices, a teal selected cell and a small 3D reference. Native behavior is reused as the oracle through shared fixtures rather than reimplemented in the native app.

The page owns exact source, parsed document, active file/entry drafts and the single GPU stage. Native tests receive an additive fixture assertion in their existing workspace test file. Library, parser, bundles, format, releases and native editing behavior stay unchanged. X/Y/Z camera controls have a separate complete draft; neither definition is approved yet. Leif retains merge authority. Actual implementation/review actors are agent:codex, never a different agent or an independent human.
