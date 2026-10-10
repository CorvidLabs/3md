---
spec: ThreeMDViewer.spec.md
---

## Tasks

- [x] Present files, source, and the live plane view.
- [x] Show Edit and Preview in one panel, with Cubes first. Below 900px, Files and the document take turns.
- [x] Open a public GitHub repo, folder, or file, or a local file or folder.
- [x] Search every opened line and open that plane.
- [x] Turn Markdown headings into planes, pack files, and download uncompressed kind 2.
- [x] Keep the element a text renderer and refuse Apple LZFSE.
- [x] Match GitHub hosts by hostname.
- [x] Record the contract in this spec and in VIEWER-6.
- [x] Hold Preview on one plane, with no render-mode switch and no autoplay.
- [x] Draw fenced grids as lit WebGL2 cubes.

- [x] Match Sculpt glyph fill, gold selected-slice edges, background, and document axes.
- [x] Keep full cubes framed in the pane and pick the nearest cube’s Z slice.
- [x] Reuse geometry on orbit, zoom, and selection, with one instanced draw.

## Gaps

- The previous page contract shipped in PR 91.
- Definition approval for the shared Edit and Preview panel is still open.
- The hosted page shows this layout after the branch merges.

## Review Sign-offs

- **Product**: previous page contract approved by user:0xLeif and shipped in PR 91. This layout change is not approved yet.
- **QA**: agent:codex local browser and visual verification; human review pending
- **Design**: n/a
- **Dev**: pending
