---
change: cover-the-github-style-viewer-page-in-the-spec-the-page-is-files-source-and-the-live-plane-view-it-opens-a-public
artifact: requirements
---

# Requirements

- **REQ-ThreeMDViewer-001** The viewer page SHALL present files, source, and the live plane view. It SHALL open a public GitHub repo, folder, or file, or a file or folder from this computer. Search SHALL read every opened line and open that plane. Markdown headings SHALL become planes. Opened files SHALL pack into one text document, and that document SHALL download as uncompressed kind 2. The `<three-md>` element SHALL stay a text renderer.
- **REQ-ThreeMDViewer-002** The page SHALL accept a GitHub locator only when the host is `github.com`, `www.github.com`, or `raw.githubusercontent.com`, or when the input is an `owner/repo` name. It SHALL NOT treat those names as a match when they appear only as a substring. A public load SHALL skip `node_modules`, SHALL keep at most 400 files, and SHALL skip a file larger than 1.5 MB. The line index SHALL keep at most 12,000 rows. Apple LZFSE SHALL be refused. The ThreeMD library SHALL stay free of filesystem and network I/O.
