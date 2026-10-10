# Lesson bundle — cover-the-github-style-viewer-page-in-the-spec-the-page-is-files-source-and-the-live-plane-view-it-opens-a-public

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Cover the GitHub-style viewer page in the spec. The page is files, source, and the live plane view. It opens a public GitHub repo, folder, or file, or a local file or folder. Search reads every line and opens that plane. Markdown headings become planes. Opened files pack into one text document and download as uncompressed kind 2. The three-md element stays a text renderer.
- **Kind**: Feature
- **Specs**: ThreeMDViewer
- **Paths**: web/viewer.html, web/gather.ts, web/github-source.ts, web/open-document.ts, web/assets/open-document.js, hi/tools.md, uitests/viewer.spec.mjs
- **Acceptance**: The spec states files, source, and live view; a public GitHub repo, folder, or file; a local file or folder; every-line search that opens that plane; section planes; pack; kind 2 download; and the element stays a text renderer. Evidence is the existing bun tests and the Playwright viewer spec.

## Evidence

- Verification commit: `418acbc17c43b7fac48a16b22e1a195e077b6a81`
- Base commit: `84307639c2f24f6a23418a2b712f52a1d5b37551`
- Verified by: `specsync check --spec ThreeMDViewer`

## From the change's context.md

# Context

## What led here

PR 90 (`0xleif/viewer/github-editor`, head `8430763`) already implements the GitHub-style viewer. The page is files, source, and the live plane view. It opens a public GitHub repo, folder, or file, or a local file or folder. Search reads every opened line and opens that plane. Markdown headings become planes. Opened files pack into one text document and download as uncompressed kind 2. `hi/tools.md` records that as VIEWER-6.

The page files are outside every current spec file list. `ThreeMD` is the library. `ThreeMDCLI` is the command. `ThreeMDElement` is the `<three-md>` text renderer. `specsync check` passed on those unchanged specs and did not cover the page. On 2026-10-09 Leif said every 3md change, including the viewer, always has both hi and a SpecSync change.

## What a later session needs

- The page code is already on this branch. This change adds the `ThreeMDViewer` module around it. Do not rewrite the parsers, the CLI, or the element.
- The element stays a text renderer. Decode, composition, linked folders, GitHub fetch, search, sections, pack, and kind 2 download stay in the page.
- The library has no filesystem or network I/O. The page does the fetch.
- GitHub locators are checked by hostname: `github.com`, `www.github.com`, and `raw.githubusercontent.com`. A host string sitting elsewhere in the URL is not a match. CodeQL `js/incomplete-url-substring-sanitization` on the test mock is fixed in `8430763`.
- Public loads skip `node_modules`, keep at most 400 files, and skip a file larger than 1.5 MB. The line index keeps at most 12,000 rows. Apple LZFSE is refused.
- Definition approval is still open. Do not self-approve, accept, or archive.
- Do not bump package versions, move tag `v2.2.1`, or publish.

## From the change's design.md

# Design

The page is one screen with three columns: files, source, and the live `<three-md>` view. A point field accepts a public GitHub repo, folder, or file. Open file, open folder, and drop read local bytes.

Below 900px the columns become Files, Source, and Live tabs. Source is the default tab. Live hides the editor. Files shows the file list.

Search reads the line index, then the catalog and the open document. A hit names the file, the plane, and the line. Choosing it opens that plane.

The element scrubs Z. It does not fetch, decode `.3mdb`, or resolve linked files. Those steps happen in the page before the text reaches the element.

Kind 2 download writes the current source with the library's uncompressed kind 2 encoder and saves that byte array. Apple LZFSE is not offered.

## From the change's testing.md

# Testing

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-001 | REQ-ThreeMDViewer-001 | `hi/tools.md` VIEWER-6. `web/viewer.html` lays out files, source, and the live view, and calls `loadGitHubPoint`, `indexLines`, `sectionsToDocument`, `packDocuments`, and `kind2Bytes`. `web/gather.test.ts` covers section planes, pack, kind 2, line hits, and search rank. `web/open-document.test.ts` covers text, composition, kind 2, LZFSE refusal, and a linked folder. `uitests/viewer.spec.mjs` covers the three panes, narrow Source and Live, kind 2, the linked village, catalog search, section jump, and composition. |
| REQ-ThreeMDViewer-002 | REQ-ThreeMDViewer-002 | `web/github-source.ts` compares `hostname` with `github.com`, `www.github.com`, and `raw.githubusercontent.com`, caps a tree at 400 files and 1.5 MB, and skips `node_modules`. `web/github-source.test.ts` parses repo, folder, file, and raw URLs, rejects an issues URL, and routes the mock by hostname and pathname. `web/viewer.html` caps `lineIndex` at 12,000. `web/open-document.test.ts` expects `compressionUnavailable` for Apple LZFSE. |

- `bun test web/github-source.test.ts web/gather.test.ts web/open-document.test.ts` passed on this branch after the hostname fix: 15 tests, 65 expects.
- `hi check` on this branch reported 85 criteria, 12 families, 10 files, and no problems, before this change record.
- Playwright `uitests/viewer.spec.mjs` passed 7 tests on the page commit `301766a`. This spec record does not change page behavior.

## Where these lessons go

- `specs/ThreeMDViewer/context.md`
