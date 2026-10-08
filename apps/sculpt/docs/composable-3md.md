# Composable 3md

One character can stand for an entire model. A composition contains a tile map and a library of named models. For example, `T` can place a tree and `C` can place a castle. Repeating a character places another copy of the same model; the library stores its definition once.

The first prototype uses explicitly sized blocks. A 24 × 24 × 24 tile can contain any model that fits those bounds. A map with four columns becomes 96 voxels wide. The X/Y grid uses the same axes as the slice editor, and each map layer adds depth along Z. Rotation is clockwise in the X/Y plane, around Z. Empty padding stays empty; oversized models fail rather than being cropped.

## Native workflow

Choose **File → New composition**, or search for **Compose reusable 3md models** in Commands. Choose a model letter, click map cells to place it, and rotate its binding. Import reads an explicitly selected readable `.3md` or compact `.3mdb`; imported definitions become snapshots in the composition, not live filesystem links. An imported composition retains its nested graph with remapped internal IDs.

**Save composition** writes the reusable map and library to a self-contained `.3md`. Reopening that file returns to the composition editor. Canceling the native save panel returns to the draft. **Open editable voxels** explicitly expands a copy into the existing sculpting workspace; painting and its compact save/export apply to that copy, not to the shared model definitions. The original composition remains reusable when saved separately. Models are edited individually and can be reimported; per-instance overrides and live external file synchronization are outside this prototype.

## Storage and bounds

This is the app-specific `ascii-composition-1` schema in a ThreeMD document, not a new upstream ThreeMD standard. Root spatial planes contain the tile characters. Metadata records grid dimensions, tile dimensions and character bindings. A fenced JSON preamble stores the other named model documents once. Those can be existing `ascii-sculpture-1` voxel documents or nested tile-map documents referencing the same global library. No camera or UI state is stored, and opening the composition does not follow paths or URLs.

The entire resolved volume stays within 256 voxels along each axis. The graph is bounded to 64 models, 16 reference levels, 64 MiB of unique resolved voxel volumes and 65,536 total recursive placements. Readable input remains bounded to 20 MiB with physical line/plane preflight. Missing bindings, missing models, duplicate definitions, circular references, unsupported metadata, invalid characters, clipping and excessive expansion fail without a partial scene. Expansion checks cancellation and caches each resolved model once.

## Example

For a scene that grows beyond a single expanded volume, choose **Use in a world**. The model library stays reusable, while [sparse placements and render distance](sparse-worlds.md) avoid allocating the gap between far-away copies.

`SculptureCompositionExamples.courtyard()` uses four definitions. Eight `C` placements refer to the same garden map. Each garden places two `T` trees and two `G` gates. The resulting scene is 144 × 24 × 144, with sixteen trees and sixteen gates. The reusable source and expanded exports are under `Examples/Compositions/`; the original twenty-one-example gallery remains unchanged.

Verification for this iteration is tracked separately under `docs/evidence/composition/`. Prior green CI or camera benchmarks do not establish composition correctness. No SpecSync approval, review, finalization or independent human review is claimed.
