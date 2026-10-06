# Lesson bundle — add-linked-file-composition-with-a-glyph-ledger-recursive-supplied-file-resolution-and-portable-self-contained-bundling

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Add linked file composition with a glyph ledger recursive supplied-file resolution and portable self-contained bundling in all three languages
- **Kind**: Feature
- **Specs**: ThreeMD
- **Paths**: Sources/ThreeMD, Sources/ThreeMDInterop, js, rust, scripts, conformance, SPEC.md, docs
- **Acceptance**: A parent Document maps printable ASCII glyphs to relative filenames, resolves supplied files recursively while preserving identities and shared children, and produces portable bundles; all three languages and all nine writer-reader pairs agree and refuse invalid paths, missing files, cycles, limits and cancellation.

## Evidence

- Verification commit: `9ac2454dfec51a9d575a030236f046462059f847`
- Base commit: `be41af523aecf041202a06d4c83471b19e09b275`
- Verified by: `specsync check --spec ThreeMD --strict`

## From the change's context.md

# Context

Leif directly approved linked authoring and portable self-contained bundling with 'ok do it'. Root owns definition, integration and publication; workers own bounded language APIs. No human diff review, signing authority, merge, release or historical rewrite is claimed.

## From the change's design.md

# Design

docs/FILE-COMPOSITION.md is normative. Core resolves pure supplied data. Bundling removes the external ledger and retains glyph/source-file provenance. Paths, entry naming and references are deterministic across languages.

## From the change's testing.md

# Testing

Execute every case in docs/FILE-COMPOSITION.md, preserve IDs and attributes, verify moved bundles without folders, lowered limits and cancellation, and all nine writer/reader pairs. Retain new evidence separately.

## Requirement evidence

| Requirement | Evidence | Result |
| --- | --- | --- |
| REQ-ThreeMD-035 | Swift DocumentFileCompositionTests, TypeScript file-composition tests, Rust file_composition tests and shared file inputs; complete pinned Trust at 2c544e0; literal semantic oracle; fresh descriptor host probe; exact-source Claude review with root source-equality check | Pass: 268 Swift, 157 TypeScript, 49 Rust plus three doctests; 479 cases and 17,451 imports across nine pairs. Metadata/IDs/sharing, error ordering and portable source-free imports pass. Claude scoped review passes. Linux/Windows runtime, optional LZFSE and signed provenance remain outside this evidence. |

## Where these lessons go

- `specs/ThreeMD/context.md`
