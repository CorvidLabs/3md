# Linked village

[`scene.3md`](../../Examples/LinkedVillage/scene.3md) is one village plane. A `3md-files` ledger maps glyphs in that plane to other ThreeMD files.

Version and library limits that apply to every study are in the [index](README.md).

## What the document is

The file declares `3md` `1.1`, axis `space`, title Linked village. The text grammar stays 1.0. The version string does not change the grammar. Metadata `3md-files` is a strict JSON object. Each key is one printable ASCII glyph, U+0021 through U+007E. Each value is a relative filename.

| Glyph | Filename |
| --- | --- |
| `1` | `models/house.3md` |
| `2` | `models/tree.3md` |
| `3` | `models/tower.3md` |
| `4` | `models/house.3md` |

Glyphs `1` and `4` both name `models/house.3md`. Glyph `2` names the tree. Glyph `3` names the tower.

One plane: `z=0`, label Village. The picture is:

```
..2..3..2..
.1.....4...
```

[`house.3md`](../../Examples/LinkedVillage/models/house.3md) declares `3md` `1.1`, axis `space`, title House. It has no `3md-files` ledger. One plane, `z=0`, label Front, id `house-front`. The body is an ASCII house.

[`tree.3md`](../../Examples/LinkedVillage/models/tree.3md) declares `3md` `1.1`, axis `space`, title Tree. It has no `3md-files` ledger. One plane, `z=0`, label Tree, id `tree-front`. The body is an ASCII tree.

[`tower.3md`](../../Examples/LinkedVillage/models/tower.3md) declares `3md` `1.1`, axis `space`, title Tower. Its ledger is `{"T":"tree.3md"}`. The path in that file is `tree.3md`, relative to `models`, the folder that contains the tower. One plane, `z=0`, label Tower, id `tower-front`. The picture includes the glyph `T`.

[Shared grove](shared-grove.md) embeds canopy text inside [`shared-grove.3md`](../../Examples/Extensions/shared-grove.3md). Linked village names other files. Both are composition. The mechanisms differ. Shared grove keeps the child source in the entry. This scene keeps filenames in a `3md-files` ledger.

[`gdscript/examples/grove/scene.3md`](../../gdscript/examples/grove/scene.3md) is a different sample. It names `props/lantern.3md` from a `3md-files` ledger. This study stays on the village files.

## What you can open

- [`Examples/LinkedVillage/scene.3md`](../../Examples/LinkedVillage/scene.3md), the village.
- [`Examples/LinkedVillage/models/house.3md`](../../Examples/LinkedVillage/models/house.3md), the house.
- [`Examples/LinkedVillage/models/tree.3md`](../../Examples/LinkedVillage/models/tree.3md), the tree.
- [`Examples/LinkedVillage/models/tower.3md`](../../Examples/LinkedVillage/models/tower.3md), the tower.
- [`Examples/LinkedVillage/README.md`](../../Examples/LinkedVillage/README.md). These are generic ThreeMD Markdown documents with ASCII illustrations. No module registration is required.
- [`docs/FILE-COMPOSITION.md`](../FILE-COMPOSITION.md), the ledger contract.

The folder contains those four documents and the README. It contains no `.3mdb` of this scene.

From the repository root, the README bundle command is:

```
swift run threemd-interchange --bundle scene.3md --folder Examples/LinkedVillage --output linked-village.3md
```

The output folder must not be a symlink. On macOS `/tmp` is one, and the host refuses it. Use a new `.3mdb` destination for portable uncompressed binary. The command never overwrites an existing file.

## What the libraries do

Core performs no filesystem or network I/O. A host that implements file composition supplies `DocumentFileSource` values. Each value is a path and the bytes. Glyph placement belongs to the host. Rendering belongs to the host.

Glyphs `1` and `4` name the same filename. Within one file, a repeated raw ledger source reuses its first resolution. Characters 1 and 4 share one house definition.

`tower.3md` maps glyph `T` to `tree.3md`. Discovery reads that ledger relative to the file that contains it.

Swift exposes `DocumentFileSource`, `DocumentFileReference`, `DocumentFileCompositionResult`, and `DocumentFileComposition` (`ledger`, `resolvePath`, `resolve`). TypeScript and Rust expose equivalent APIs.

The README command writes a bundle of this scene. Sharing writes the resolved graph as readable `3md-composition-1` text. A host that encodes with `.binary` stores that profile as payload kind 2. Kind 1 is deprecated. `encodeTextContainer` still stores the same profile as payload kind 1 for a ThreeMD 2.0 reader.

A bundled profile can leave this folder. Each library imports it through the existing composition codec. Editing the Tree source and resolving again refreshes every linked occurrence. Existing bundled copies are independent.

## What they do not do

`ThreeMDParser`, `ThreeMDStorage`, `ThreeMDComposition`, `ThreeMDFileComposition`, and `ThreeMDEditing` do not open files. They stay on values the caller already has. The library does not open `models/house.3md`, `models/tree.3md`, or `models/tower.3md`. A host that implements file composition supplies the bytes.

`ThreeMDFiles` is the Godot script that reads a path the caller already chose. This village sample is not a Godot document.

Sculpt.3md is an application. It is not a format parser. This folder is not a Sculpt spatial-schema file.

The libraries do not assign a scene position to glyphs `1`, `2`, `3`, `4`, or `T`. The hosted gallery does not expand composition references.
