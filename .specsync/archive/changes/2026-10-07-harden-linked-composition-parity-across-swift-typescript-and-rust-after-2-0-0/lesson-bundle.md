# Lesson bundle — harden-linked-composition-parity-across-swift-typescript-and-rust-after-2-0-0

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Harden linked composition parity across Swift TypeScript and Rust after 2.0.0
- **Kind**: Feature
- **Specs**: ThreeMD
- **Paths**: Sources/ThreeMD, Sources/ThreeMDInterop, Tests, js, rust, conformance, docs, CHANGELOG.md, .github, AGENTS.md
- **Acceptance**: Swift TypeScript and Rust resolve linked files without work or memory that grows with the containing path and refuse over-bound edges at discovery in the same order; shared files cases covering caller limits and refusal order and path grammar and escapes and the cached-subtree ceiling agree in all nine pairs; Swift and Rust cancellation during resolution returns no partial result; the development file-bundle host compiles on Darwin and Glibc and Musl and names failing paths; Linux runs of all three suites and interchange are recorded and a Linux CI job runs them

## Evidence

- Verification commit: `fbbcf2b5fed9475f8c203973933ad8b1af5ed4f1`
- Base commit: `ca2d1e34f20be3c5100d0fd1474a8ee9cc78d2d4`
- Verified by: `specsync check --spec ThreeMD`

## From the change's context.md

# Context

ThreeMD 2.0.0 shipped linked file composition. A read-only parity audit of main 9ac2454 and two adversarial reviews of the follow-up work found no result divergence for ordinary inputs, but found that per-reference discovery work and memory grew with the containing path (for a 1 MiB directory with 16,356 references, Swift took 56 s and about 16 GB and Rust 14 s and about 14 GB), that over-bound source-file edges were refused only after discovery, that caller limits and several refusal orders were testable only per language, that Rust parsed long limit literals and reported adoption at the exact attribute bound differently, and that Swift and Rust lacked mid-operation cancellation tests.

This change was prepared on 2026-10-06 under Leif's direct request to continue 3md release preparation, while another session owned the 2.0.0 release itself. The implementation was written on an unpublished local branch under an earlier definition (local commit cdf01b7, approved by agent:claude before implementation) that also listed release documentation. Leif then split the work: the release session delivered the release documentation, CLI build fix and publish workflows in PR69, and this follow-up keeps only the parity hardening, the Linux CI job and its own documentation. This definition records that narrowed scope on a branch from the released main ca2d1e3. No merge, tag, release, package publication or deployment is part of it.

## From the change's design.md

# Design

Each discovered file records its normalized directory end offsets once. A per-file map from raw ledger source to (canonical path, depth) avoids repeated resolution and visits, and edges hold the shared canonical key. Before visiting a target, the resolver computes its UTF-8 length from the recorded offsets plus the source suffix and refuses with referenceAttributesExceeded when 17 bytes of glyph and source-file overhead plus the path exceed the caller's bound. Within one reference, record-bound and path-grammar refusals still precede it, and it precedes cycle, depth and missingFile. Adapter limit objects map field-for-field onto each port's limits types. The Rust adapter adopts entries through an additive editing function and builds the graph with DocumentComposition::new to report the specific composition error.

## From the change's testing.md

# Testing

Run the complete pinned Trust 1.2.2 gate with Fledge 1.7.2 on the exact implementation commit: lint, Swift build and tests, TypeScript typecheck, build and tests, Rust fmt, strict Clippy, tests and doctests, the nine-pair interchange, bundle drift and editor grammar. Run Swift, TypeScript and Rust suites, the interchange and the file-bundle host inside a Linux container and record toolchain versions. Finite cases are not exhaustive proof; Windows and musl execution are not established.

## Requirement evidence

| Requirement | Evidence | Result |
| --- | --- | --- |
| REQ-ThreeMD-036 | Swift DocumentFileCompositionTests, TypeScript file-composition and interchange-adapter tests, Rust file_composition and editing tests, shared files cases, complete pinned Trust at 4a0f8de and an earlier Linux container run | Pass: 283 Swift, 174 TypeScript, 67 Rust plus three doctests; 568 cases and 17,991 imports across nine pairs. Long-directory, attribute-bound order, lowered-limit, escape, cycle and ceiling cases agree. Linux for the final tree is the CI linux job; Windows and musl execution remain unverified. |

## Where these lessons go

- `specs/ThreeMD/context.md`
