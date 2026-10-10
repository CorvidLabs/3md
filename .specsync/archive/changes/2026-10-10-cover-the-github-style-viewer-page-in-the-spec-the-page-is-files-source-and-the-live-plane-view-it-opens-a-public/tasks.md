---
change: cover-the-github-style-viewer-page-in-the-spec-the-page-is-files-source-and-the-live-plane-view-it-opens-a-public
artifact: tasks
---

# Tasks

Implementation of the page is already on this branch. These tasks add the spec around it.

- [x] Record VIEWER-6 in `hi/tools.md`.
- [x] Keep the element a text renderer and keep network I/O out of the library.
- [x] Check GitHub hosts by hostname in the loader and in the loader test.
- [x] After definition approval, scaffold `specs/ThreeMDViewer/` from `deltas/ThreeMDViewer.md`.
- [x] List the page files in that spec.
- [x] Run `specsync check --spec ThreeMDViewer` and `hi check`. `specsync check` passed 4 specs, with ThreeMDViewer at 20/20 exports. `hi check` reported 85 criteria and no problems.
