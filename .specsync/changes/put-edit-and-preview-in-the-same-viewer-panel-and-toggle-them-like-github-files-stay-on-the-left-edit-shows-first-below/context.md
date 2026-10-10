---
change: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
artifact: context
---

# Context

## What led here

The hosted page shipped in PR 90 and the ThreeMDViewer spec shipped in PR 91. That page showed files, source, and the live view side by side. Leif asked for Edit and Preview to share one panel and toggle, like GitHub's Write and Preview.

## What a later session needs

- Branch `0xleif/viewer/edit-preview` in `/Users/leif/Development/_CorvidLabs/3md-edit-preview`, based on `e18f35e`. Do not push to main. Do not merge.
- Files stay on the left. Edit and Preview share `.pane.stage`. Default is Edit. Below 900px, `.fileswitch` swaps Files and the document.
- Choosing Preview calls `lab.render()` so the element measures the panel. The element still receives source while Edit is showing.
- Cubes is a third state of that same panel. It reads the parsed planes and draws a fenced character grid as translucent cubes. The element bundle is not a voxel engine and is not rebuilt.
- The element bundle is not rebuilt. Do not bump versions or move tag `v2.2.1`.
- Definition approval is still open. Do not self-approve, finalize, or archive.
- Do not finalize the kind 2, GDScript, storage-ceiling, or 2.1 docs-coverage changes.
