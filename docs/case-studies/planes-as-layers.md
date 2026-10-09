# Planes as layers

[`layers.3md`](../../gdscript/examples/layers.3md) is a Godot sample. The planes stay data. A game that wants nodes builds them itself.

Version and library limits that apply to every study are in the [index](README.md).

## What the document is

The file is text grammar `1.0`, axis `layer`, title Grove. It has three planes.

| z | Label | Body |
| --- | --- | --- |
| 0 | Ground | The forest floor. A game can parent its ground nodes here. |
| 1 | Canopy | Birds and light. The body says this plane is another layer. |
| 2 | HUD | Health and the map. The body says the addon does not instance a CanvasLayer. |

The file declares axis `layer`. The libraries store each plane's `z`, label, and Markdown body. They do not build a scene from those fields.

## What you can open

- [`gdscript/examples/layers.3md`](../../gdscript/examples/layers.3md), the document.
- [`gdscript/examples/play_layers.gd`](../../gdscript/examples/play_layers.gd), a headless check. It parses the file and expects the title Grove, three planes, and the labels Ground, Canopy, and HUD.
- [`gdscript/examples/layer_map.gd`](../../gdscript/examples/layer_map.gd), the example that builds child nodes.
- [`gdscript/examples/README.md`](../../gdscript/examples/README.md), the Godot-facing notes. The shared text corpus stays in [`Examples/`](../../Examples).
- [`gdscript/addons/threemd`](../../gdscript/addons/threemd). Copy only this folder. [`plugin.cfg`](../../gdscript/addons/threemd/plugin.cfg) is version 2.2.1.

The samples were run on Godot 4.7.2. The addon targets that release. It does not target Godot 3 or Godot 4.8.

[`gdscript/examples/grove/scene.3md`](../../gdscript/examples/grove/scene.3md) is a different sample. It names `props/lantern.3md` from a `3md-files` ledger. This study does not use that ledger.

## What the libraries do

Swift, TypeScript, Rust, and GDScript parse each plane as data: a `z`, an optional label, and a body. `play_layers.gd` does that check and then quits. It builds no nodes.

`layer_map.gd` sits in `gdscript/examples`. It is outside the addon. The script is `ThreeMDLayerMap`. Attach it to a node the game owns and set `document_path`. On ready it calls `build`. `build` asks `ThreeMDFiles.load_document` for that path. For each plane it makes a `Node`, names it from the label (or `plane` when the label is empty), stores metadata `threemd_z` and `threemd_body`, and returns the nodes. `_ready` calls `add_child` for each one on the node the game owns.

The editor importer recognizes `.3md` and `.3mdb` and saves a `ThreeMDDocumentAsset`. A script can `load` that resource and call `parsed()`. Enabling the plugin does not change the open scene.

`ThreeMDFiles` is the library script that reads a path. The path has to be one the game already chose.

## What they do not do

The addon does not spawn gameplay nodes. `layer_map.gd` is the piece that does, and only under a node the game owns. Gameplay nodes stay under the game's control.

`ThreeMDParser`, `ThreeMDStorage`, `ThreeMDComposition`, `ThreeMDFileComposition`, and `ThreeMDEditing` do not open files. The importer is editor-only.

`ThreeMDStorage` returns `compressionUnavailable` when the compression byte is 1. This sample is text, so that path is idle here. Composition editing implements `replaceEntry` only. The full diagnostic report is not ported.

GDScript is checked locally. `fledge run gdscript` runs the headless suite. `fledge run gdscript-interchange` sets `THREEMD_GODOT` and checks sixteen writer/reader pairs. Hosted CI does not install Godot. The hosted verify lane stays on the nine Swift, TypeScript, and Rust pairs.

This folder has no `.3mdb` twin of `layers.3md`. The hosted gallery shows the text catalog under `Examples/`. It does not decode binary `.3mdb` files.
