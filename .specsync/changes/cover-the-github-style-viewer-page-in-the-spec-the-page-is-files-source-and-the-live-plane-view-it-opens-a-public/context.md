---
change: cover-the-github-style-viewer-page-in-the-spec-the-page-is-files-source-and-the-live-plane-view-it-opens-a-public
artifact: context
---

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
