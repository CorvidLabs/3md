---
change: bring-sculpt-slice-editing-to-the-browser-with-a-visual-grid-drawing-tools-undo-and-live-3d-reference
artifact: research
---

# Native parity findings

- Sculpture.palette is #@*+ox:=- and Sculpture.empty is period (46). Native editing uses byte glyphs. Visual browser editing therefore accepts the native ASCII palette; other browser-readable glyphs remain available through source/preview.
- SculptureWorkspace.paint interpolates integer points using the same error-based line algorithm. Brush radius is size/2 clamped to 0...2, with square clipping to bounds. Fill is applied only at stroke start and ignores size. rememberStroke captures the pre-stroke snapshot lazily on the first actual change, so unchanged starts and no-ops behave correctly.
- Native undo/redo restore sculpture snapshots, clamp selection and clear redo on a new remembered edit. Native history retains 100 states. Browser history must also preserve exact source and coordinate with source typing, not rely on hidden-textarea programmatic writes that discard undo state.
- Native Show previous slice draws only behind empty current cells. The screenshot's 3D reference is the existing SculptureViewport at 170-point height, with Expand returning to the volume view.
- The browser currently reads the first code fence into gridOf, skips all-empty grids, treats dot/space/tab as empty and caps visual volume at 4000 occupied cells. The write adapter must distinguish safely editable complete rectangular native-compatible fences from readable-only content and must retain empty grids.
- Existing renderer geometry is cached per parsed document. Camera/selection updates reuse it. The small reference should reuse the same context, with actual source edits as the only new reason to rebuild geometry.

Structural actions need a separately defined source-coordinate policy before add/duplicate/remove can match native fixed-index layers. They follow this first authoring pass. No external engine/library is required to render this interface.
