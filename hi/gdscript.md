---
hi: 1
families: [GDSCRIPT]
---

# GDScript

## Intent

I want to copy the ThreeMD addon into a Godot 4.7.2 project, enable it, and import .3md and .3mdb as document data while the open scene, file reads, and gameplay nodes stay with the game.

I want the operations the addon implements to follow the other libraries, with a clear refusal for anything it leaves out, and I want its version to match the library release I copy from the repo.

## Criteria

- **GDSCRIPT-1**  I can copy gdscript/addons/threemd into a Godot 4.7 project and enable the plugin. The addon targets Godot 4.7.2. It does not target Godot 3 or Godot 4.8.
- **GDSCRIPT-2**  The editor imports .3md and .3mdb as a document resource. A running game can load() that imported path and read the title and plane labels. The addon registers the loader, so the game does not add a second script. Enabling the plugin does not change the open scene and does not spawn gameplay nodes.
- **GDSCRIPT-3**  Parser, storage, composition, and editing do not open files. ThreeMDFiles reads a path the game already chose.
- **GDSCRIPT-4**  Planes stay data. A game that wants nodes builds them itself. The example layer map is outside the addon.
- **GDSCRIPT-5**  Kind 2 save and kind 1 read behave like the other libraries for the operations the addon implements. LZFSE comes back unavailable.
- **GDSCRIPT-6**  Composition editing in the addon replaces one entry and keeps its id. The full diagnostic report and the other composition operations stay in Swift, TypeScript, and Rust.
- **GDSCRIPT-7**  I can run the headless suite locally when Godot 4.7.2 is installed. Hosted CI does not run that suite.
- **GDSCRIPT-8**  The addon version matches the library release, 2.2.1. It is copied from the repo. It is not a Godot Asset Library package.
