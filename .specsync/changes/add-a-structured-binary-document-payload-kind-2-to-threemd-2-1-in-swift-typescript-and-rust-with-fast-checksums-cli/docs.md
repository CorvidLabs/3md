---
change: add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli
artifact: docs
---

# Docs

Two rules apply to every file below (SB-35): every statement about binary payloads names the payload kind, and no
speed ratio is quoted without its language, runtime and baseline. Kind-2 speedups are quoted only against the bounded
text decode and the 2.1 kind-1 decoder (never against the slow-CRC 2.0 kind 1). Historical files
(`docs/RELEASE-2.0.0.md`, earlier evidence under `docs/evidence/`, archived SpecSync changes) stay unchanged.

## Contract (WP0, WP8)

| File | Change |
|---|---|
| `SPEC.md` | Version 1.2. Section 11 second paragraph (`.binary` writes kind 2, `encodeTextContainer` writes kind 1, extension `.3mdb` for both kinds); 11.1 header rows, payload kind table and the D1 to D14 validation order with the CRC implementation note; 11.2 kind bounds, byte-order keys for the payload, the frozen whitespace set and `encodeTextContainer`; new 11.3 (normative), 11.4 (rationale) and 11.5 (reserved extension points); 12.1, 12.2 and 12.3 binary envelopes and bundles as kind 2 and kind 3 refusal; a section 13 bullet for kind 3, a key table and an indexed archive |
| `specs/ThreeMD/*` | The kind-2 API, the `.binary` behavior change, the error mapping, `containerInfo`, `encodeTextContainer`, the Rust number fix and the Swift frozen whitespace set, with requirement IDs and test references |
| `specs/ThreeMDCLI/*` | Binary input for every subcommand, the storage failure line and JSON fields, `convert`, `inspect` |
| `specs/ThreeMDElement/*` | The bundle invariant: no storage code (marker list) and the 50,000-byte budget; the Purpose sentence says the package version follows the ThreeMD release version |
| `docs/design/threemd-2.1/test-plan.md`, `docs/design/threemd-2.1/perf-gate.md` (new) | The specification package's test plan and performance gate, each with a note that maps the package's paths to repository paths and lists the adaptations made on copying. Every "test-plan section" and "perf-gate section" reference in this change, the specs, `conformance/structured/README.md` and `scripts/structured/generate.mjs` points here |

## User documentation (WP9)

| File | Change |
|---|---|
| `README.md` | "Binary storage and reusable documents" rewritten for kind 2: `.binary` writes the structured payload; `encodeTextContainer` for ThreeMD 2.0 readers; `containerInfo` and `supportedPayloadKinds`; the container description says which kind holds canonical text; measured load times quoted per language and runtime against the bounded text decode and the 2.1 kind-1 decoder; binary composition bundles as kind-2 envelopes; kind 3 reserved. The sentence that the command-line tool keeps its text behavior changes. "Command-line tool" gains binary input, `convert` and `inspect` with examples |
| `docs/MIGRATION-2.1.md` (new) | From the API in `design.md`: what changes for users (`.binary` now writes kind 2), who must act (writers whose files ThreeMD 2.0.x must read switch to `encodeTextContainer`; 2.0 applications should present `unsupportedPayloadKind(2)` as "this file needs a newer ThreeMD"), what does not change (enums, signatures, limits, `isBinary`, composition text), the two `validate` corrections (Rust powers of two, Swift whitespace set W), TypeScript key enumeration order, converting 2.0 `.3mdb` files in both directions, and the three migration snippets |
| `docs/RELEASE-2.1.0.md` (new) | Release scope, capability matrix per language, verification evidence (verify lane, Linux workflow, compatibility job, perf gate receipts, fuzz counts, Trust), and the release limits: LZFSE Apple-only, text-only element and VS Code surfaces, the Unicode 13.0 guarantee on the pinned toolchains, Linux performance report-only until calibrated, Windows unverified |
| `docs/FILE-COMPOSITION.md` | Line 8: sharing writes the readable profile, or that profile stored as payload kind 2 (kind 1 through `encodeTextContainer`). Line 28: supplied children may be text or payload kind 1 or 2; a kind-3 child is refused with `unsupportedPayloadKind(3)` |
| `docs/EDITING-RELEASE.md` | The capability matrix gains 2.1 rows: structured binary payload (kind 2), `encodeTextContainer` and `containerInfo`, the fast CRC, CLI binary support, in all three languages |
| `js/README.md` | The 2.0.0 capability sentence (line 8) and the format line (line 79) updated for 2.1: kind 2 from `DocumentStorageFormat.binary()`, `encodeTextContainer`, `containerInfo`, `DocumentPayloadKind`, LZFSE still unavailable |
| `Examples/README.md` | The fixture table gains a structured (kind 2) column with `canopy.structured.3mdb` and `shared-grove.structured.3mdb` ("six actual fixtures" becomes eight); the manifest note mentions `payloadKind`; the closing paragraph says the CLI now reads, converts and inspects `.3mdb` files while the hosted viewer stays text-only |
| `Examples/LinkedVillage/README.md` | A `.3mdb` bundle destination now writes the profile as payload kind 2; `--text-container` writes kind 1 for ThreeMD 2.0 readers |
| `conformance/README.md` | Lists `conformance/structured/` (anchors, worked examples, vectors, sizes) and the four `*.structured.3mdb` extension files |
| `CHANGELOG.md` | 2.1.0 entry: the `.binary` behavior change, the new APIs in each language, the CLI binary support, the Rust number fix (92 powers of two), the fast CRC (kind-1 decode now within 10% of text), the Swift whitespace fix, interchange protocol 2, the perf gate, and the reserved kind 3 |
| `ROADMAP.md` | 2.1 delivered; later items: payload kind 3 (structured composition), a key-table layout, an indexed archive for partial loading, a portable compression codec |
| `AGENTS.md` | The current scope paragraph for 2.1: Leif's decisions, the decisions made under his delegation, the executing agent, the pinned toolchains and the limits on merge, tag and release |
| `docs.3md`, `web/docs.3md` | Regenerated with `scripts/build-docs-3md.mjs` after the SPEC, README, CHANGELOG and ROADMAP edits; the docs drift check must pass |

