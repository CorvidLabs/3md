---
change: add-gdscript-as-a-fourth-supported-threemd-language-a-godot-4-addon-that-parses-serializes-stores-composes-and-edits
artifact: testing
---

# Testing

Headless Godot runs the suite. A script error is a failure even when the process exit code is 0. The engine prints `SCRIPT ERROR` and may still call `quit(0)`.

| Check | Script | Oracle |
| --- | --- | --- |
| Numeric spellings | `gdscript/tests/number_check.gd` | `conformance/extensions/numeric-powers.json`, 4,318 vectors |
| NFC | `gdscript/tests/nfc_check.gd` | Unicode 17 via Node `String.normalize`, committed `nfc_vectors.bin` |
| Text | `gdscript/tests/text_check.gd` | `conformance/*.json` plus the three Unicode document fixtures |
| Binary | `gdscript/tests/binary_check.gd` | kind 1 and kind 2 document anchors in `conformance/structured/manifest.json` |

Passing runs on this branch:

- `TEXT OK 0 CASES 46`
- `TOTAL 4318 MISMATCH 0`
- `NFC 1127 MISMATCH 0`
- `BINARY OK 0 CASES 50`
- `COMPOSITION OK 0 CASES 4`
- `FILES OK 4` for Examples/LinkedVillage
- `EDIT OK` for document snapshot, remove, insert, stale revision, and `plane-1` adoption
- `LAYERS OK 3`
- `SHOWCASE OK` for the Godot 4.7.2 grove: text asset, payload kind 1, payload kind 2, composition, linked files, a revision-checked edit, layer nodes, and importer registration

Local sixteen-pair run (`THREEMD_GODOT=/opt/homebrew/bin/godot .build/debug/threemd-interchange`), protocol `3md-interchange-1`:

```json
{"schema":"3md-interchange-receipt-1","cases":569,"producerConsumerPairs":16,"imports":31984,"passed":true,"compression":"none; optional Apple LZFSE excluded"}
```

Each of the 16 producer/consumer pairs transferred 1999 documents. The verify lane is unchanged and still runs nine pairs.

Still required before the change is called complete: composition-graph edits beyond `replaceEntry`, the full diagnostic report, and `fledge trust verify`. GDScript is not added to the 2.1 performance gate or the verify lane.

## Requirement evidence

| ID | Evidence |
| --- | --- |
| GD-02, GD-03 | `number_check.gd`, `nfc_check.gd`, `text_check.gd` |
| GD-04 | `binary_check.gd`: `BINARY OK 0 CASES 50` |
| GD-05 | `composition_check.gd`, `file_check.gd`, `edit_check.gd`. Composition edits and full diagnostics remain open |
| GD-06 | `gdscript/tools/interchange.sh`. Local receipt: 16 pairs, 31984 imports, `passed` true. Verify lane stays at nine pairs |
| GD-07 | `gdscript/examples/layers.3md`, README, CONTRIBUTING, `fledge run gdscript` |
