---
spec: ThreeMDViewer.spec.md
---

## Key Decisions

- The page is its own module. `ThreeMD` stays the library. `ThreeMDElement` stays the text renderer. `ThreeMDCLI` stays the command.
- GitHub hosts are compared with `URL.hostname`. A substring match is not enough.
- The page fetches. The library stays free of filesystem and network I/O.
- Edit and Preview share one panel. Files stay on the left. Edit is the default. Below 900px, Files and the document take turns. Choosing Preview calls `render` so the element measures the panel. The element still receives source while Edit is showing.

## Files to Read First

- `web/viewer.html`
- `web/open-document.ts`
- `web/github-source.ts`
- `web/gather.ts`
- `hi/tools.md` VIEWER-6

## Current Status

- PR 91 is on main. This branch puts Edit and Preview in one panel.
- Definition approval for this layout change is not recorded yet.

## Notes

- Rebuild the page bundle with `bun build ./web/open-document.ts --outfile ./web/assets/open-document.js --format esm --target browser --minify`.
- Leave `web/assets/three-md.js` on the element build.

## Lessons

- The page shipped in PR 90 with VIEWER-6 before this module existed. `specsync check` on the library specs stayed green and still left `web/viewer.html` outside every spec file list. The page is its own module.
- A GitHub host check uses `URL.hostname`. The loader test's substring match of `raw.githubusercontent.com` was the CodeQL finding.
- Leif reviewed the change as `user:0xLeif` on 2026-10-10. It was finalized on the follow-up pull request after PR 90 had merged.
- Side-by-side source and live view left a narrow editor. Edit and Preview now share the panel and switch. The element still receives the source while Edit is showing, and Preview calls render so the plane view measures the panel.
