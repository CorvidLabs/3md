---
spec: ThreeMDViewer.spec.md
---

## Key Decisions

- The page is its own module. `ThreeMD` stays the library. `ThreeMDElement` stays the text renderer. `ThreeMDCLI` stays the command.
- GitHub hosts are compared with `URL.hostname`. A substring match is not enough.
- The page fetches. The library stays free of filesystem and network I/O.

## Files to Read First

- `web/viewer.html`
- `web/open-document.ts`
- `web/github-source.ts`
- `web/gather.ts`
- `hi/tools.md` VIEWER-6

## Current Status

- The page behavior is on `0xleif/viewer/github-editor`.
- This spec records that behavior. Definition approval is recorded as `user:0xLeif`. Closing approval is still open.

## Notes

- Rebuild the page bundle with `bun build ./web/open-document.ts --outfile ./web/assets/open-document.js --format esm --target browser --minify`.
- Leave `web/assets/three-md.js` on the element build.
