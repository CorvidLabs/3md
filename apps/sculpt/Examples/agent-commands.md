# Sculpture document commands

Agents can inspect and edit readable `.3md` and compact `.3mdb` sculptures through the development-only Swift `RookTool` executable. The CLI and native editor use the same typed command engine and bounded document codec. This interface edits explicitly named files; it does not automate or connect to the running app. Open either resulting format in the editor to see it.

From the repository directory, inspect an example:

```console
swift run RookTool sculpture inspect Examples/character-orb.3md
```

The only standard output is JSON. The inspection reports `version`, `title`, `width`, `height`, `depth`, `occupiedCount`, `palette`, `emptyGlyph`, `coordinateBase`, and `axes`.

Coordinates are zero-based. X counts columns from left to right, Y counts rows from top to bottom, and Z counts spatial depth slices. Each dimension can be 1–256. Valid coordinates satisfy `0 <= x < width`, `0 <= y < height`, and `0 <= z < depth`. A period (`.`) is an empty cell. The occupied glyph palette is `# @ * + o x : = -`. Cubes and ASCII show the same cells, so the same commands edit either presentation, including the detailed castle, world, and solar-system examples.

Save this exact batch as `/private/tmp/rook-agent-demo.commands.json` using your file editor or the agent's file-writing tool:

```json
{
  "version": 1,
  "commands": [
    { "action": "rename", "title": "First agent sculpture" },
    { "action": "paint", "x": 2, "y": 3, "z": 8, "glyph": "@" },
    { "action": "erase", "x": 4, "y": 3, "z": 8 },
    { "action": "rotateSlice", "z": 8, "quarterTurns": 1 }
  ]
}
```

Apply it to a new output file, then inspect that output:

```console
swift run RookTool sculpture apply Examples/character-orb.3md /private/tmp/rook-agent-demo.commands.json /private/tmp/rook-agent-result.3md
swift run RookTool sculpture inspect /private/tmp/rook-agent-result.3md
```

Choose a fresh output filename each time. Apply refuses an existing file, directory, or symbolic link, including a broken symbolic link. The input sculpture and command file stay unchanged. All commands validate and complete in memory before output is published atomically. Any invalid command rejects the entire batch.

The output extension selects storage: `.3md` writes canonical readable text; `.3mdb` writes compact compressed voxels. Other output extensions are refused. Input format is detected from its contents, so either input can produce either output without changing document semantics. For example, change the output above to `/private/tmp/rook-agent-result.3mdb` for a compact save. A compact file is Sculpt.3md-specific storage, not a new standard ThreeMD text dialect.

Apply returns JSON containing `version: 1`, `operation: "apply"`, the absolute `output` path, `appliedCommandCount`, and the resulting `inspection`. Failures return a nonzero exit status and a diagnostic on standard error.

The version 1 actions are:

| Action | Required fields | Effect |
| --- | --- | --- |
| `paint` | `x`, `y`, `z`, `glyph` | Replace one cell with one palette glyph or `.`. |
| `erase` | `x`, `y`, `z` | Empty one cell. |
| `fill` | `x`, `y`, `z`, `glyph` | Replace the seed's connected glyph region within its slice. Connectivity uses four neighbors; it never crosses Z slices. |
| `clearSlice` | `z` | Empty every cell in that slice. |
| `rotateSlice` | `z`, `quarterTurns` | Rotate a square slice clockwise by 1, 2, or 3 quarter turns. |
| `rename` | `title` | Set a title of 1–80 printable ASCII characters. |

For example, these commands fill a connected region and clear a slice:

```json
{
  "version": 1,
  "commands": [
    { "action": "fill", "x": 7, "y": 7, "z": 8, "glyph": "*" },
    { "action": "clearSlice", "z": 15 }
  ]
}
```

