# 3md roadmap

Where the format and its tooling are headed. Confidence is a rough 0 to 100 read
on how sure we are a step is the right next move and will land cleanly.

## Now (2.0.0 packages, format 1.0 grammar)

The text grammar is 1.0 and frozen. SPEC.md 1.1 adds independently versioned
general binary storage, self-contained composition and linked file authoring.
ThreeMD 2.0.0 (released 2026-10-06) ships these in lockstep in the Swift
`ThreeMD` package, the TypeScript `@corvidlabs/threemd` library and the Rust
`threemd` crate: readable and uncompressed binary storage, composition,
`3md-files` linked file resolution and bundling, optional stable identities and
transactional typed patches. They are checked by the 43-vector text conformance
suite and a nine-pair public-API interchange gate. Also shipped: the `threemd`
CLI, an HTML renderer with Markdown rendering, cross-plane links, VS Code syntax
highlighting, the `<three-md>` component, two live demos (GitHub Pages and
corvidlabs.xyz) and an MIT license. Provenance is soft: Trust reports unsigned
degradation, and a permitted signed attestation remains an open gap.
State confidence: 93.

## Done (from this roadmap)

- Publish `@corvidlabs/threemd` to GitHub Packages (auto-published on release).
- Real Markdown rendering in `threemd html`.
- Cross-plane links (`[[z=N]]` / `[[z=N|text]]`).
- A third implementation: the Rust crate, conformance-verified.
- VS Code syntax-highlighting extension (`editor/vscode`, .vsix).
- 1.0 spec freeze: named frontmatter mini-format, relation to prior art, stability guarantees.
- Cross-browser demo tests (`uitests`, Playwright on Chromium + WebKit): a CI
  gate asserting the interactive lab renders, the focused plane stays frontmost
  while scrubbing, every axis tab and sampled gallery entries load, and the
  console stays clean. Guards the Safari-only 3D depth regression that z-index
  masks in Chromium.
- Publish the `threemd` crate to [crates.io](https://crates.io/crates/threemd)
  (v1.0.0, zero runtime deps), so all three implementations are installable from
  their native registries. The `cargo-publish` workflow failed for later
  releases because it rewrote the crate version and left the tree dirty; 2.0.0
  checks the committed version against the tag instead and publishes when the
  `CRATES_IO_TOKEN` secret is configured.
- General binary storage, self-contained composition, stable identities and
  transactional editing in Swift, TypeScript and Rust (2.0.0).
- Linked file composition with `3md-files` ledgers and portable bundles (2.0.0).
- A nine-pair cross-language public-API interchange gate (2.0.0).

## Versioning

Two independent numbers, kept distinct on purpose:

- The **format version** is **1.0** and frozen. It only changes if the *grammar*
  changes. SPEC.md 1.1 adds optional storage, composition and linked-file
  extensions with their own identifiers (binary envelope version 1,
  `3md-composition-1`, the `3md-files` metadata ledger) without new grammar.
  The grammar proposals in [docs/PROPOSALS.md](docs/PROPOSALS.md) (per-plane
  timing hints, `@asset`, `@include`) remain unimplemented, so the format is 1.0.
- Each implementation is its own package with its own semver. The Swift package
  (git tag v2.0.0), `@corvidlabs/threemd`, the `threemd` crate,
  `@corvidlabs/three-md-element` and the VS Code extension align at **2.0.0**.
  A bug fix bumps a package's patch; new tooling bumps its minor; neither
  changes the format version.

## Tooling shipped on the 1.0 line

These add capability without touching the frozen 1.0 grammar or the conformance
contract.

- The canonical `<three-md>` web component (`element/`,
  `@corvidlabs/three-md-element` 1.0.0): one framework-agnostic, tested
  interactive renderer backed by `@corvidlabs/threemd`. Replaces the bespoke
  renderer that was duplicated between the demo and the site and drifted (the
  Safari and Low-Power "focused plane never comes forward" bug had to be fixed
  twice). `web/index.html` and the corvidlabs.xyz site both consume it, so the
  demos and the shipped renderer are the same code. Tested in CI (Chromium +
  WebKit): focused plane frontmost while scrubbing, works with
  requestAnimationFrame paused (Low Power Mode), no horizontal overflow from
  320px to 1440px, clean console. Closes #1.
- Per-implementation spec-sync modules so every project (Swift, TypeScript,
  Rust, the web component) is tracked by `fledge spec check`, not just Swift.

## Next

| Step | Confidence | Notes |
|------|------------|-------|
| Prebuilt CLI binaries for Homebrew | 65 | The tap formula builds from source (needs Xcode 15+). Shipping per-platform release binaries (as the other CorvidLabs formulae do) would make `brew install` fast and Xcode-free. |
| VS Code Marketplace publish | 55 | The extension ships as a `.vsix` today; Marketplace + OpenVSX need a publisher account. Deferred until the format settles. |

Shipped since this table was first written: the Homebrew tap (`brew install
CorvidLabs/tap/threemd`), a static docs page (web/docs.html), the social-preview
image, and cross-browser CI for the demos.

## Later / open questions (SPEC.md section 13)

Designed in [docs/PROPOSALS.md](docs/PROPOSALS.md) (non-normative; the 1.0 grammar
is frozen). General binary storage (SPEC.md section 11) and host-supplied linked
files (section 12.3) now cover parts of proposals 4 and 3 without new grammar;
the items below remain open:

- Per-plane transition or timing hints for time and frame axes (confidence 88).
- Inline model/asset embeds (`@asset src="scene.glb"`) (confidence 70).
- Transclusion across documents (`@include`) (confidence 52).
- Portable compressed storage beyond Swift's optional Apple LZFSE backend (confidence 35).

## Out of scope

- Enforcing attest on the marketing site: its squash-merge, content-only flow
  does not fit signature enforcement. It stays advisory there. Confidence ~30.
