# Load an imported grove

[`scene.3md`](../../gdscript/examples/grove/scene.3md) is a Godot sample. After the editor import, a game loads that path and reads the title and plane labels. The planes stay data.

Version and library limits that apply to every study are in the [index](README.md).

## What the document is

The file declares `3md` `1.1`, axis `layer`, and title Grove. Its `3md-files` ledger is `{"1":"props/lantern.3md"}`. It has three planes.

| z | Label | Body |
| --- | --- | --- |
| 0 | Ground | The forest floor. Glyph 1 is the lantern prop. |
| 1 | Canopy | Birds and light. This plane is another layer, not a Godot node. |
| 2 | HUD | Health and the map. |

The file declares axis `layer`. The libraries store each plane's `z`, label, and Markdown body. They do not build a scene from those fields.

Glyph 1 names [`lantern.3md`](../../gdscript/examples/grove/props/lantern.3md). That file is separate. Its title is Lantern. The library does not open it unless a caller supplies the path.

## What you can open

- [`gdscript/examples/grove/scene.3md`](../../gdscript/examples/grove/scene.3md), the document.
- [`gdscript/examples/grove/props/lantern.3md`](../../gdscript/examples/grove/props/lantern.3md), the file glyph 1 names.
- [`gdscript/examples/load_imported.gd`](../../gdscript/examples/load_imported.gd), a headless check. It calls `load()` on the imported text and on the kind-2 file written beside it. It does not spawn nodes.
- [`gdscript/examples/write_grove_kind2.gd`](../../gdscript/examples/write_grove_kind2.gd). It writes `scene.3mdb` with this addon's kind-2 encoder. It does not call `load()`. `scene.3mdb` is not a committed file.
- [`gdscript/examples/README.md`](../../gdscript/examples/README.md), the Godot-facing notes.
- [`gdscript/addons/threemd`](../../gdscript/addons/threemd). Copy only this folder. [`plugin.cfg`](../../gdscript/addons/threemd/plugin.cfg) is version 2.2.1.
- [`document_format_loader.gd`](../../gdscript/addons/threemd/document_format_loader.gd), the loader a running game uses.
- [`docs/RELEASE-2.2.1.md`](../RELEASE-2.2.1.md), the bug and the fix. The unfixed log is [`godot-load-repro.log`](../evidence/release-2.2.1/godot-load-repro.log).

The samples were run on Godot 4.7.2. The addon targets that release. It does not target Godot 3 or Godot 4.8.

This study is not [`layers.3md`](../../gdscript/examples/layers.3md) and not [`shared-grove.3md`](../../Examples/Extensions/shared-grove.3md).

## What the libraries do

After the editor import, a Godot 4.7 game calls `load("res://examples/grove/scene.3md")`. The value is a `ThreeMDDocumentAsset`. The game then calls `parsed()`. The title is Grove. The labels are Ground, Canopy, and HUD.

`load_imported.gd` is the headless check. It does not call `parsed()`. It calls `load()` from `_initialize`, not `_init`. On a `--script` SceneTree, `_init` runs before Godot registers `class_name` resource loaders. `_initialize` runs after that registration. The script expects `document_title` Grove and `plane_labels` Ground, Canopy, and HUD. It does not build the asset with `from_text`.

The same script also calls `load("res://examples/grove/scene.3mdb")`. That path is not in the repository. `write_grove_kind2.gd` writes it with this addon's kind-2 encoder. Look for the file only after that script runs.

The loader is `ThreeMDDocumentFormatLoader` inside the addon. Godot registers that `class_name` from the global script class cache at startup, including a running game. The importer plugin is editor-only. Copying `addons/threemd` is enough. The game does not add a second script.

The loader claims only type `ThreeMDDocumentAsset` and extension `res`. `_load` calls `ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)`. The empty type lets the binary loader open the `.res`. `CACHE_MODE_IGNORE` keeps that read off the import remap that called it. A typed load of the same path would recurse.

Before this loader, that `load()` failed outside the editor. The importer saves a binary `.res` whose type string is `ThreeMDDocumentAsset`. The binary loader does not claim that type hint. Godot reported `No loader found for resource: res://.godot/imported/<file>.res (expected type: ThreeMDDocumentAsset)`. The kept log is [`godot-load-repro.log`](../evidence/release-2.2.1/godot-load-repro.log). The 2.2.0 headless suite never called `load()` on an imported document. `showcase.gd` builds the asset with `ThreeMDDocumentAsset.from_text`.

Swift, TypeScript, Rust, and GDScript still store each of these planes as data: a `z`, a label, and a body. `ThreeMDFiles` is the library script that reads a path the caller already chose. A caller can open `props/lantern.3md` that way. `load()` of `scene.3md` does not open the lantern by itself.

## What they do not do

The addon does not spawn gameplay nodes. `load_imported.gd` does not spawn nodes. Gameplay nodes stay under the game's control.

`ThreeMDParser`, `ThreeMDStorage`, `ThreeMDComposition`, `ThreeMDFileComposition`, and `ThreeMDEditing` do not open files. The loader opens only the imported `.res` Godot already selected. It does not follow the `3md-files` ledger.

The library does not open `lantern.3md` unless a caller supplies the path.

`scene.3mdb` is not a committed file. `write_grove_kind2.gd` writes it. `load_imported.gd` calls `load()` on that path after the write.

Hosted CI does not install Godot. `fledge run gdscript` is the local suite. It imports with the plugin enabled, writes `scene.3mdb`, imports again, and then runs `load_imported.gd`. A `--script` check alone does not import.
