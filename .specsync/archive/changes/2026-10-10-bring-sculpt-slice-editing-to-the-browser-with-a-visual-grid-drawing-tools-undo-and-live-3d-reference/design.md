---
change: bring-sculpt-slice-editing-to-the-browser-with-a-visual-grid-drawing-tools-undo-and-live-3d-reference
artifact: design
---

# Slice workspace design

Use the supplied Sculpt screenshot as the visual reference and the current CorvidLabs tokens as the browser identity. The main hierarchy is document title, view selector, Slice canvas and tools. The editable grid gets the largest area; the small reference answers where the selected slice sits in the volume. No new page theme or decorative cards.

Color uses existing paper/ink/surface/hairline/accent tokens, with the fixed cube background #11161a, teal cell selection near #39cbbb, quieter previous-layer glyphs and gold selected-slice cube edges #ffca70. Schibsted Grotesk remains the UI face; Spline Sans Mono serves grid glyphs and source. Browser light/dark themes remain supported.

Desktop arrangement inside the existing document panel:

```text
Document title                         Edited
Edit   Preview   Cubes   Slice
Slices          Slice 1           X 7  Y 4
[thumb] 1       Fit  2x 4x 8x 16x    3D reference  Expand
[thumb] 2       +----------------+    [current GPU stage]
[thumb] 3       | editable cells |    Draw  Erase  Fill
[thumb] 4       |                |    # @ * + o x : = -
[thumb] 5       +----------------+    Size  1  3  5
9 x 7 cells     Show previous slice   Selected cell / Apply
                 keyboard hint       Undo  Redo
```

Files remain the existing outer navigation. Slice thumbnails are compact inner navigation; on phones they become a horizontal scroll strip. The reference and tools flow below the grid at narrow widths, with the reference collapsible so it does not crowd drawing. Grid zoom scrolls inside the editor; it never widens the page. Tools keep large touch targets, pressed state and visible focus. One grid focus target plus coordinate controls avoids thousands of cell tab stops.

The subject-specific decision is the glyph grid beside its volumetric context. Review against the screenshot: no hero content, new gradients, overlaid toolbars or generic dashboard cards. Expand moves the same GPU view back to Cubes; edits and camera are preserved.
