# Lesson bundle — guarantee-portable-cross-language-document-and-composition-interchange-with-a-nine-pair-public-api-verification-matrix

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Guarantee portable cross-language document and composition interchange with a nine-pair public API verification matrix
- **Kind**: BugFix
- **Specs**: ThreeMD
- **Paths**: Sources/ThreeMD/, Tests/ThreeMDTests/, js/, rust/, conformance/, scripts/, Package.swift, fledge.toml, .specsync/config.toml, specs/ThreeMD/, SPEC.md, README.md, AGENTS.md, docs/EDITING-RELEASE.md, web/assets/three-md.js, Sources/ThreeMDInterop/
- **Acceptance**: Every Swift TypeScript and Rust producer exports interoperable readable text canonical text uncompressed binary and self-contained composition data that every consumer imports without losing supported values. A permanent bounded public-API matrix covers all nine producer-consumer pairings exact canonical bytes semantics numeric bit patterns Unicode and escaping stable identities revisions and graph preservation, with hostile input cases and every fixture mandatory. Resolve actual legacy parse/serialization compatibility defects without changing parser APIs or the frozen text grammar. Make JS typechecking declaration builds and Node package execution part of verification. Optional Apple LZFSE remains an explicitly documented capability pending the separate user compression choice; no claim that unsupported compressed input is portable. Existing archives and element/dist stay unchanged, no release merge main push or automatic Sculpt dependency update.

## Evidence

- Verification commit: `0eeb26a65421dd732dae37061a1e867d3d74d016`
- Base commit: `f44ba6704050752155c6324fc43854db35daac24`
- Verified by: `specsync check --spec ThreeMD --strict`

## From the change's context.md

# Context

Leif directly requested that all supported languages import and export each other's files. Swift, TypeScript and Rust already implement the portable extensions, but language-local fixtures do not execute the nine producer/consumer pairings. Audits identified Unicode trimming, source key collisions and link extraction differences. This scope adds executable interchange evidence and repairs confirmed compatibility defects while retaining APIs and the frozen grammar.

Work starts at PR62 head f44ba6704050752155c6324fc43854db35daac24 in an isolated checkout. Historical archives and element/dist remain untouched. Sculpt dependency adoption and release publication are separate. Portable text and uncompressed binary are mandatory. Apple LZFSE is an explicit optional capability while the separate user compression question is pending.

## From the change's design.md

# Design

A Swift development executable coordinates bounded JSON-lines adapters using public Swift, built TypeScript and Rust APIs. Requests carry kind and exact input bytes as hexadecimal. Responses carry canonical, binary and legacy text bytes, exact numeric bit patterns, semantic content, identity adoption and a deterministic atomic edit result. This is a test protocol, not a new public snapshot/patch wire format. Producers are tested independently against fixed expectations and then their outputs are imported by all consumers, including the same language. No library process or filesystem resolver is added.

Manifest case IDs and formats are mandatory, not optional skips. Canonical/profile/binary bytes must agree exactly; legacy text spelling may vary but must preserve its documented semantics. The existing canonical normalization of signed zero is explicit. Errors compare stable categories/codes, not localized prose. Core repairs align existing grammar interpretations and retain all legacy vectors. Rust uses sets for duplicate coordinates to avoid quadratic scans. Orchestration is Swift; adapters use the language under test.

## From the change's testing.md

# Testing

Execute every declared case through Swift, TypeScript and Rust producers and all nine pairings for canonical text, uncompressed binary and composition text/binary. Also test legacy text when its representable semantics apply. Fixed byte goldens anchor the independent expectation; deterministic finite-number and Unicode/quoting corpora exercise thresholds and scalar ordering. Reimport adopted and edited outputs and compare graph preservation, stable identities and canonical revisions. Mutate header/version/flags/CRC/length/UTF-8 and strict composition JSON; require all adapters to reject each expected invalid input without partial output. Fail on unknown or missing manifest cases.

Run Swift format/build/tests, Bun tests/typecheck/declaration build, Node built-package interchange, Rust format/clippy/tests, bundle drift and editor gates. Run the pinned full Trust 1.2.2 lane and forced strict SpecSync. Review source at the exact implementation commit. Record actual unsigned Attest limitations without weakening policy. Do not claim exhaustive all-input proof, on-device runtime coverage or portable LZFSE from these tests.

## Requirement evidence

| Requirement | Evidence | Result |
| --- | --- | --- |
| REQ-ThreeMD-033 | All three public adapters and nine-pair matrix; 82 shared source cases, 43 automatically discovered legacy JSON sources, 45 fixed numbers, 256 seeded numbers; exact byte/bit and adopted/edit checks | Pass: 426 cases, 16,983 imports, all nine pairs at source 6b6be79eeda12b7ff20b5a06b2c2470a94de0eee, optional LZFSE excluded explicitly |
| REQ-ThreeMD-034 | Mandatory catalog/count/format checks; Swift protocol and watchdog regressions; required JS typecheck/build/Node execution; complete pinned Trust and strict SpecSync; complementary scoped peer reviews | Pass: complete Trust at 55efdaab7efd2a12e78f3602af35c7e7b08322c0 and final matrix/harness at 6b6be79; official materialization recheck follows, with unsigned provenance limitation preserved |

## Verified source and commands

Root executed the complete pinned Trust 1.2.2 lane on source
55efdaab7efd2a12e78f3602af35c7e7b08322c0. It passed eight steps in 35.388
seconds: 244 Swift tests, 141 TypeScript tests, 31 Rust tests plus three
doctests, formatting/strict Clippy, JS package typechecking/declaration builds,
the 426-case Node/Swift/Rust interchange matrix, bundle drift and editor grammar.
Trust reported Augur proceed at risk 35 and the existing unsigned progressive
provenance degradation. It did not verify a permitted signature.

The final catalog guard source 6b6be79eeda12b7ff20b5a06b2c2470a94de0eee
also passed `swift run threemd-interchange`: 1,887 imports per pair, 16,983
total, with permanent exact-key, malformed/oversized stream and Unix watchdog
regressions. Original fixture source bytes and element/dist remain unchanged.
Three actual agent technical reviews passed with stated authorship and
complementary peer coverage, not independent human approval.

Raw receipts are retained at /private/tmp/3md-interchange-trust-final.log and
/private/tmp/3md-interchange-matrix-final.log. The official check records the
materialized contract and exact implementation commit separately.

## Where these lessons go

- `specs/ThreeMD/context.md`
