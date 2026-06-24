# 3md roadmap

Where the format and its tooling are headed. Confidence is a rough 0 to 100 read
on how sure we are a step is the right next move and will land cleanly.

## Now

Shipped and verified: a defined format (SPEC.md); three parsers in lockstep
(Swift `ThreeMD`, TypeScript `@corvidlabs/threemd`, and the Rust `threemd` crate)
proven equivalent by a 42-vector conformance suite; a `threemd` CLI; an HTML
renderer with Markdown rendering; cross-plane links; nine examples; two live demos
(GitHub Pages and corvidlabs.xyz); MIT license; and enforcing signed
attestations. State confidence: 92.

## Done (from this roadmap)

- Publish `@corvidlabs/threemd` to GitHub Packages (auto-published on release).
- Real Markdown rendering in `threemd html`.
- Cross-plane links (`[[z=N]]` / `[[z=N|text]]`).
- A third implementation: the Rust crate, conformance-verified.

## Next

| Step | Confidence | Notes |
|------|------------|-------|
| Editor support (VS Code extension) | 70 | Syntax highlighting and live preview for `.3md`. The biggest adoption lever; larger, separate effort. |
| 1.0 spec freeze plus a "relation to prior art" section | 64 | Decide the frontmatter-vs-YAML question, lock the grammar, compare to CommonMark directives and reveal.js, then freeze. Let the 0.x line bake first. |

## Later / open questions (SPEC.md section 8)

- Inline model embeds (`@model src="scene.glb"`).
- Transclusion across documents.
- Per-plane transition or timing hints for time and frame axes.
- A binary or compressed container for large scenes.

## Out of scope

- Enforcing attest on the marketing site: its squash-merge, content-only flow
  does not fit signature enforcement. It stays advisory there. Confidence ~30.
