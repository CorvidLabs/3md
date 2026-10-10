---
change: cover-the-github-style-viewer-page-in-the-spec-the-page-is-files-source-and-the-live-plane-view-it-opens-a-public
artifact: design
---

# Design

The page is one screen with three columns: files, source, and the live `<three-md>` view. A point field accepts a public GitHub repo, folder, or file. Open file, open folder, and drop read local bytes.

Below 900px the columns become Files, Source, and Live tabs. Source is the default tab. Live hides the editor. Files shows the file list.

Search reads the line index, then the catalog and the open document. A hit names the file, the plane, and the line. Choosing it opens that plane.

The element scrubs Z. It does not fetch, decode `.3mdb`, or resolve linked files. Those steps happen in the page before the text reaches the element.

Kind 2 download writes the current source with the library's uncompressed kind 2 encoder and saves that byte array. Apple LZFSE is not offered.
