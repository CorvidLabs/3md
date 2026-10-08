---
change: add-gdscript-as-a-fourth-supported-threemd-language-a-godot-4-addon-that-parses-serializes-stores-composes-and-edits
artifact: requirements
---

# Requirements

IDs `GD-01` to `GD-08` are local to this change. The canonical requirement is `REQ-ThreeMD-043` in `deltas/ThreeMD.md`. The text grammar, the version 1 container, payload kinds, and the composition profile do not change. Swift, TypeScript, and Rust behavior does not change.

## Language

- **GD-01 Addon.** A Godot 4 addon under `gdscript/addons/threemd/` parses, serializes, stores, composes, resolves linked files, and edits documents with the same results as Swift, TypeScript, and Rust. The library scripts do not call `FileAccess` or open a network connection. A separate helper reads project files for games.
- **GD-02 Text.** Headless Godot passes every shared text vector in `conformance/*.json` and the Unicode document fixtures. Parse errors use the existing codes: `missingFrontmatter`, `invalidFrontmatter`, `missingVersion`, `invalidPlaneDirective`, `missingPlanePosition`, `duplicatePlane`. Duplicate `z` uses numeric equality, so `-0` and `0` are the same plane. Coordinates use correctly rounded IEEE-754 doubles, including the 4,318 `numeric-powers.json` spellings. Godot `float()` and `String.num_scientific` are not used for canonical coordinates.
- **GD-03 Unicode.** Key equivalence uses Unicode 17 NFC, the same version Node and Bun use for `String.normalize("NFC")`. Trimming uses the frozen Foundation whitespace set. Hangul composition is algorithmic. The generated table is embedded in the addon.
- **GD-04 Binary.** `encode_text_container` writes payload kind 1 and `encode_binary` writes payload kind 2. Both are byte-identical to the committed goldens for every non-composition document anchor. Decode of those files returns the same document. LZFSE returns `compressionUnavailable`. The header stays the 40-byte little-endian version 1 container. CRC-32/ISO-HDLC keeps the check value `0xCBF43926`. No new error code is added.
- **GD-05 Composition and editing.** Self-contained composition, glyph-ledger file composition, stable identities, exact revisions, and diagnostics match the other three libraries on the shared fixtures. The ledger helper is the only piece that reads files, and it reads bytes the caller already chose. Resolution still refuses invalid paths, cycles, missing files, and limit overflow.
- **GD-06 Interchange.** The interchange gate gains a GDScript adapter. Every writer/reader pair among Swift, TypeScript, Rust, and GDScript is checked. The protocol stays `3md-interchange-1` unless a separate change moves it.
- **GD-07 Games.** README and CONTRIBUTING name GDScript and show how to copy `addons/threemd` into a Godot project. A small example uses planes as layers. `fledge` task `gdscript` runs the headless suite. The addon does not publish a Godot asset, a package, or a tag.
- **GD-08 Trust.** This change does not weaken lifecycle, contract, risk, or provenance policy, does not edit the managed trust block, and does not treat an agent run as Leif's review of the diff.

## Canonical

### REQ-ThreeMD-043

The Godot 4 GDScript addon SHALL parse, serialize, store, compose, resolve linked files, and edit ThreeMD documents with the same results as the Swift, TypeScript, and Rust libraries. Canonical text, payload kind 1, and payload kind 2 SHALL be byte-identical to the committed goldens. LZFSE SHALL be reported as unavailable. The library SHALL perform no file or network I/O. Grammar, container, and composition profile versions SHALL remain unchanged.

Acceptance Criteria:

- Headless Godot passes the shared text vectors, the 4,318 numeric-power spellings, and the Unicode key fixtures.
- Kind 1 and kind 2 document anchors match byte for byte, and decoding them returns the same document.
- Composition, editing, and linked-file fixtures agree with the other three libraries.
- The interchange matrix includes GDScript.
- README explains how to copy the addon. A planes-as-layers example is included.
