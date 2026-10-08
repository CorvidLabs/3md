# Linked compositions

A linked composition keeps its models in separate files inside a project folder. One character in its tile map names one file, through ThreeMD 2.0.0's `3md-files` ledger. Sculpt reads the reachable files, resolves the shared models and shows the result. This is COMPOSITION-40; this page describes iteration A, the read path.

## Opening one

Choose **Open** and pick the linked root, then choose its project folder when Sculpt asks. Cancelling opens nothing. The folder must contain the root.

The folder is granted for this session only. Sculpt keeps no bookmark, stores nothing beyond the appearance setting and needs no new entitlement, so after a relaunch you choose the folder again.

In this iteration a linked composition is view-only. Painting, insertion, editing a shared model, map and tile size changes, saving, export and world handoff are unavailable, with a short explanation. Preview still works.

**Reload Linked Files** (File menu, or the button in the sheet) reads the files again after you change them elsewhere. Sculpt does not watch the folder. A failed reload keeps the previous scene and names the file; reloading never marks your work as changed.

If the links fail when you open the root, Sculpt shows a repair view: each failing link with its file and the reason, plus **Reload** and **Choose Folder**. Nothing is written.

## The file format

A linked root is an ordinary readable ThreeMD document with the app-specific scene schema `ascii-linked-composition-1`. It is not an upstream ThreeMD standard. Its metadata is exactly `scene-schema`, `width`, `height`, `tile-width`, `tile-height`, `tile-depth`, `3md-files` and an optional `sculpt-turns`. Its planes are tile layers like a composition's, without an embedded library. Every placed character other than `.` must be a ledger key.

The ledger maps one printable character to a path relative to the root, for example `3md-files: {"h":"models/house.3md"}`. Sculpt writes it with a JSON encoder on one line and checks it with ThreeMD's own ledger reader. `sculpt-turns` maps a character to 1, 2 or 3 clockwise quarter turns.

Detection is by content, never by extension. A linked root stored in the general binary container is refused by name.

## What a link may point to

Only files that other tools can also read:

- readable `ascii-sculpture-1` voxel models;
- the same models in the general ThreeMD binary container without compression;
- other readable linked roots.

Everything else is refused and the file is named: Sculpt compact `.3mdb` storage (the default Save), compressed binary, Sculpt compositions and worlds, composition profiles and bundles, generic Markdown, and any other document that carries its own ledger. To link a model saved in compact storage, save a readable copy first.

## Reading stays inside the folder

Every read goes through one confined reader. It splits paths by byte, opens each folder on the way without following symbolic links, accepts only regular files with a single hard link, refuses hidden path components, notices two spellings of the same file, and reads no more than the remaining budget. Only files reachable from the root are read, each once.

Linked paths cannot contain a colon (which Finder shows as a slash), a backslash or a control character. A root or linked file whose name contains one is refused by name; rename it.

## Limits

Until a tagged ThreeMD release includes the early bounds merged in CorvidLabs/3md#70, Sculpt enforces its own:

| Limit | Value |
| --- | --- |
| Normalized path | 1,024 UTF-8 bytes |
| Path component | 255 UTF-8 bytes |
| Reachable files, including the root | 64 |
| Ledger entries across all files | 512 |
| Files on one link path | 16 |
| Bytes read across all files | 16 MiB |
| Raw `3md-files` text in one file | 128 KiB |

Existing limits still apply: 256 cells per axis for each voxel model and the composition graph bounds. Refusals name the project-relative file and the limit. Missing files, invalid or escaping paths and cycles are refused the same way; a cycle is shown as the chain of files.

## Bundles

A bundle is the self-contained `3md-composition-1` graph that ThreeMD produces when it resolves a linked composition: each model is stored once, and references carry `glyph` and `source-file`. Sculpt reads bundles through ordinary **Open** without the project folder. `source-file` is kept as provenance and never followed. An opened bundle is an ordinary composition, so the existing native save and insertion apply to it. RookTool's `sculpture portable inspect` reports a bundle as a composition.

Sculpt can already encode a resolved linked composition as a readable or uncompressed binary bundle; the export command arrives in iteration B.

## Agent tools

RookTool reads only files named on its command line. Given a linked root, it reports that the file needs its project folder instead of a generic decode failure.

## Coming in iteration B

Starting a new linked composition, **Insert Linked Model**, Save and Save As that keep links correct, removing links, and the bundle export command.
