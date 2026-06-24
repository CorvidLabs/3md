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

## Next

| Step | Confidence | Notes |
|------|------------|-------|
| VS Code Marketplace publish | 55 | The extension ships as a `.vsix` today; Marketplace + OpenVSX need a publisher account. Deferred until the format settles. |
| Docs site (Astro) + Homebrew tap + social-preview image | 60 | Remaining flagship-presentation polish. Each is a standalone follow-up. |

## Later / open questions (SPEC.md section 8)

- Inline model embeds (`@model src="scene.glb"`).
- Transclusion across documents.
- Per-plane transition or timing hints for time and frame axes.
- A binary or compressed container for large scenes.

## Out of scope

- Enforcing attest on the marketing site: its squash-merge, content-only flow
  does not fit signature enforcement. It stays advisory there. Confidence ~30.
