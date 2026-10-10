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

- [x] Give the stage more room, retain visible document identity, and group document actions.
- [x] Add Fit, zoom buttons, keyboard orbiting, and a scrolling slice row with keyboard navigation.
- [x] Offer Preview for prose and unavailable WebGL2, and recover GitHub controls after errors.

## Gaps

- The previous page contract shipped in PR 91.
- Leif approved the final scope and verified closure on 2026-10-10; supported scoped review and finalization archived the viewer and camera changes.
- The hosted page shows this layout after the branch merges.

## Review Sign-offs

- **Product**: previous page contract approved by user:0xLeif and shipped in PR 91. Leif approved the final layout and navigation scope on 2026-10-10 and authorized lifecycle closure after verification passes.
- **QA**: agent:codex current browser/native checks and visual observations; verified viewer and camera records archived. Scope approval does not claim independent human diff review.
- **Design**: n/a
- **Dev**: agent:codex implementation and scoped review; current automated verification passed.

- [x] Preserve file, linked-entry, invalid, and empty drafts with caret and selected plane across navigation.
- [x] Mark edits, filter files, navigate by keyboard, reveal phone documents, and avoid stale source queries.
- [x] Search and pack current drafts, and preserve the collection after a failed open.

- [x] Preserve the selected slice across delayed source refresh and sort file paths for consistent keyboard navigation.
- [x] Compact small-phone spacing without reducing existing assertions.

- [x] Match Sculpt and viewer full orbit through both poles with camera-only pan and proportional zoom.
- [x] Add shared asymmetric native/browser projection and picking fixtures.
- [x] Finish current cross-platform verification and lifecycle closure for the camera scope.
- [ ] Await definition approval for the separate axis gizmo and numeric precision controls.
