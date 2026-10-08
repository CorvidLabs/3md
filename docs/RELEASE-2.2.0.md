# ThreeMD 2.2.0

Status: tag `v2.2.0`, GitHub release published 2026-10-08. npm serves 2.2.0.
crates.io still serves `threemd` 2.1.0.

Tag `v2.2.0` points at `54a6f30`. The GitHub release is
[v2.2.0: Godot 4.7 addon](https://github.com/CorvidLabs/3md/releases/tag/v2.2.0).
npm serves `@corvidlabs/threemd` and `@corvidlabs/three-md-element` at 2.2.0.
The Homebrew formula `threemd` is 2.2.0 (`e142a8c` in CorvidLabs/homebrew-tap).
The crate publish failed because `CRATES_IO_TOKEN` is not configured, so
crates.io stayed at 2.1.0. Swift resolves `from: "2.2.0"` from the tag.
Hosted CI on `54a6f30` passed before the tag: Trust
[37857306140](https://github.com/CorvidLabs/3md/actions/runs/37857306140),
Linux [37857306051](https://github.com/CorvidLabs/3md/actions/runs/37857306051),
UI [37857306031](https://github.com/CorvidLabs/3md/actions/runs/37857306031),
Sculpt [37857306180](https://github.com/CorvidLabs/3md/actions/runs/37857306180),
Pages [37857306029](https://github.com/CorvidLabs/3md/actions/runs/37857306029),
and CodeQL
[37857305168](https://github.com/CorvidLabs/3md/actions/runs/37857305168).

The format is unchanged. Text grammar 1.0, binary envelope version 1, payload
kinds 1 and 2, and composition profile `3md-composition-1` are the same as
ThreeMD 2.1.0. Swift, TypeScript, and Rust library behavior is the 2.1.0
library. The library source for that behavior remains `b70373b`.

## What is new

The Godot 4 addon in `gdscript/` parses, saves, composes, and edits documents
on Godot 4.7.2. Copy `gdscript/addons/threemd` into a project's `addons`
folder and enable ThreeMD. The editor imports `.3md` and `.3mdb` as
`ThreeMDDocumentAsset` resources and does not change the open scene.

The addon covers the text file, payload kind 1, payload kind 2, composition,
linked files from bytes the caller supplies, and revision-checked document
edits. Parser, storage, composition, and editing scripts do not open files.
`ThreeMDFiles` reads project paths a game has already chosen. Examples live
in `gdscript/examples`. Planes stay data. A game maps them onto nodes it owns.

Local checks on the addon, before this notes commit, were the Godot 4.7.2
headless suite and the sixteen-pair interchange on protocol
`3md-interchange-1`: 569 cases, 31984 imports, each writer/reader pair 1999.
The hosted verify lane stays on the nine Swift, TypeScript, and Rust pairs.
Hosted CI does not install Godot.

Sculpt.3md was already nested at `apps/sculpt` after tag `v2.1.0`. Its
package name stays Rook. Its compact `.3mdb` is not the upstream binary
standard. This version does not publish the app.

## Versions

| Surface | This repository | Published |
| --- | --- | --- |
| Swift `ThreeMD` | tag `v2.2.0` | GitHub release `v2.2.0` |
| `@corvidlabs/threemd` | `2.2.0` in `js/package.json` | npm `2.2.0` |
| Rust `threemd` | `2.2.0` in `rust/Cargo.toml` | crates.io `2.1.0` |
| `@corvidlabs/three-md-element` | `2.2.0` in `element/package.json` | npm `2.2.0` |
| VS Code `corvidlabs.threemd` | `2.2.0` in `editor/vscode/package.json` | local VSIX only |
| Godot addon | `2.2.0` in `plugin.cfg` | copy from this repository |
| Homebrew `threemd` | formula in CorvidLabs/homebrew-tap | `2.2.0` |

## Limits that stay

- LZFSE is refused by the Godot addon (`compressionUnavailable`). Uncompressed
  storage is the portable contract. LZFSE stays Apple-only in Swift.
- Composition editing in GDScript implements `replaceEntry` only.
- The full diagnostic report is not ported to GDScript.
- The element and the VS Code extension stay text surfaces.
- The VS Code extension is a local VSIX and is not in a marketplace.
- Windows execution is not verified. Linux CI runs the three library suites
  and the nine-pair interchange. It does not run Godot.
- The SpecSync definition for the Godot addon is still an unapproved draft.
  This preparation does not approve it.
- `docs/evidence/release-2.2.0/` is not in this preparation.
- `docs/evidence/release-2.1.0/` is still absent.

## Follow-ups

These are not in this preparation.

- CLI binary input, `convert` and `inspect`. Those commands stay text-only.
- Interchange protocol 2. The development adapter is still `3md-interchange-1`.
- The 2.0.0 reader compatibility job.
- The CI performance gate in `docs/design/threemd-2.1/perf-gate.md`.
- Hosted CI installing Godot and adding the addon to the verify lane.
- Composition edits beyond `replaceEntry`, and the full diagnostic report, in
  GDScript.

## Publish result

The GitHub release, both npm packages, and the Homebrew formula shipped.
The crate did not. Configure `CRATES_IO_TOKEN` and rerun `cargo-publish.yml`
from tag `v2.2.0` before telling anyone that crates.io serves 2.2.0.
