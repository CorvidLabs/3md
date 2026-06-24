# 3md roadmap

Where the format and its tooling are headed. Confidence is a rough 0 to 100 read
on how sure we are a step is the right next move and will land cleanly.

## Now (v1.0)

The format is at version 1.0 (stable, frozen grammar). Shipped and verified: a
frozen spec (SPEC.md) with a named frontmatter mini-format and a relation-to-prior-art
section; three parsers in lockstep (Swift `ThreeMD`, TypeScript
`@corvidlabs/threemd`, the Rust `threemd` crate) proven equivalent by a 43-vector
conformance suite; a `threemd` CLI; an HTML renderer with Markdown rendering;
cross-plane links; nine examples; VS Code syntax highlighting; two live demos
(GitHub Pages and corvidlabs.xyz); MIT license; and enforcing signed attestations.
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

## 1.1 - additive tooling (the format stays frozen at 1.0)

Version 1.1 is tooling only. It does not touch the 1.0 grammar or the
conformance contract; it makes 3md easier to embed and extend.

- The canonical `<three-md>` web component (`element/`, published as
  `@corvidlabs/three-md-element`): one framework-agnostic, tested interactive
  renderer backed by `@corvidlabs/threemd`. Replaces the bespoke renderer that
  was duplicated between the demo and the site and drifted (the Safari and
  Low-Power "focused plane never comes forward" bug had to be fixed twice).
  `web/index.html` now consumes the component, so the demo and the shipped
  renderer are the same code. Tested in CI (Chromium + WebKit): focused plane
  frontmost while scrubbing, works with requestAnimationFrame paused (Low Power
  Mode), no horizontal overflow from 320px to 1440px, clean console. Closes #1.
- Format-feature proposals for a future minor version live in
  [docs/PROPOSALS.md](docs/PROPOSALS.md) (per-plane timing hints, `@asset`,
  `@include`, a container), each designed to be additive.

## Next

| Step | Confidence | Notes |
|------|------------|-------|
| Publish `threemd` to crates.io | 80 | The crate is publish-ready (`cargo publish --dry-run` is clean) but not yet on crates.io, so Rust users currently consume it as a git dependency. A `cargo-publish` workflow is in place; it needs a `CRATES_IO_TOKEN` secret, then it publishes on release like the npm package. |
| Prebuilt CLI binaries for Homebrew | 65 | The tap formula builds from source (needs Xcode 15+). Shipping per-platform release binaries (as the other CorvidLabs formulae do) would make `brew install` fast and Xcode-free. |
| VS Code Marketplace publish | 55 | The extension ships as a `.vsix` today; Marketplace + OpenVSX need a publisher account. Deferred until the format settles. |

Shipped since this table was first written: the Homebrew tap (`brew install
CorvidLabs/tap/threemd`), a static docs page (web/docs.html), the social-preview
image, and cross-browser CI for the demos.

## Later / open questions (SPEC.md section 8)

Designed in [docs/PROPOSALS.md](docs/PROPOSALS.md) (non-normative; the 1.0 grammar
is frozen and nothing there is implemented yet):

- Per-plane transition or timing hints for time and frame axes (confidence 88).
- Inline model/asset embeds (`@asset src="scene.glb"`) (confidence 70).
- Transclusion across documents (`@include`) (confidence 52).
- A binary or compressed container for large scenes (confidence 35).

## Out of scope

- Enforcing attest on the marketing site: its squash-merge, content-only flow
  does not fit signature enforcement. It stays advisory there. Confidence ~30.
