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
- Publish the `threemd` crate to [crates.io](https://crates.io/crates/threemd)
  (v1.0.0, zero runtime deps), so all three implementations are installable from
  their native registries. A `cargo-publish` workflow keeps it in sync on release.

## Versioning

Two independent numbers, kept distinct on purpose:

- The **format version** is **1.0** and frozen. It only changes if the *grammar*
  changes. A future **format 1.1** would mean new directives or attributes - the
  additive proposals in [docs/PROPOSALS.md](docs/PROPOSALS.md) (per-plane timing
  hints, `@asset`, `@include`, a container). None of those are implemented, so
  the format is 1.0.
- Each implementation is its own package with its own semver, all currently at
  **1.0.0** for parity because they all implement format 1.0: the Swift package
  (git tag v1.0.0), `@corvidlabs/threemd` (npm 1.0.0), the `threemd` crate
  (crates.io 1.0.0), and the `<three-md>` component (`@corvidlabs/three-md-element`
  1.0.0). A bug fix bumps a package's patch; new tooling bumps its minor;
  neither changes the format version.

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
