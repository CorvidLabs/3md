# Case studies

Seven readings of documents already in this repository. Each study says what the file is, which paths you can open, what the libraries do, and what they leave alone.

ThreeMD 2.2.1 is current. Tag `v2.2.1` is commit `5411a9a`. The GitHub release was published on 2026-10-08. npm serves `@corvidlabs/threemd` and `@corvidlabs/three-md-element` at 2.2.1. The Homebrew formula `threemd` is 2.2.1. crates.io still serves `threemd` 2.1.0 because `CRATES_IO_TOKEN` is not configured. The notes are [RELEASE-2.2.1.md](../RELEASE-2.2.1.md).

The format is unchanged. Text grammar is 1.0. The binary envelope is version 1. Payload kinds are 1 and 2. The composition profile is `3md-composition-1`. Kind 1 is deprecated for new files. Kind 2 is the structured payload. Storage has no fixed size stop. Swift, TypeScript, and Rust library behavior stays the 2.1.0 library. The new surface is the Godot addon.

Swift, TypeScript, and Rust are the hosted verify lane. That lane checks nine writer/reader pairs. GDScript is a fourth library. When `THREEMD_GODOT` is set, local interchange checks sixteen pairs. `fledge run gdscript-interchange` is that run. Hosted CI does not install Godot. `fledge run gdscript` is the local headless suite.

The addon is [`gdscript/addons/threemd`](../../gdscript/addons/threemd). [`plugin.cfg`](../../gdscript/addons/threemd/plugin.cfg) names it ThreeMD, version 2.2.1. It targets Godot 4.7.2. It does not target Godot 3 or Godot 4.8. Copy only that folder into a game's `addons` directory and enable ThreeMD. `gdscript/project.godot` sets the feature `4.7`.

Library scripts do not open files. `ThreeMDParser`, `ThreeMDStorage`, `ThreeMDComposition`, `ThreeMDFileComposition`, and `ThreeMDEditing` stay on values the caller already has. `ThreeMDFiles` reads a path the game already chose. The addon loader opens only the imported `.res` Godot already selected. LZFSE comes back as `compressionUnavailable`. Composition editing implements `replaceEntry` only. The full diagnostic report is not ported. The addon does not spawn gameplay nodes. Enabling the plugin does not change the open scene.

Sculpt.3md at [`apps/sculpt`](../../apps/sculpt) is an application. These studies skip it. Sculpt is not a fifth parser. Its compact `.3mdb` is not the upstream binary standard. The upstream magic is `3mdbin\r\n`.

## Studies

- [Planes as layers](planes-as-layers.md) reads [`gdscript/examples/layers.3md`](../../gdscript/examples/layers.3md). Planes stay data. [`layer_map.gd`](../../gdscript/examples/layer_map.gd) is an example outside the addon.
- [Load an imported grove](load-imported-grove.md) reads [`gdscript/examples/grove/scene.3md`](../../gdscript/examples/grove/scene.3md). A Godot 4.7 game calls `load()` on that path and reads the title and plane labels.
- [Linked village](linked-village.md) reads [`Examples/LinkedVillage/scene.3md`](../../Examples/LinkedVillage/scene.3md). A glyph ledger names other files. The library does not open them.
- [Shared grove](shared-grove.md) reads [`Examples/Extensions/shared-grove.3md`](../../Examples/Extensions/shared-grove.3md). One named document is embedded once and referenced. The library does no filesystem or network I/O.
- [Kind 2 canopy](kind-2-canopy.md) reads [`Examples/Extensions/canopy.3md`](../../Examples/Extensions/canopy.3md) and [`canopy.structured.3mdb`](../../Examples/Extensions/canopy.structured.3mdb). Those are the same document in two containers.
- [Conway frames](conway-frames.md) reads [`Examples/game-of-life.3md`](../../Examples/game-of-life.3md). Twenty-four planes store the generations. The libraries do not run the rule.
- [Sunken Vault links](sunken-vault-links.md) reads [`Examples/dungeon.3md`](../../Examples/dungeon.3md). Exits are `[[z=N]]` links. The libraries do not play the rooms.

The [extension fixture table](../../Examples/README.md#storage-and-composition-fixtures) lists the readable files, the kind 1 binaries, and the Apple LZFSE binaries. The hosted gallery viewer does not decode binary `.3mdb` files or expand composition references.
