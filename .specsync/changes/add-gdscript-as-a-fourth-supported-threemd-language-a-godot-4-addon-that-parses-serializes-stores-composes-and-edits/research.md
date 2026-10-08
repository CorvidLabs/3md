---
change: add-gdscript-as-a-fourth-supported-threemd-language-a-godot-4-addon-that-parses-serializes-stores-composes-and-edits
artifact: research
---

# Research

- Engine on this machine: Godot 4.7.2 stable, official, `ed1daf0bf`, at `/opt/homebrew/bin/godot`.
- `//` is a comment in Godot 4.7, not integer division. `/` is float division. `ThreeMDBig` divides with a bit loop.
- `float()` and `String.num_scientific` disagree with the shared numeric oracle. Eight powers of two were enough to show that. The addon parses and formats with integer arithmetic only. All 4,318 spellings then matched.
- A subnormal fraction can be larger than 2^32. Packing it into one 32-bit word yields +0. The fraction occupies 52 bits across both words.
- Node 26 reports `process.versions.unicode` 17.0. Python's `unicodedata` on this machine is older, so the table is built from Unicode 17 `UnicodeData.txt` and `CompositionExclusions.txt` and checked against `String.normalize("NFC")`.
- Hangul syllables are a First/Last range in `UnicodeData.txt`, not one line per syllable. Composition of L, V, and T is algorithmic. Adjacent jamo have combining class 0, so the compose step must try a pair of starters, not only a starter plus a mark.
- The version 1 header is little-endian. Godot `PackedByteArray.encode_u32` and `decode_u32` are little-endian, which matches `DataView` with `littleEndian = true`.
- `class_name` is visible to other scripts only after `godot --headless --editor --quit` writes `gdscript/.godot/global_script_class_cache.cfg`. Preload works without that cache.
- There is no `bool()` constructor. `bool(value)` is a compile or runtime error.
