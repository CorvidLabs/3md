---
hi: 1
families: [CLI, VIEWER, EDITOR]
---

# Tools

## Intent

I want the threemd command to validate a text file, show its planes and links, render HTML, and read a pipe.

I want that command to stay on the text file, and I want kind 2 to stay with the libraries.

I want the hosted page to let me edit a text document and share a link that carries it, with the three-md element as the viewer.

I want the editor extension to highlight a text .3md file from a VSIX I build locally, with the libraries keeping the parse rules.

## Criteria

- **CLI-1**  I can validate a text .3md file with threemd validate. A well-formed file prints ok, and a malformed file fails with the error.
- **CLI-2**  I can inspect planes and cross-plane links from the command line with threemd info and threemd links.
- **CLI-3**  I can run threemd check-links and get a failure when a [[z=N]] target is missing.
- **CLI-4**  I can render a text document to HTML with threemd html.
- **CLI-5**  I can pipe text in by passing -. The tool does not read the network.
- **CLI-6**  I can pass --json to validate, info, links, and check-links.
- **CLI-7**  I can rely on .3mdb staying off the CLI. When I need kind 2 I use the libraries, and the CLI stays on the text file.
- **VIEWER-1**  I can open the hosted editor and viewer, edit a text document, and share a link that carries the document.
- **VIEWER-2**  The viewer is the three-md element. The npm package @corvidlabs/three-md-element is 2.2.1.
- **VIEWER-3**  I can browse the text examples in the hosted gallery. Those cards stay text. In the viewer I can find every text example in the repository, open an uncompressed .3mdb, open a composition profile, or open a folder of linked files. The page shows the decoded text in the element. Apple LZFSE stays unavailable.
- **VIEWER-4**  I can rely on the element and the VS Code surface staying on text.
- **VIEWER-5**  I can scrub, drag, and step through the planes of a text document in the element. Parsing stays with @corvidlabs/threemd.
- **VIEWER-6**  The viewer keeps files on the left. Edit, Slice, the plane preview, and Cubes share the panel beside them and switch, and Cubes shows first, inside the window. On a narrow window, Files and the document take turns. The page does not switch render modes and does not autoplay. The opening document is a fenced character grid drawn as complete, lit cubes on the GPU that I can orbit and zoom. Their translucent fill keeps the glyph color, visible edges outline the cells, and gold edges mark the selected Z slice without repainting it. The dark stage, colors, and axes match Sculpt.3md, a single cell looks like a full cube, and about 1400 cubes stay responsive. Clicking a cube picks its slice, and the status bar shows the line, the axis, and the cube count. The document title stays visible, controls leave room for the stage on my phone, and the slice row scrolls to keep my selection visible. I can rotate it through full turns in every direction, choose Pan to move it, Shift-drag or right-drag to pan, and use two fingers to move and pinch to zoom. I can fit the sculpture back in the window, zoom with buttons or scroll, and use arrow keys to orbit or Shift-arrows to pan. Insert tools belong in Edit, and exports and conversion tools are together under Document. A document without cubes offers Preview so I can keep reading. GitHub open shows when it is busy and lets me try again after an error. I can point it at a public GitHub repo, folder, or file, or at a file or folder on this computer. Switching files or documents inside an open keeps my edits, caret, and selected plane. Edited files are marked, and I can filter the file list and use the keyboard to choose one. Opening a file or search result on my phone brings the document into view. Search and packing use my current edits. A failed open keeps my current files. Search looks at every line and opens that plane. I can turn Markdown headings into planes, pack opened files into one text document, and download that document as uncompressed kind 2. The element stays a text renderer.
- **VIEWER-7**  I can choose X, Y or Z on the rotation sphere, drag around that axis, enter an exact degree step, and nudge the camera or pan by a number of cells. Free returns to ordinary orbit. These movements match Sculpt and keep my sculpture unchanged.
- **VIEWER-8**  I can edit a rectangular sculpture in Slice with thumbnails, a large character grid, Draw, Erase and Fill, the Sculpt palette, sizes 1, 3 and 5, previous-slice ghosts, keyboard cells, grid zoom, and a live 3D reference. One drag is one undo step. Source edits share that history, and it follows my file or linked document when I switch. Only the cells I paint change; other source bytes remain intact. Unsupported documents explain how I can keep working in Edit.
- **EDITOR-1**  I can get syntax highlighting for a text .3md file in the editor extension, including frontmatter, @plane directives, cross-plane links, and Markdown plane bodies.
- **EDITOR-2**  I can build the extension locally as a VSIX. It is not published to a marketplace.
- **EDITOR-3**  The extension does not become a second parser with different rules.
- **EDITOR-4**  The extension has no preview and no language server.
- **EDITOR-5**  I can build the local extension at version 2.2.1, the same library release.
