# Docs

These pages describe Sculpt.3md in this checkout. The app builds against the ThreeMD sources at the repository root, by path. [Distribution](distribution.md) is the adoption checklist, and none of its checks have been started.

## Product

- [Architecture](architecture.md) — one window, the package targets, and the offline sandbox.
- [Sculpture editor](ascii-sculpture.md) — cubes, ASCII, slices, bounds, and the landed editor slices.
- [Verification](verification.md) — the reset-app lane, and the later notes that retired launcher hi files left the checkout.
- [Threat model](threat-model.md) — appearance, chosen files, and the absence of a network client.
- [Trust boundaries](trust-boundaries.md) — what crosses the window, the file panel, and the development tools.
- [Dependencies](dependencies.md) — the exact ThreeMD 2.0.0 pin and the tool pins.
- [Fledge](fledge-integration.md) — development lanes only. The app does not ship Fledge.

## Scenes and files

- [Composable 3md](composable-3md.md) — one character places a reusable model.
- [Sparse worlds](sparse-worlds.md) — exact 64-bit placements and a finite render neighborhood.
- [Exploration](world-exploration.md) — Orbit, plus session-only WASD, drag-to-look, and vertical travel.
- [Shared model editing](shared-model-editing.md) — Apply, Cancel, and Make Unique.
- [File and folder insertion](file-insertion.md) — embed a chosen sculpture or composition.
- [Linked compositions](linked-composition.md) — read models from a project folder chosen for the session.
- [Compact storage](compact-storage.md) — the app-specific `.3mdb` container.
- [ThreeMD 2.0 adoption](3md-2-adoption.md) — explicit portable text and uncompressed-binary copies.
- [1024-cubed case study](volume-1024-case-study.md) — stored bytes, probe timings, frames, and the world files.
- [Upstream storage proposal](three-md-upstream-plan.md) — the historical 1.8.1 assessment. The current pin is in [dependencies](dependencies.md).

## Release hold

- [Distribution](distribution.md) — wait for tagged ThreeMD 2.1.0, then the adoption checks.

## Examples

- [Gallery](../Examples/README.md) — twenty-one sculptures, each as 3md, PNG, GIF, MP4, and OBJ.
- [Math ladder](../Examples/Math/README.md) — formula models from 16³ through 256³. The 256-cell model is a PNG here and is generated on request.
- [Compositions](../Examples/Compositions/README.md) — the nested courtyard and a wide world.
- [Blockhaven](../Examples/Blockhaven/README.md) — the original block landscape.
- [Agent commands](../Examples/agent-commands.md) — explicit-file inspection and edits. The commands do not control the running app.

## Evidence

Each folder keeps the lane that produced it. A later pin does not rerun that lane.

- [Base app](evidence/base-mac-app/) — the reset window, Settings, and menu bar.
- [ASCII sculpture](evidence/ascii-sculpture/verification-notes.md)
- [Gallery and exports](evidence/sculpture-enhancements/verification-notes.md)
- [Editor redesign](evidence/editor-redesign/verification-notes.md)
- [Cubes](evidence/voxel-worlds/verification-notes.md)
- [Solar system](evidence/solar-system/verification-notes.md)
- [Compact storage](evidence/compact-storage/verification-notes.md)
- [Camera performance](evidence/camera-performance/verification-notes.md)
- [Compositions and worlds](evidence/composition/verification-notes.md)
- [Blockhaven](evidence/blockhaven/verification-notes.md)
- [Shared models](evidence/shared-model-editing/verification-notes.md)
- [Direct insertion](evidence/file-insertion/README.md)
- [Insertion discoverability](evidence/insertion-discoverability/README.md)
- [ThreeMD 2.0 adoption](evidence/3md-2-adoption/verification-notes.md)
- [Landed ThreeMD integration](evidence/landed-3md-integration/README.md)
- [World exploration](evidence/world-exploration/README.md)
- [1024-cubed receipts](evidence/volume-1024/README.md)
- [Linked compositions](evidence/linked-composition/README.md)
- [Math gallery](evidence/math-gallery/README.md)

Contracts live in [the app spec](../specs/RookApp/RookApp.spec.md), [the volume spec](../specs/RookSculpture/RookSculpture.spec.md), [the preview spec](../specs/RookRendering/RookRendering.spec.md), [appearance](../specs/RookCore/RookCore.spec.md), and [development tools](../specs/RookDevelopment/RookDevelopment.spec.md). Criteria are indexed in [INTENT.md](../INTENT.md).
