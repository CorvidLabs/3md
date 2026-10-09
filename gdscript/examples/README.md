# Godot examples

These samples run on Godot 4.7.2, the current stable release. Copy
`gdscript/addons/threemd` into a game's `addons` folder and enable ThreeMD.
The plugin registers an importer for `.3md` and `.3mdb`. It does not change
the open scene.

The shared document corpus lives in [`Examples/`](../../Examples). This folder
is the Godot-facing slice.

| Capability | Where |
| --- | --- |
| Text document and plane layers | [`layers.3md`](layers.3md), checked by [`play_layers.gd`](play_layers.gd) |
| Linked filenames | [`grove/`](grove) |
| Payload kind 1, payload kind 2, composition, edits, and node mapping | [`showcase.gd`](showcase.gd) |
| Attach planes to a node the game owns | [`layer_map.gd`](layer_map.gd) |
| Editor import | `addons/threemd/import_plugin.gd` |

`showcase.gd` is headless. `layer_map.gd` is the piece a scene uses:

```gdscript
# On a node in the game scene:
# document_path = "res://examples/grove/scene.3md"
```

Each plane becomes a child `Node` named from its label. `threemd_z` and
`threemd_body` are stored as metadata. Gameplay nodes stay under the game's
control.

After import, a game loads the project path. [`load_imported.gd`](load_imported.gd) does that for [`grove/scene.3md`](grove/scene.3md) and for the kind-2 `grove/scene.3mdb` this addon writes beside it:

```gdscript
var asset: ThreeMDDocumentAsset = load("res://examples/grove/scene.3md")
var document = asset.parsed()
```

`ThreeMDParser`, `ThreeMDStorage`, `ThreeMDComposition`, `ThreeMDFileComposition`,
and `ThreeMDEditing` still do not open files. `ThreeMDFiles` reads paths the
game already chose. The importer is editor-only.
