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

## Binary and composition scope

Use SpecSync 6.0.0 for all lifecycle writers. The local binary is
`/Users/leif/.cargo/bin/specsync`; the development Fledge pin is 1.7.2 at
`/opt/homebrew/bin/fledge`. CI verifies the release checksums and pins Trust
1.2.2 to `bccd89c111d47778c97c5064fb62ab51695e04ea`.

Check the plugin's actual version. Fledge's installed plugin registry can take
priority over PATH; when it resolves an older Trust, invoke the isolated
`fledge-trust` 1.2.2 binary directly with the pinned Fledge on PATH. Do not
change the global plugin installation merely to run this checkout's gate.

The current scope adds general binary Document storage and self-contained
named Document references. Preserve the existing 1.0 text grammar, version
leniency, parser/serializer APIs, and cross-language text conformance. New
feature code is Swift-only; portable uncompressed storage is required and
Apple LZFSE is an optional conditional backend. Named references never perform
implicit filesystem or network reads. Voxel expansion and rendering are
application semantics, not ThreeMD behavior.

Leif directly approved this defined scope and full SpecSync 6 SDD. The actor
recording that definition is `agent:sculpture_exports`, acting under Leif's
direct authorization. The record does not claim Leif reviewed an implementation
diff and is not independent human review. Actual tests, implementation review,
signature/provenance and lifecycle completion remain separately evidenced.
Preserve the existing Attest trusted keys and reviewer identity restrictions;
do not identify another agent as `agent:claude` or invent signer evidence.

Root coordinates exact implementation commits, verification and authorized
feature-branch pull requests. A scope approval does not authorize an unreviewed
merge, tag, release, deployment or repository visibility change. Do not run the
shared verification lane concurrently with the coordinator.

<!-- CorvidLabs trust toolchain: BEGIN (managed, do not edit inside) -->
## CorvidLabs trust toolchain

This repository uses one trust gate. Every session must use it and must not bypass or weaken it.

- Run `fledge trust verify` before calling a change complete.
- Keep module specs synchronized with implementation changes.
- Treat an Augur block verdict as a hard stop that must be surfaced and de-risked.
- Record and verify provenance with Attest after the repository's verification lane passes.
- Keep generated trust configuration and this managed block in place.

<!-- CorvidLabs trust toolchain: END -->
