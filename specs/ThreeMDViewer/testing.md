---
spec: ThreeMDViewer.spec.md
---

## Automated Testing

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `web/gather.test.ts` | bun | Section planes, pack, kind 2 round-trip, line plane index, search rank. |
| `web/github-source.test.ts` | bun | Repo, folder, file, and raw locators. Host and path routing. Issues URL rejected. |
| `web/open-document.test.ts` | bun | Text, composition, kind 1, kind 2, LZFSE refusal, linked folder. |
| `uitests/viewer.spec.mjs` | Playwright | Edit and Preview share one panel, narrow Files and document switch, kind 2, linked village, catalog search, section jump, composition. |

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-001 | REQ-ThreeMDViewer-001 | VIEWER-6 in `hi/tools.md`. The page and the bun and Playwright tests above. |
| REQ-ThreeMDViewer-002 | REQ-ThreeMDViewer-002 | `web/github-source.ts` hostname checks, the 400 file and 1.5 MB caps, the 12,000 line cap in `web/viewer.html`, and the LZFSE test. |
| REQ-ThreeMDViewer-003 | REQ-ThreeMDViewer-003 | VIEWER-6 in `hi/tools.md`. Desktop and narrow layout tests in `uitests/viewer.spec.mjs`. |

## Manual Testing

- [ ] Open `viewer.html`. On a wide window, files stay on the left and Edit and Preview switch in the panel beside them. On a narrow window, Files and the document take turns.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| Host name only appears inside the path or query | The locator is rejected. |
| Tree contains `node_modules` or a file over 1.5 MB | Those files are skipped. |
| More than 400 text files, or more than 12,000 lines | The list stops at the cap and says so. |
| Apple LZFSE bytes | The page refuses them and names `compressionUnavailable`. |
| Desktop width | Files stay visible while Edit and Preview switch. Preview shows the live plane view. |
| Width at or below 900px | Files and the document take turns. The document still switches Edit and Preview. |
