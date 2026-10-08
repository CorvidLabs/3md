---
change: add-gdscript-as-a-fourth-supported-threemd-language-a-godot-4-addon-that-parses-serializes-stores-composes-and-edits
artifact: tasks
---

# Tasks

- [x] GD-02 / GD-03. Correctly rounded numbers, Unicode 17 NFC, text parse, serialize, and links. Headless checks are green.
- [x] CRC-32/ISO-HDLC, including the `123456789` check value, in `checksum.gd`.
- [x] GD-04. Kind 1 and kind 2 storage, byte-identical to the document anchors. Headless result: `BINARY OK 0 CASES 50`. LZFSE returns `compressionUnavailable`.
- [x] GD-05 composition and linked files. `COMPOSITION OK 0 CASES 4` and `FILES OK 4` (LinkedVillage). Document edits: `EDIT OK` for snapshot, remove, insert, stale revision, and identity adoption. Composition-graph edits and the full diagnostic report are still open.
- [x] GD-01 game helper. `ThreeMDFiles` reads caller-selected project files. Parser, storage, composition, editing, and file composition do not call `FileAccess`.
- [x] GD-06. Local sixteen-pair gate with `THREEMD_GODOT` set. Receipt `3md-interchange-receipt-1`: `cases` 569, `producerConsumerPairs` 16, `imports` 31984, each pair 1999, `passed` true. Protocol stays `3md-interchange-1`. The verify lane stays on nine pairs.
- [x] GD-07 example, README, CONTRIBUTING, and `fledge run gdscript`. The task is not in the verify lane. Godot 4.7.2 examples cover layers, the linked grove, both payload kinds, composition, edits, and editor import registration.
- [ ] GD-08. `fledge trust verify` on the finished tree. Do not approve this definition as the user.
