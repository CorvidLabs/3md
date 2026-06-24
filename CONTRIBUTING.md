# Contributing to 3md

Thanks for your interest. 3md is a small, plain-text format with three parsers
kept in lockstep by a shared conformance suite. The most important rule:
**behavior changes must land in every implementation and be pinned by a
conformance vector.**

## Layout

- `Sources/ThreeMD/` - the canonical Swift parser, serializer, and HTML renderer.
- `js/` - the TypeScript package (`@corvidlabs/threemd`).
- `rust/` - the Rust crate (`threemd`).
- `conformance/` - shared JSON vectors. Both `Tests/ThreeMDTests/ConformanceTests`
  and `js/test/conformance.test.ts` and `rust/tests/conformance.rs` run them.
- `Examples/` - sample `.3md` documents.
- `SPEC.md` - the authoritative format specification.
- `editor/vscode/` - the syntax-highlighting extension.
- `web/` - the standalone interactive demo (served on GitHub Pages).

## The gate

One command runs everything (Swift format check, build, tests, and the Rust
crate):

```bash
fledge lanes run verify
```

Run it before calling any change done. Per language:

```bash
swift test                                   # Swift
cd js && bun install && bun test             # TypeScript
cd rust && cargo test                        # Rust
```

## Changing the format

1. Update `SPEC.md` first: it is the contract.
2. Add or update a vector in `conformance/` that pins the new behavior.
3. Implement it in all three parsers (Swift, TypeScript, Rust) so every
   conformance suite passes.
4. Add language-level unit tests where useful.

A change that only lands in one implementation will fail the others' conformance
runs. That is the point.

## House rules

- No em-dash characters in committed text (brand rule). Use commas, colons,
  parentheses, or hyphens.
- Swift follows the CorvidLabs conventions (see AGENTS.md); `swift-format` and
  the `.swift-format` config enforce the mechanical parts.
- Keep the library targets dependency-free (Foundation for Swift, std for Rust,
  no runtime deps for the TS package).

## Trust toolchain

This repo is governed by the CorvidLabs trust toolchain (fledge, spec-sync,
augur, attest). See AGENTS.md for the standing rules; CI enforces the same gate.
