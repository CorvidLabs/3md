---
change: add-gdscript-as-a-fourth-supported-threemd-language-a-godot-4-addon-that-parses-serializes-stores-composes-and-edits
artifact: design
---

# Design

The addon is a library, not a scene plugin. Enabling it does not change the open scene.

## Layout

- `gdscript/project.godot` is only the headless test project.
- `gdscript/addons/threemd/` is what a game copies.
- `gdscript/tests/` runs under `godot --headless --script`.
- `gdscript/tools/generate_nfc.py` rebuilds the Unicode 17 table. The committed `nfc_data.gd` is the table the game loads.

## Types

- `ThreeMDDocument` and `ThreeMDPlane`. `title`, `preamble`, `label`, `x`, and `y` are null when omitted. An empty string is present and empty.
- `ThreeMDLink` and `ThreeMDLinkEdge` for `[[z=N]]` and `[[z=N|text]]`.
- `ThreeMDError` with `code`, `message`, `line` (`-1` when absent), and `detail`.
- `ThreeMDParser.parse`, `serialize`, `links`, `dangling_links`, `link_graph`.
- `ThreeMDNumber.parse_finite` and `canonical`.
- `ThreeMDStorage.encode_text`, `encode_text_container`, `encode_binary`, `decode`.
- Composition, editing, and `ThreeMDFiles` follow the TypeScript types, with `snake_case` names.

## Binary

Kind 1 is the storage writer's canonical UTF-8, not `serialize`. The storage writer always quotes scalars. Kind 2 is the structured payload from SPEC.md 11.3. The checksum covers header bytes `[0, 36)` and payload bytes `[40, end)`.

## Games

A layer example reads one `.3md` through `ThreeMDFiles` and maps each plane's `z` to a `CanvasLayer` or a `Node2D` the game owns. The addon does not instance those nodes itself.
