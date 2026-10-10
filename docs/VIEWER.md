# Browser viewer

[Open the viewer](https://corvidlabs.github.io/3md/viewer.html) to read and edit a document, inspect its cubes or
paint a supported slice grid. The viewer starts in **Cubes**. Choose **Preview**
to read notes, prose or frame documents one plane at a time; it does not autoplay.

## Try an example

These links open existing public GitHub files directly in the viewer.

| Example | Open in the viewer | What to try |
| --- | --- | --- |
| [Reusable canopy](../Examples/Extensions/canopy.3md) | [Text sculpture](https://corvidlabs.github.io/3md/viewer.html?src=https%3A%2F%2Fgithub.com%2FCorvidLabs%2F3md%2Fblob%2Fmain%2FExamples%2FExtensions%2Fcanopy.3md) | Orbit in Cubes, choose Slice and draw a cell. |
| [Layered notes](../Examples/layered-notes.3md) | [Reading example](https://corvidlabs.github.io/3md/viewer.html?src=https%3A%2F%2Fgithub.com%2FCorvidLabs%2F3md%2Fblob%2Fmain%2FExamples%2Flayered-notes.3md) | Choose Preview and select a plane. |
| [Canopy binary, kind 2](../Examples/Extensions/canopy.structured.3mdb) | [Portable binary](https://corvidlabs.github.io/3md/viewer.html?src=https%3A%2F%2Fgithub.com%2FCorvidLabs%2F3md%2Fblob%2Fmain%2FExamples%2FExtensions%2Fcanopy.structured.3mdb) | The same canopy opens from the structured binary file. |
| [Canopy binary, kind 1](../Examples/Extensions/canopy.3mdb) | [Older portable binary](https://corvidlabs.github.io/3md/viewer.html?src=https%3A%2F%2Fgithub.com%2FCorvidLabs%2F3md%2Fblob%2Fmain%2FExamples%2FExtensions%2Fcanopy.3mdb) | Existing uncompressed kind-1 files remain readable. |
| [Shared grove](../Examples/Extensions/shared-grove.structured.3mdb) | [Self-contained composition](https://corvidlabs.github.io/3md/viewer.html?src=https%3A%2F%2Fgithub.com%2FCorvidLabs%2F3md%2Fblob%2Fmain%2FExamples%2FExtensions%2Fshared-grove.structured.3mdb) | Use Inside to choose the embedded canopy or grove document. |

[Open the Examples folder](https://corvidlabs.github.io/3md/viewer.html?src=https%3A%2F%2Fgithub.com%2FCorvidLabs%2F3md%2Ftree%2Fmain%2FExamples) to browse the public files, or
[open the repository](https://corvidlabs.github.io/3md/viewer.html?src=https%3A%2F%2Fgithub.com%2FCorvidLabs%2F3md). **Load an example** shows the curated
examples. Search also finds the wider example catalog, binary samples and the
built-in **folder · LinkedVillage** example.

## Open your own files

- **Open file** reads a `.3md` text document or an uncompressed standard `.3mdb`.
  You can also drop a file onto the viewer. Markdown and text imports can become
  planes using **Document → Headings to planes**.
- **Open folder** reads files from the folder you choose, including nested
  folders. Keep linked children alongside their scene, with the paths named in
  its `3md-files` ledger. The folder loader prefers `scene.3md` and resolves
  reachable linked documents from the supplied files.
- The GitHub field accepts a **public** repo, folder, file or raw GitHub URL.
  Paste an address and choose **open**. Select another document in Files;
  filter that list or search its lines to find a plane.

For example, paste one of these into the GitHub field:

```text
CorvidLabs/3md
https://github.com/CorvidLabs/3md/tree/main/Examples
https://github.com/CorvidLabs/3md/blob/main/Examples/Extensions/canopy.3md
https://github.com/CorvidLabs/3md/blob/main/Examples/Extensions/canopy.structured.3mdb
```

For a linked project, download the repo and choose **Open folder** on
[Examples/LinkedVillage](https://github.com/CorvidLabs/3md/tree/main/Examples/LinkedVillage), keeping
`scene.3md` and `models/` together. The built-in folder search result opens those
same linked entries without downloading the repo. A GitHub folder currently
lists its files individually; it does not resolve the scene's linked entries
through the same folder path.

## Read, rotate and edit

**Edit** changes the source. **Preview** reads the selected plane. **Cubes**
shows a compatible character grid in 3D. **Slice** edits compatible rectangular
grids and includes a live 3D reference. All views use the current document.

In Cubes, drag to orbit through a full turn. Choose **Pan**, or Shift-drag or
right-drag, to move the sculpture on screen. Scroll to zoom; two fingers pan and
pinch on touch screens. **Fit** restores the starting camera. Use **Free** or
**X**, **Y**, **Z** to choose the rotation constraint; **Precise movement** offers
numeric rotation and pan steps. Arrow keys orbit a focused canvas, Shift-arrows
pan, plus/minus zoom and Home fits. Click a cube to select its slice.

In Slice, choose a thumbnail, then **Draw**, **Erase** or **Fill**, a character
and a brush size. Drag to paint; one stroke is one undo step. Arrows select a
cell and Space applies the tool. **Selected cell** lets you enter exact X/Y
coordinates. Use grid zoom or **Show previous slice** as needed. **Expand**
returns to Cubes with the same camera and selected slice.

## Keep your changes

The **Document** menu downloads the current document as readable `.3md` or
uncompressed kind-2 `.3mdb`. Ctrl/Cmd-S downloads readable text. **Copy share
link** puts the current document in the link so another reader can open it.

Edits and undo history survive file and linked-entry switches within the current
open collection. Download exports a copy; it does not overwrite the original
file, save back to a folder, commit to GitHub or clear the Edited marker.
Refreshing or opening another collection clears the in-memory drafts, so
download the documents you want to keep first. Composition exports contain the
selected document; edits do not rebuild the original composition profile.

## Supported files and limits

| Input or view | Browser support |
| --- | --- |
| `.3md` | UTF-8 ThreeMD text, including prose and grid documents. |
| Standard `.3mdb` | Uncompressed payload kind 2 and older payload kind 1; self-contained compositions can expose their embedded entries. |
| Apple LZFSE `.3mdb` | Unsupported. Use readable text or uncompressed binary. |
| Sculpt compact `.3mdb` | A separate app format. Save readable `.3md` or export an upstream uncompressed binary copy from Sculpt first. |
| Local linked folders | Resolve reachable `3md-files` references from the selected folder's files. |
| Public GitHub | Repo/folder/file/raw locators; up to 400 files, skipping tree entries larger than 1,500,000 bytes. Private repos and authentication are unsupported. GitHub can rate limit requests. |
| Cubes | Character grids up to 64 × 64 per plane, at most 12 distinct non-space characters and up to 4000 occupied cells. Space, dot and tab are empty. Requires WebGL2. |
| Slice | Complete fenced grids of matching dimensions, up to 64 × 64, 256 planes, 4000 occupied cells and 1.5 MiB source, using Sculpt's palette `#@*+ox:=-` with dot/space empty. |

Prose, ragged grids, other glyphs or larger documents can stay in Edit/Preview
when Slice is unavailable. The 2D Slice editor works without a WebGL reference.
These browser limits do not change the ThreeMD library's storage capabilities.

Two loading gaps remain: GitHub linked folders list individual documents rather
than resolving their scene entries, and a non-GitHub direct binary `?src=` URL
is read as text. For the latter, download the `.3mdb` and use **Open file**;
the GitHub-backed binary links above use the supported binary path.

For storage details, see [the binary format](../SPEC.md),
[linked file composition](FILE-COMPOSITION.md), and
[Sculpt.3md](../apps/sculpt/README.md). Sculpt's default compact save has a
different format from the standard ThreeMD binary, despite sharing `.3mdb` as
its filename extension.
