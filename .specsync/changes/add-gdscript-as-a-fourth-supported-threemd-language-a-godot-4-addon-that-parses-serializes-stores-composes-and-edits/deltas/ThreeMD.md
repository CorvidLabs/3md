# GDScript as a fourth ThreeMD language

## ADDED

### REQUIREMENT REQ-ThreeMD-043

The Godot 4 GDScript addon SHALL parse, serialize, store, compose, resolve linked files, and edit ThreeMD documents with the same results as the Swift, TypeScript, and Rust libraries. Canonical text, payload kind 1, and payload kind 2 SHALL be byte-identical to the committed goldens. LZFSE SHALL be reported as unavailable. The library SHALL perform no file or network I/O. A separate helper MAY read project files the caller selected. Grammar, the version 1 container, payload kinds, and the composition profile SHALL remain unchanged. No lifecycle, contract, risk, or provenance gate SHALL be weakened. (Change requirements GD-01 to GD-08.)

Acceptance Criteria:

- Headless Godot passes the shared text vectors, the 4,318 numeric-power spellings, and the Unicode key fixtures, using Unicode 17 NFC and the frozen Foundation whitespace set.
- `encode_text_container` reproduces every non-composition kind-1 document anchor, and `encode_binary` reproduces every non-composition kind-2 document anchor. Decoding either file returns the same document. LZFSE returns `compressionUnavailable`.
- Self-contained composition, glyph-ledger resolution, identities, revisions, and diagnostics match the shared fixtures.
- The interchange gate checks every writer/reader pair among the four languages.
- README and CONTRIBUTING name the addon and how to copy `addons/threemd`. A small example uses planes as game layers. The `fledge` `gdscript` task runs the headless suite.