Batches contain 1–256 commands. Unknown actions, unexpected fields, missing fields, unsupported versions, invalid glyphs, and out-of-bounds coordinates are rejected. Both inputs must be regular files; either sculpture format is bounded at 20 MiB, while command JSON stays bounded at 256 KiB. Compact decoding also validates dimensions, bounded stream length, exact decompressed voxel count, and checksum. The output folder must already exist, permit writing, and support hard links for atomic publication; unsupported filesystems return an error without replacing an existing path. No command runs a process, accesses the network, or changes the app's sandbox entitlements.

## Compositions and sparse worlds

`inspect` also detects self-contained reference documents. Composition inspection reports `mode: "composition"`, the shared model count, root map/bindings and expanded voxel facts. Sparse-world inspection reports `mode: "sparse-world"` and exact instance records. World X/Y/Z coordinates are decimal strings in the JSON result so clients do not round Int64 values through floating-point numbers.

```console
swift run RookTool sculpture inspect Examples/Compositions/courtyard.3md
swift run RookTool sculpture expand Examples/Compositions/courtyard.3md /private/tmp/courtyard-expanded.3mdb
swift run RookTool sculpture inspect Examples/Compositions/wide-world.3md
swift run RookTool sculpture model Examples/Compositions/wide-world.3md garden /private/tmp/garden-copy.3mdb
```

Expansion and model extraction require a fresh output path. They produce detached voxel copies that the ordinary `apply` command can edit. Whole-world expansion and direct voxel edits to reference documents are refused, preserving their references and distant placement records.

`sculpture compose MANIFEST.json NEW.3md` assembles a reusable composition from explicitly named regular model files. The manifest contains exactly the version-1 fields below; paths are relative to the manifest. Imported nested compositions are embedded with remapped internal IDs. No path or URL remains in the output library.

```json
{
  "version": 1,
  "title": "Gate pair",
  "width": 2,
  "height": 1,
  "tileWidth": 24,
  "tileHeight": 24,
  "tileDepth": 24,
  "layers": [["GG"]],
  "bindings": [{"glyph": "G", "model": "gate", "quarterTurns": 0}],
  "models": [{"id": "gate", "path": "moon-gate.3md"}]
}
```

The bounded [composition](../docs/composable-3md.md) and [sparse-world](../docs/sparse-worlds.md) schemas are Sculpt.3md-specific conventions, not upstream ThreeMD standards. These CLI operations remain file-based development tools; the product does not host a service or run the CLI.

## Inserting files into a composition or world

`sculpture portable insert INPUT REQUEST.json OUTPUT.3md|OUTPUT.3mdb` and `sculpture reference insert INPUT.3md REQUEST.json NEW.3md` apply the app's insertion rules to explicitly listed files. Portable insert keeps imported identities and annotations and requires `expectedScene`, a file whose exact revision must still match the input; it refuses rather than dropping portable data when the portable limit is reached, and when no portable data is involved the refusal suggests reference insert for a native result. A native INPUT is treated as a parent without portable data. Reference insert writes native readable output from scene values, refuses a portable parent, does not accept `expectedScene`, and its receipt field `portableDataNotCarried` lists inputs whose portable data the native output does not keep.

```json
{
  "version": 1,
  "files": ["models/tower.3md", "models/bridge.3mdb"],
  "cell": { "x": 0, "y": 0, "z": 0 },
  "replaceOccupied": false,
  "expectedScene": "expected.3md"
}
```

Use `cell` with JSON integers for a composition, or `focus` with canonical decimal strings for a world, for example `{ "x": "-5", "y": "7", "z": "9223372036854775000" }`. Exactly one is required. Paths are relative to the request file and are placed in the listed order. Requests are strict, version 1 and at most 256 KiB. Occupied composition targets are refused unless `replaceOccupied` is true. Count, cell, character and model checks run before any file is read; each file is then read as a regular file without following symlinks and checked for size and tile fit, and every refusal names the file. World and generic Markdown children are refused, and a result that could not reopen natively is refused as too large. The output must not exist. The JSON receipt lists the placed models with their titles and target cells or exact origins, any replaced glyphs, the storage kind and, for portable output, the revision size and diagnostics.
