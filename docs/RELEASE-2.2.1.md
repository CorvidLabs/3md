# ThreeMD 2.2.1

Status: the tag is `v2.2.1` on this release commit after hosted CI is green.
Publishing the GitHub release starts the existing workflows. npm serves 2.2.0
until `publish.yml` rewrites both packages from the tag. The Homebrew formula
`threemd` is 2.2.0 until `post-release-formula.yml` runs. crates.io still
serves `threemd` 2.1.0.

The 2.2.0 crate publish
([37859195832](https://github.com/CorvidLabs/3md/actions/runs/37859195832))
failed because `CRATES_IO_TOKEN` is not configured. This release does not add
that token. Do not say crates.io serves 2.2.1 unless `cargo-publish.yml` from
tag `v2.2.1` succeeds. The GitHub release body records that run as it finishes.
Swift resolves `from: "2.2.1"` from tag `v2.2.1`.

The format is unchanged. Text grammar 1.0, binary envelope version 1, payload
kinds 1 and 2, and composition profile `3md-composition-1` are the same as
ThreeMD 2.1.0. Swift, TypeScript, and Rust library behavior is the 2.1.0
library. The library source for that behavior remains `b70373b`. `SPEC.md` is
unchanged. LZFSE stays `compressionUnavailable` in the addon. Planes stay data.
The addon does not create gameplay nodes.

## The bug

After the editor import, the documented game path is:

```gdscript
var asset: ThreeMDDocumentAsset = load("res://examples/grove/scene.3md")
var document = asset.parsed()
```

On Godot 4.7.2 that `load()` failed outside the editor. The importer saves a
binary `.res` whose type string is the script class `ThreeMDDocumentAsset`.
`ClassDB.class_exists("ThreeMDDocumentAsset")` is false.
`ResourceFormatLoaderBinary` opens the file when the type hint is empty, and
it does not claim the path when the hint is that script class. Godot reports:

```text
No loader found for resource: res://.godot/imported/<file>.res (expected type: ThreeMDDocumentAsset)
```

The 2.2.0 headless suite never called `load()` on an imported document.
`showcase.gd` builds the asset with `ThreeMDDocumentAsset.from_text`. The
sample path `res://levels/grove.3md` is not a file in this repository.
`gdscript/examples/grove/scene.3md` is a real document. Its title is Grove.

## What changed

`gdscript/addons/threemd/document_format_loader.gd` is a
`ResourceFormatLoader` with `class_name ThreeMDDocumentFormatLoader`. Godot
registers that class from the global script class cache at startup, including
a running game, after an editor scan has seen it. Registering the loader only
from the `EditorPlugin` misses a running game, because the importer plugin is
editor-only. Copying `addons/threemd` is enough. A game does not add a second
script.

The loader claims only type `ThreeMDDocumentAsset` and extension `res`. For
any other type or path it refuses. `_load` calls:

```gdscript
ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
```

The empty type string lets the binary loader open the `.res`.
`CACHE_MODE_IGNORE` keeps that read off the import remap that called it. A
typed load of the same path would recurse. The importer's resource type stays
`ThreeMDDocumentAsset`.

Parser, storage, composition, and editing still do not open files.
`ThreeMDFiles` stays the only library script that reads a project path the
caller chose. The loader opens only the imported `.res` Godot already
selected.

## The example

`gdscript/examples/load_imported.gd` is headless. It does not spawn nodes. It
calls `load()` on `res://examples/grove/scene.3md` and on
`res://examples/grove/scene.3mdb`, then checks that each value is a
`ThreeMDDocumentAsset` whose title is Grove and whose plane labels are
Ground, Canopy, and HUD.

`scene.3mdb` is not committed. `gdscript/examples/write_grove_kind2.gd` writes
it with this addon's payload kind 2 encoder. `gdscript/tools/check.sh` imports
with the ThreeMD plugin enabled, writes that file, imports again, then runs
`load_imported.gd`. A `--script` check alone does not import. Godot import
cache, `.import` sidecars, `.uid` files, and `scene.3mdb` stay untracked.

The same script on the unmodified 2.2.0 addon exits non-zero. That log is
[docs/evidence/release-2.2.1/godot-load-repro.log](evidence/release-2.2.1/godot-load-repro.log).
It contains the no-loader line above.

On a `--script` `SceneTree`, `_init` runs before Godot registers custom
resource loaders. The example calls `load()` from `_initialize`, which runs
after that registration. A running game's `_ready` is also after it.

## Local checks

Godot on this machine is `4.7.2.stable.official.ed1daf0bf`. The check refuses
any binary that is not 4.7.x. `GODOT` overrides the binary. Nothing here
installs Godot, export templates, or packages, and the addon stays on 4.7.

`fledge run gdscript` (`bash gdscript/tools/check.sh`) passed. It printed
`LOAD IMPORTED OK`, then the nine existing scripts: number, NFC, text, binary,
composition, linked files, edit, layers, and showcase.

`fledge run gdscript-interchange` passed on protocol `3md-interchange-1`:
569 cases, 31984 imports, sixteen writer/reader pairs, each pair 1999.
Hosted CI does not install Godot. This suite is not in the verify lane. This
release does not add a weaker gate and does not add GDScript to `lanes.verify`.

The repository gate is pinned Fledge 1.7.2, `fledge trust verify`. Hosted CI
on this release commit must be green before the tag: Trust, Linux, UI,
Sculpt, Pages, and CodeQL. Godot stays a local check.

## Versions

| Surface | This repository | Published before this GitHub release |
| --- | --- | --- |
| Swift `ThreeMD` | tag `v2.2.1` after hosted CI | GitHub release `v2.2.0` |
| `@corvidlabs/threemd` | `2.2.1` in `js/package.json` | npm `2.2.0` |
| Rust `threemd` | `2.2.1` in `rust/Cargo.toml` | crates.io `2.1.0` |
| `@corvidlabs/three-md-element` | `2.2.1` in `element/package.json` | npm `2.2.0` |
| VS Code `corvidlabs.threemd` | `2.2.1` in `editor/vscode/package.json` | local VSIX only |
| Godot addon | `2.2.1` in `plugin.cfg` | copy from this repository |
| Homebrew `threemd` | formula in CorvidLabs/homebrew-tap | `2.2.0` (`e142a8c`) |

`publish.yml` publishes both npm packages and rewrites their version from the
tag. It does not use `NPM_TOKEN`. `cargo-publish.yml` publishes `rust/threemd`
only when `CRATES_IO_TOKEN` is set. `post-release-formula.yml` updates the
Homebrew formula after the source tarball exists. Those workflows are not
dispatched as a pre-check.

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
  This release does not approve it.
- `docs/evidence/release-2.1.0/` is still absent.
- `docs/evidence/release-2.2.0/` is still absent. The 2.2.1 evidence kept here
  is the unfixed `load()` log.

## Follow-ups

These are not in this release.

- CLI binary input, `convert` and `inspect`. Those commands stay text-only.
- Interchange protocol 2. The development adapter is still `3md-interchange-1`.
- The 2.0.0 reader compatibility job.
- The CI performance gate in `docs/design/threemd-2.1/perf-gate.md`.
- Hosted CI installing Godot and adding the addon to the verify lane.
- Composition edits beyond `replaceEntry`, and the full diagnostic report, in
  GDScript.
- A crates.io publish of `threemd` 2.2.1. That needs `CRATES_IO_TOKEN` and a
  successful `cargo-publish.yml` run. This release does not invent a token.
