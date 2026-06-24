# 3md roadmap

Where the format and its tooling are headed. Confidence is a rough 0 to 100 read
on how sure we are a step is the right next move and will land cleanly.

## Now (v0.3.0)

Shipped and verified: a defined format (SPEC.md), two parsers in lockstep (Swift
`ThreeMD` and TypeScript `@corvidlabs/threemd`) proven equivalent by a 36-vector
conformance suite, a `threemd` CLI, an HTML renderer, nine examples, MIT license,
and enforcing signed attestations. State confidence: 90.

## Next

| Step | Confidence | Notes |
|------|------------|-------|
| Publish `@corvidlabs/threemd` to npm | 88 | Built, typed, conformance-tested, README-ready. Lowest-effort distribution win. |
| Real Markdown rendering in `threemd html` | 82 | Render plane bodies to HTML instead of raw `<pre>`, so the CLI is a true previewer. Keep the core library dependency-free. |
| Cross-plane links (`[[z=2]]` or `@link`) | 75 | The most-missed authoring feature (stories, changelogs, maps). A format change for a 0.4: spec, both parsers, vectors. |
| A third implementation (for example Rust) | 72 | Proves the conformance suite lets someone build an independent parser, not just hand-port. |
| Editor support (VS Code extension) | 70 | Syntax highlighting and live preview for `.3md`. The biggest adoption lever; larger, separate effort. |
| 1.0 spec freeze plus a "relation to prior art" section | 64 | Decide the frontmatter-vs-YAML question, lock the grammar, compare to CommonMark directives and reveal.js, then freeze. Let 0.3 bake first. |

## Later / open questions (SPEC.md section 8)

- Inline model embeds (`@model src="scene.glb"`).
- Transclusion across documents.
- Per-plane transition or timing hints for time and frame axes.
- A binary or compressed container for large scenes.

## Out of scope

- Enforcing attest on the marketing site: its squash-merge, content-only flow
  does not fit signature enforcement. It stays advisory there. Confidence ~30.