## Conformance and protocol documentation (WP1, WP6)

| File | Change |
|---|---|
| `conformance/structured/README.md` (new) | Layout of the directory, the `3md-structured-golden-1` and `3md-structured-vectors-1` schemas, the step labels used by vectors, and the annotated worked examples |
| `conformance/interchange/README.md` | 83 source cases (49 valid, 34 invalid) instead of 82 and 33; the new request and per-pair output totals with `textContainer`, the vectors and the fixed protocol cases |
| `conformance/interchange/PROTOCOL.md` | Protocol `3md-interchange-2`: the optional `limits` object (shape, validation order, input decode only), `binaryHex` as kind 2, `textContainerHex`, `structuredReplay` (development only) |

## API documentation in source (WP2 to WP5, WP8)

| File | Change |
|---|---|
| `Sources/ThreeMD/DocumentStorage.swift`, `DocumentStorageCodec.swift` | Doc comments for the new declarations; the `DocumentStorageFormat`, `.binary(compression:)`, `encode`, `decode` and type comments; the `invalidContainer` and `unsupportedPayloadKind` comments and descriptions |
| `js/src/storage.ts` | JSDoc for `DocumentPayloadKind`, `DocumentContainerInfo`, `supportedPayloadKinds`, `containerInfo`, `encodeTextContainer` and the changed `encode` and `decode` behavior |
| `rust/src/storage.rs`, `rust/src/lib.rs` | Rustdoc for the constants, `DocumentContainerInfo`, `container_info`, `encode_text_container` and the changed behavior, with doc tests |
| `Sources/CLI/main.swift` | Usage text for binary input, `convert` and `inspect` |

## Release evidence and versions (WP10, WP12)

| File | Change |
|---|---|
| `docs/evidence/release-2.1.0/` (new) | `fuzz.json` (release-volume counts and seeds), the perf receipts per language, runtime and OS, and the interchange receipt |
| `js/package.json`, `rust/Cargo.toml`, `rust/Cargo.lock`, `element/package.json`, `editor/vscode/package.json` | Version 2.1.0 |
| `element/README.md` (lines 29 to 33), `editor/vscode/README.md` (lines 25 to 34) | 2.1.0, `threemd-2.1.0.vsix` and the `docs/RELEASE-2.1.0.md` link instead of 2.0.0, `threemd-2.0.0.vsix` and `docs/RELEASE-2.0.0.md`; the text-only statements stay |

## Found outside the specification plan

`element/README.md` (lines 29 to 33) and `editor/vscode/README.md` (lines 25 to 34) name version 2.0.0, the
`threemd-2.0.0.vsix` file and `docs/RELEASE-2.0.0.md`, which go stale when WP10 moves both packages to 2.1.0. The
specification plan did not list them. Both are now in `affected_paths`, and WP10 updates them (table above), as the
2.0.0 release change did for the same lines.
