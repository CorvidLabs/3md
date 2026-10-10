# Viewer and Sculpt cube comparison

On 2026-10-09, agent:codex ran `/usr/bin/swift run Rook` from this worktree and inspected the live Cubes stage. Character orb was opened in both applications, slice 9 was selected, and the native stage was orbited. The same 122-cell starter geometry was also compared with slice 2 selected. Both stages were captured; web captures followed a refresh of the local page at `http://127.0.0.1:8234/viewer.html`.

The native starter comparison was a temporary copy with Sculpt’s required `axis: space`, `scene-schema: ascii-sculpture-1`, width/height 8, and `ascii` fence labels. Its grid cells and plane order match the viewer starter. The viewer source and existing fixtures were not migrated.

- `sculpt-orb.jpg` and `web-orb.jpg`: Character orb, 608 occupied cells, slice 9.
- `web-1600.jpg`: real pointer orbit, wheel zoom, and click-to-pick on 1600 cubes; the click changed the selected Z slice from 3 to 0 with no warning or error logs.
- `sculpt-starter.jpg` and `web-starter.jpg`: starter geometry, 122 occupied cells, slice 2.

The web stage keeps all six outward-wound faces in one nearly cell-sized cube mesh and culls back faces. Shared interior faces are suppressed, as in Sculpt’s exterior-surface extraction. Lit fill retains glyph colors. Browser fill is 0.5 and glyph edges are 0.4 for visible presence under web blending; native Sculpt fill defaults to 0.35. Selected edges use gold rgb(1, 0.79, 0.44) at 0.8 without changing glyph fill. The background and document axes match. The native and browser compositors are different; these are visual comparisons, not a claim of identical pixels.

The page installs geometry once per parsed document. Orbit, zoom, and selected-slice changes reuse those buffers and use one instanced draw per redraw. Picking intersects cube bounds and chooses the nearest hit. Camera scale and distance follow Sculpt with a fit margin for the pane.

Verification includes the full Chromium and WebKit `uitests/viewer.spec.mjs` suite (70 passed), actual GPU pixel reads for single-cell faces from six viewpoints and edge-only selection, the opening lit-cube and console checks, and a 1600-cell camera test requiring zero geometry uploads and one draw per redraw. SpecSync’s strict viewer check, `hi check`, and the element bundle drift/size check pass. The pinned Trust gate runs after the feature commit and push; its final result is recorded on PR 92.

The input caps remain 64 by 64 per plane and 4000 occupied cells. Painting/erasing into source, 256 cubed volumes, sparse worlds, OBJ export, and Sculpt source changes are out of scope. The existing SpecSync change remains an unapproved draft. This agent evidence is not Leif’s diff review, an independent human review, an approval, or a signature.
