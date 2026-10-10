---
spec: ThreeMDViewer.spec.md
---

## Key Decisions

- The page is its own module. `ThreeMD` stays the library. `ThreeMDElement` stays the text renderer. `ThreeMDCLI` stays the command.
- GitHub hosts are compared with `URL.hostname`. A substring match is not enough.
- The page fetches. The library stays free of filesystem and network I/O.
- Edit, Preview, and Cubes share one panel. Files stay on the left. Cubes is the default. Below 900px, Files and the document take turns. Choosing Preview calls `render` so the element measures the panel. The element still receives source while Edit is showing.

## Files to Read First

- `web/viewer.html`
- `web/open-document.ts`
- `web/github-source.ts`
- `web/gather.ts`
- `hi/tools.md` VIEWER-6

## Current Status

- PR 91 is on main. PR 92 shares Edit, Preview, and Cubes in one panel and adds Sculpt cube-stage parity plus the continuing UI and UX improvements.
- Leif approved the final viewer scope on 2026-10-10 and authorized acceptance and archiving after successful verification. Verification and closure are pending on PR 93; Leif retains merge authority.

## Notes

- This parity pass edits only the page renderer. Keep the existing element and open-document bundles. For a future change to the page bundle, rebuild with `bun build ./web/open-document.ts --outfile ./web/assets/open-document.js --format esm --target browser --minify`.
- Leave `web/assets/three-md.js` on the element build.

## Lessons

- The page shipped in PR 90 with VIEWER-6 before this module existed. `specsync check` on the library specs stayed green and still left `web/viewer.html` outside every spec file list. The page is its own module.
- A GitHub host check uses `URL.hostname`. The loader test's substring match of `raw.githubusercontent.com` was the CodeQL finding.
- Leif reviewed the change as `user:0xLeif` on 2026-10-10. It was finalized on the follow-up pull request after PR 90 had merged.
- Side-by-side source and live view left a narrow editor. Edit and Preview now share the panel and switch. The element still receives the source while Edit is showing, and Preview calls render so the plane view measures the panel.

- Cube geometry and neighbor visibility are cached per parsed document. Camera movement does no document scans; slice selection is a uniform. One draw combines lit 0.5 fill and antialiased glyph or gold edges. Shared interior faces are suppressed to retain translucency.
- Sculpt was run locally and its Character orb compared in both live stages. Native and web screenshots are in `docs/evidence/viewer-sculpt-parity/`. This is agent visual verification, not Leif’s review or definition approval.

- Leif directly requested continued UI and UX work on 2026-10-09. This covers the compact workspace and controls in the existing page scope; it does not record definition approval, human diff review, or a merge.
- The canvas occupies the space above the camera strip. Framing and picking use its actual client dimensions; changing view or viewport still does not resize an established WebGL bitmap.
- Export and conversion actions use a native disclosure with natural button focus, Escape dismissal, and outside-click closure. The source download shortcut preserves editor focus.

- PR 92 has merged. Leif requested a new fix PR for file navigation. Draft state belongs to the page and survives file and composition-entry switches within the current collection. It is not browser storage or a write to the source files. That follow-up was kept in draft until Leif's explicit 2026-10-10 scope approval.

- File activation focuses the document before restoring its caret. Chromium clears a restored selection when the editor remains blurred; focus-first restoration passes in both engines. Packing uses the current draft of the active document for each opened file, without rewriting composition profiles. The line index is reused until a draft or the collection changes.

- Linux WebKit exposed a delayed-render slice reset, native directory enumeration differences, and insufficient drawing space on a 320 by 740 phone. Source refresh now restores the selected slice, the file list sorts paths for consistent keyboard navigation, and narrow-screen padding leaves more stage space. The final verification runs are pending; existing phone and focus assertions remain, with an added wait across the editor debounce.

## Current camera parity

Leif explicitly approved full native/browser camera parity and verified closure on 2026-10-10. Both volume canvases now use full yaw/pitch turns, continuous pole bases, session-only screen pan, zoom 0.5...2 and the matched default Fit pose. Native interactive cameras use complete-volume framing while default utility cameras retain historical preview scale. Shared projection/picking fixtures and current screenshots are in `docs/evidence/viewer-camera/`. The X/Y/Z sphere and precise step controls have a separate complete draft; definition approval is pending.
