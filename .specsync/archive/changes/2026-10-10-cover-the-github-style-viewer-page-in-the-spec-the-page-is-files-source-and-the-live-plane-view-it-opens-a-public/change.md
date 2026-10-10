---
id: cover-the-github-style-viewer-page-in-the-spec-the-page-is-files-source-and-the-live-plane-view-it-opens-a-public
state: archived
type: feature
base_commit: 84307639c2f24f6a23418a2b712f52a1d5b37551
---

# Cover the GitHub-style viewer page in the spec. The page is files, source, and the live plane view. It opens a public GitHub repo, folder, or file, or a local file or folder. Search reads every line and opens that plane. Markdown headings become planes. Opened files pack into one text document and download as uncompressed kind 2. The three-md element stays a text renderer.

## Intent

Cover the GitHub-style viewer page in the spec. The page is files, source, and the live plane view. It opens a public GitHub repo, folder, or file, or a local file or folder. Search reads every line and opens that plane. Markdown headings become planes. Opened files pack into one text document and download as uncompressed kind 2. The three-md element stays a text renderer.

## Affected Canonical Specs

- `ThreeMDViewer`

## Acceptance Criteria

- The spec states files, source, and live view; a public GitHub repo, folder, or file; a local file or folder; every-line search that opens that plane; section planes; pack; kind 2 download; and the element stays a text renderer. Evidence is the existing bun tests and the Playwright viewer spec.

## No-spec Rationale

Not applicable
