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
## CorvidLabs trust toolchain

This repository uses one trust gate. Every session must use it and must not bypass or weaken it.

- Run `fledge trust verify` before calling a change complete.
- Keep module specs synchronized with implementation changes.
- Treat an Augur block verdict as a hard stop that must be surfaced and de-risked.
- Record and verify provenance with Attest after the repository's verification lane passes.
- Keep generated trust configuration and this managed block in place.

<!-- CorvidLabs trust toolchain: END -->
