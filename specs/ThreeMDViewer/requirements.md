---
spec: ThreeMDViewer.spec.md
---

## User Stories

- As a reader, I want files, source, and the live plane view together.
- As a reader, I want to point the page at a public GitHub repo, folder, or file, or at a file or folder on this computer.
- As a reader, I want search to read every line and open that plane.

## Acceptance Criteria

- **REQ-ThreeMDViewer-001** The viewer page SHALL present files, source, and the live plane view. It SHALL open a public GitHub repo, folder, or file, or a file or folder from this computer. Search SHALL read every opened line and open that plane. Markdown headings SHALL become planes. Opened files SHALL pack into one text document, and that document SHALL download as uncompressed kind 2. The `<three-md>` element SHALL stay a text renderer.
- **REQ-ThreeMDViewer-002** The page SHALL accept a GitHub locator only when the host is `github.com`, `www.github.com`, or `raw.githubusercontent.com`, or when the input is an `owner/repo` name. It SHALL NOT treat those names as a match when they appear only as a substring. A public load SHALL skip `node_modules`, SHALL keep at most 400 files, and SHALL skip a file larger than 1.5 MB. The line index SHALL keep at most 12,000 rows. Apple LZFSE SHALL be refused. The ThreeMD library SHALL stay free of filesystem and network I/O.

## Constraints

- The element bundle stays text-only and is not rebuilt for this page.
- Package versions stay 2.2.1. Tag `v2.2.1` stays where it is.
- The page fetches public GitHub only. The library does the parse and the kind 2 encode.

## Out of Scope

- Parser, CLI, and element behavior.
- Gallery cards, which stay the curated text set.
- Private GitHub repos, remote folder indexes beyond the public git tree, and Apple LZFSE.

### REQ-ThreeMDViewer-001

The viewer page SHALL present files, source, and the live plane view. It SHALL open a public GitHub repo, folder, or file, or a file or folder from this computer. Search SHALL read every opened line and open that plane. Markdown headings SHALL become planes. Opened files SHALL pack into one text document, and that document SHALL download as uncompressed kind 2. The `<three-md>` element SHALL stay a text renderer.

Acceptance Criteria:

- The spec states the three panes, GitHub and local open, every-line search, section planes, pack, kind 2 download, and the text-only element.
- Evidence is VIEWER-6, the bun tests in `web/gather.test.ts` and `web/open-document.test.ts`, and `uitests/viewer.spec.mjs`.

### REQ-ThreeMDViewer-002

The page SHALL accept a GitHub locator only when the host is `github.com`, `www.github.com`, or `raw.githubusercontent.com`, or when the input is an `owner/repo` name. It SHALL NOT treat those names as a match when they appear only as a substring. A public load SHALL skip `node_modules`, SHALL keep at most 400 files, and SHALL skip a file larger than 1.5 MB. The line index SHALL keep at most 12,000 rows. Apple LZFSE SHALL be refused. The ThreeMD library SHALL stay free of filesystem and network I/O.

Acceptance Criteria:

- `web/github-source.ts` and `web/github-source.test.ts` match hosts with `URL.hostname` and paths with `pathname`.
- The tree cap, the byte cap, the line cap, and the LZFSE refusal are named in the spec and covered by the existing tests.

