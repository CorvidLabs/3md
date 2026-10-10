---
change: cover-the-github-style-viewer-page-in-the-spec-the-page-is-files-source-and-the-live-plane-view-it-opens-a-public
artifact: testing
---

# Testing

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-001 | REQ-ThreeMDViewer-001 | `hi/tools.md` VIEWER-6. `web/viewer.html` lays out files, source, and the live view, and calls `loadGitHubPoint`, `indexLines`, `sectionsToDocument`, `packDocuments`, and `kind2Bytes`. `web/gather.test.ts` covers section planes, pack, kind 2, line hits, and search rank. `web/open-document.test.ts` covers text, composition, kind 2, LZFSE refusal, and a linked folder. `uitests/viewer.spec.mjs` covers the three panes, narrow Source and Live, kind 2, the linked village, catalog search, section jump, and composition. |
| REQ-ThreeMDViewer-002 | REQ-ThreeMDViewer-002 | `web/github-source.ts` compares `hostname` with `github.com`, `www.github.com`, and `raw.githubusercontent.com`, caps a tree at 400 files and 1.5 MB, and skips `node_modules`. `web/github-source.test.ts` parses repo, folder, file, and raw URLs, rejects an issues URL, and routes the mock by hostname and pathname. `web/viewer.html` caps `lineIndex` at 12,000. `web/open-document.test.ts` expects `compressionUnavailable` for Apple LZFSE. |

- `bun test web/github-source.test.ts web/gather.test.ts web/open-document.test.ts` passed on this branch after the hostname fix: 15 tests, 65 expects.
- `hi check` on this branch reported 85 criteria, 12 families, 10 files, and no problems, before this change record.
- Playwright `uitests/viewer.spec.mjs` passed 7 tests on the page commit `301766a`. This spec record does not change page behavior.
