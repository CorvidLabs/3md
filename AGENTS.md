# 3md

Markdown with a Z axis. See [README.md](README.md) for the pitch and
[SPEC.md](SPEC.md) for the format definition. The implementation is the
`ThreeMD` Swift package.

## Project map

- `Sources/ThreeMD/` - the parser and serializer library.
- `Tests/ThreeMDTests/` - XCTest suite.
- `Examples/` - sample `.3md` documents.
- `specs/ThreeMD/` - the spec-sync contract for the library.
- `SPEC.md` - the authoritative format specification.

## Conventions

CorvidLabs Swift conventions apply: explicit access control, K&R braces, no
force unwrap, async/await only, Sendable across concurrency boundaries,
descriptive generic names, 4-space indentation, 120-column lines. The formatter
config in `.swift-format` enforces the mechanical parts.

<!-- CorvidLabs trust toolchain: BEGIN (managed, do not edit inside) -->
## CorvidLabs trust toolchain (standing rules)

This repo is governed by four CLIs. Every session MUST use them; never bypass or weaken them.

- fledge: run `fledge lanes run verify` before calling any change done. It must pass.
- spec-sync: when you change a module with a *.spec.md, update the spec, then `fledge spec check`. (skipped: <reason>, if content-only)
- augur: `augur check --staged` before a commit; `augur check --range origin/main..HEAD` before merge. A block verdict is a hard stop, never auto-overridden.
- attest: after a green lane, `attest sign --commit HEAD --reviewer agent:<id> --from-augur augur.json --tests-passed`.

CI enforces the same gate (.github/workflows/trust.yml) and fails if this block is missing. Brand rule: no em-dash characters in anything you write.
<!-- CorvidLabs trust toolchain: END -->
