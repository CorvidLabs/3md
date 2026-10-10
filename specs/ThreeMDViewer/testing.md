---
spec: ThreeMDViewer.spec.md
---

## Automated Testing

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `web/gather.test.ts` | bun | Section planes, pack, kind 2 round-trip, line plane index, search rank. |
| `web/github-source.test.ts` | bun | Repo, folder, file, and raw locators. Host and path routing. Issues URL rejected. |
| `web/open-document.test.ts` | bun | Text, composition, kind 1, kind 2, LZFSE refusal, linked folder. |
| `uitests/viewer.spec.mjs` | Playwright | Three panes, narrow Source and Live, kind 2, linked village, catalog search, section jump, composition. |

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-001 | REQ-ThreeMDViewer-001 | VIEWER-6 in `hi/tools.md`. The page and the bun and Playwright tests above. |
| REQ-ThreeMDViewer-002 | REQ-ThreeMDViewer-002 | `web/github-source.ts` hostname checks, the 400 file and 1.5 MB caps, the 12,000 line cap in `web/viewer.html`, and the LZFSE test. |

## Manual Testing

- [ ] Open `viewer.html`, point it at `github.com/CorvidLabs/3md`, and confirm the file list, the source, and the live view.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| Host name only appears inside the path or query | The locator is rejected. |
| Tree contains `node_modules` or a file over 1.5 MB | Those files are skipped. |
| More than 400 text files, or more than 12,000 lines | The list stops at the cap and says so. |
| Apple LZFSE bytes | The page refuses them and names `compressionUnavailable`. |
