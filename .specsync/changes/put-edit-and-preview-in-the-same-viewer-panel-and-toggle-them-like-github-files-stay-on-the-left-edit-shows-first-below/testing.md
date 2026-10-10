---
change: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
artifact: testing
---

# Testing

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-003 | REQ-ThreeMDViewer-003 | VIEWER-6 in `hi/tools.md`. `web/viewer.html` switches Edit and Preview in one panel and calls `render` for Preview. `uitests/viewer.spec.mjs` covers the desktop switch and the narrow Files and document switch. |
| REQ-ThreeMDViewer-004 | REQ-ThreeMDViewer-004 | VIEWER-6 in `hi/tools.md`. `web/viewer.html` holds the element on `mode="single"`, removes the render-mode menu and the play control, and draws cubes with WebGL2. `uitests/viewer.spec.mjs` covers no autoplay and about 1400 cubes. |

- `specsync check --spec ThreeMDViewer`
- `hi check` at the repository root
- Playwright `uitests/viewer.spec.mjs` passed 60 tests on Chromium and WebKit after the outline chip opens Preview first. The desktop and narrow layout tests passed again after the bar metadata hide.
