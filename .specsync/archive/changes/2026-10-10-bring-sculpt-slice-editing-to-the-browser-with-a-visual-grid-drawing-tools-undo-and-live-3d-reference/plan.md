---
change: bring-sculpt-slice-editing-to-the-browser-with-a-visual-grid-drawing-tools-undo-and-live-3d-reference
artifact: plan
---

# Plan

1. Obtain definition approval, then start this change through SpecSync 6. Record the actual approval without claiming a reviewed diff or a signature.
2. Add an eligibility/source-span adapter in the page. Cache rectangular grids and exact character offsets by source revision. All mutations are reversible source transactions; unsupported content remains readable through the existing views.
3. Implement shared stroke interpolation, clipped brushes and four-neighbor fill. Establish coherent per-draft history across typing and grid edits, including linked entry/file state. Bound history memory, reject over-budget transactions atomically and end strokes before navigation/export.
4. Add the Slice view with thumbnails, grid canvas, selected-cell controls, zoom/scroll, previous-slice overlay and native-style tools. Reparent the existing GPU canvas for the small reference and Expand; preserve camera, bitmap/context and geometry on view-only changes. Coalesce live-reference source updates per animation frame and flush pending edits before navigation or export.
5. Add independently specified edit fixtures and run the actual native workspace and browser interactions against them. Extend source, file/history, phone, pointer-cancel and GPU-unavailable regressions.
6. Update canonical viewer requirements, purpose, bounded-editing exclusions, companions and VIEWER-6 to describe the implemented feature. Run current browser/native selections, strict root/native specs, intent checks and pinned Trust. Record actual provenance under unchanged policy.
7. Present evidence and use supported scoped review/finalization only under explicit verified-closure approval. Update the feature PR with the resulting behavior and exact validation; Leif merges it.

Structural slice actions, volume resizing, direct 3D paint and export-format expansion follow this central editing loop in later definitions. Axis gizmo work may proceed separately only when its existing definition is approved.
