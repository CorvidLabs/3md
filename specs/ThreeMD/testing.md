---
spec: ThreeMD.spec.md
---

## Test Plan

Tests assert public behavior and independent format/graph evidence. The existing
Swift text-parser, renderers, links, anchors, diagnostics and conformance suites
remain in Tests/ThreeMDTests. The TypeScript and Rust ports continue to run the
shared text vectors. The ThreeMD 2.1 structured payload (payload kind 2) claims
byte-for-byte parity in all three ports and is verified as described in
"Structured Payload Verification (ThreeMD 2.1)" below.

DocumentStorageTests.swift, DocumentStorageBoundsTests.swift and
DocumentStorageCompressionTests.swift cover the new general storage boundary.
ParserNumericTests.swift preserves the accepted finite ASCII decimal grammar
for every coordinate. DocumentStorageDecimalTests.swift covers long malformed
decimals in readable and correctly checksummed binary input, plus deterministic
cancellation after preflight when the parser fails.
DocumentCompositionTests.swift and DocumentCompositionCodecTests.swift cover
the graph and readable profile. Presence of tests is not a passing receipt;
root records actual results against the implemented revision.

## Storage Verification

- Round-trip Unicode, mixed axes, metadata, finite coordinates, literal quotes
  and backslashes in text, uncompressed binary and conditional LZFSE.
- Inspect the exact 40-byte header, little-endian fields and independently
  calculated CRC, including the standard 123456789 check vector.
- Reject truncated, corrupt, trailing, concatenated, wrong-version/kind/flags,
  nonzero-reserved and unknown-compression containers.
- Verify decoded-byte declarations are bounded before allocation, plus lowered
  limits for input/output, records, lines and planes.
- Reject a 4 KiB decimal with an invalid suffix through readable input and an
  otherwise valid binary envelope without quadratic backtracking. Preserve
  optional signs, fractions and exponents and reject nonfinite/non-ASCII forms.
- Reject nonfinite coordinates, repeated Z, reserved-key collisions and direct
  values that cannot round-trip faithfully.
- On platforms without Compression, verify explicit unavailability rather than
  silently changing the requested format.
- Verify task cancellation propagates without a partial result on supported
  concurrency runtimes. Cancellation checks use an availability guard for
  macOS 10.15/iOS 13/tvOS 13/watchOS 6 and later; earlier Apple runtimes no-op
  that check without raising the package deployment baseline.
  A synchronous internal parser injection cancels its current task immediately
  before a real parse failure, proving cancellation takes priority without
  timing races or a public API change.

## Structured Payload Verification (ThreeMD 2.1)

Payload kind 2 (SPEC.md 11.3) is verified in Swift, TypeScript and Rust unless a
line says otherwise. Every item below runs in `fledge lanes run verify`, and
therefore in the Linux workflow and Trust, with three exceptions. The ThreeMD
2.0.0 compatibility job and the performance gate run on their own, as their
items say; only the size gate G6 of the performance gate also runs in the unit
tests. The i686 Rust test runs in the Linux workflow and the arm64_32 compile on
the macOS performance job. The full test plan is
`docs/design/threemd-2.1/test-plan.md`, and the performance gate is
`docs/design/threemd-2.1/perf-gate.md`.

- **Goldens.** `conformance/structured/` holds the kind-2 anchors of the 45 valid
  interchange cases without an extension source (including the profile
  envelopes of `composition-empty-root` and `composition-shared-dag-unused`) and
  the three SPEC.md 11.3.17 worked examples (`worked-document`, `worked-numbers`,
  `worked-keys`, CRCs `8A5B3B70`, `DB5A2326`, `649EB26B`), with `manifest.json`
  (schema `3md-structured-golden-1`) and `sizes.json`.
  `conformance/extensions/*.structured.3mdb` (4 files) and
  `Examples/Extensions/{canopy,shared-grove}.structured.3mdb` sit next to their
  kind-1 files. For each golden, every port checks: `.binary(.none)` of the
  bounded text decode equals the file byte for byte; decode equals that
  document (Swift compares `utf8` and number bit patterns); re-encode equals the
  file; `containerInfo` reports version 1, kind 2, compression 0, flags 0,
  reserved 0, equal lengths and the manifest CRC; `encodeTextContainer` equals
  the kind-1 anchor where one exists; composition envelopes decode to the
  readable composition; and the SHA-256 matches the manifest. Every committed
  2.0 `.3mdb` stays byte-unchanged. `scripts/structured/generate.mjs --check`
  regenerates the fixtures and fails on any difference, and on any string
  outside the Unicode 13.0 set of `scripts/structured/unicode-13.0-assigned.json`.
- **Hostile, edge and limit vectors.** `conformance/structured/vectors.json`
  (schema `3md-structured-vectors-1`) holds 156 vectors, 142 under `invalid/`
  and 14 under `limits/`. Each names the SPEC.md 11.3 step that decides it,
  optional limits (29 vectors carry limits, which decide their outcome),
  `expected` (an error code or `ok`) and `expected20` (the ThreeMD 2.0.0
  reader's outcome). Every port decodes every vector under its limits and must
  return exactly `expected`; the LZFSE vector is skipped by the Swift LZFSE
  backend. Per-port writer vectors (TypeScript lone surrogates and key merges,
  the Rust equivalent-key map, the Swift dictionary) and Unicode 17 skew vectors
  stay in each port's own suite.
- **Unit tests.** `Tests/ThreeMDTests/DocumentStorageStructuredTests.swift`,
  `js/test/structured.test.ts` and `rust/tests/structured.rs` cover Var
  boundaries and V1 to V3, the number forms and zigzag edges, the CRC check
  value `0xCBF43926` and the slicing loop against a bytewise reference, the
  Swift UTF-8 rule (including repairs that keep the input length), chunked
  UTF-8 validation at 65,535, 65,536, 65,537 and 200,000 bytes, the TypeScript
  two-call chunked decoding test (a body ending in `E2 82`, then a version
  starting with `AC 62`, both `invalidUTF8`), the segment scanner G1 to G6, the
  canonical text metrics against the real 2.0 writer, byte-order keys and NFC
  equivalence, `containerInfo` (no magic, 8 to 39 bytes with the magic, 40 bytes
  and more), `encodeTextContainer` against every kind-1 anchor and the 2.0
  writer's error order, the writer cap edges and −0 normalization, and Swift
  LZFSE round trips with the kind-2 D10 bound.
- **Frozen whitespace set and number spelling.** A Swift test pins the 19 W
  scalars and the excluded spaces U+0085, U+000B, U+000C, U+180E, U+2028 and
  U+FEFF. All three ports spell the 4,318 vectors of
  `conformance/extensions/numeric-powers.json` (schema
  `3md-canonical-numbers-1`: every signed power of two and ±10^k for k from −30
  to 30) and the 45 existing numeric vectors; the existing Rust tie tests still
  pass.
- **Differential fuzzing.** Seeded properties P1 to P8: totality, canonical
  bijection, text agreement, cross-port outcomes on a replayed mutation blob,
  writer and reader agreement, equivalence with the 2.1 `validate` under
  standard and lowered limits, identical cross-port writer bytes and number
  canonicality. CI runs the CI volume on every push; the release-candidate
  volume (10^6 per port for P6) runs once on the release tip and is recorded in
  `docs/evidence/release-2.1.0/fuzz.json`. A failing case is minimized into
  `vectors.json`.
- **Limits, cancellation and platforms.** Typed cancellation with no partial
  result at every SPEC.md 11.3.13 point; an amplification case that L3 or L4
  rejects with no Phase Q parse; peak memory under 4 times the input for the
  64 MiB worst cases; TypeScript buffer ownership and Swift `Data` slices with a
  nonzero `startIndex`; Swift 32-task concurrency under TSan and Rust
  `Send + Sync`; `cargo test --target i686-unknown-linux-gnu --test structured`
  and a watchOS arm64_32 compile for 32-bit arithmetic; the full suites in the
  Linux container.
- **Interchange protocol 2.** `swift run threemd-interchange` speaks
  `3md-interchange-2`: document and composition requests accept an optional
  `limits` object applied to the input decode only, responses add
  `textContainerHex` (kind 1) while `binaryHex` becomes kind 2, the catalog
  (schema `3md-interchange-catalog-2`, 83 source cases: 49 valid and 34 invalid)
  renames the 2.0 `binaryFile` to `textContainerFile`, names a kind-2
  `binaryFile` for every valid case and replays all 156 vectors under their
  limits. `invalid-binary-kind` now expects `checksumMismatch` and the new
  `invalid-binary-kind-3` expects `unsupportedPayloadKind`. Every reader
  consumes every writer's kind 1 and kind 2 in all nine pairs, and the files
  cases cover kind-1, kind-2 and refused kind-3 children.
- **ThreeMD 2.0.0 compatibility.** `fledge run compat-2-0` and the `compat-2-0`
  Linux workflow job, not the verify lane, check out `v2.0.0` and prove that its
  adapters return `unsupportedPayloadKind` for the 54 kind-2 anchors and
  `expected20` for the 127 limit-free vectors, and that its libraries return
  `expected20` for all 156 vectors under their limits.
- **Performance gate.** The separate `perf` lane, `scripts/bench/gate.mjs` and
  `.github/workflows/perf.yml` enforce kind-2 decode at most 0.25 of the bounded text decode time (G1) and
  faster than the legacy parser (G2), kind-1 decode within 1.10 of the bounded
  text decode (K1), and the size gate G6 (always blocking, also in the unit
  tests through `conformance/structured/sizes.json`). Floors block on macOS
  arm64 from the first run; calibrated ceilings block after two calibration
  runs; Linux reports only until it is calibrated.
- **Migrations.** Every existing test and fixture that assumed `.binary` meant
  kind 1 moves to `encodeTextContainer` or gains the kind-2 expectation, as
  section 10 of `docs/design/threemd-2.1/test-plan.md` lists per file.

## Composition Verification

- Preserve repeated and nested references with one source per ID, ordered
  reference attributes, Unicode and mixed document axes.
- Inspect canonical sorted definition output and reload the profile through the
  existing text parser and generic binary storage.
- Remove imported original files and retain in-memory lookup, proving the
  library performs no automatic external resolution.
- Reject unsafe/duplicate IDs, missing root/targets, cycles including unused
  nodes, depth, unique-byte/reference/occurrence and per-reference attribute
  excesses.
- Reject malformed/noncanonical outer documents, unknown and duplicate JSON
  fields (including escaped aliases), oversized/deep JSON and unsupported schemas.
- Assert available task cancellation remains distinct from validation failures.

## Canonical Extension Fixtures

Examples/Extensions contains canopy and shared-grove in readable text,
portable uncompressed binary and optional Apple LZFSE binary. The actual Swift
generator encoded all six files, decoded them back to equal Document or
DocumentComposition values, and wrote manifest.json with exact bytes/SHA256.
The focused new test run passed 43 XCTest methods according to root's actual
receipt. This is focused storage/graph evidence; the retained complete native
lane and closing lifecycle checks remain separate.

The canopy is a small ordinary space-axis document. The grove has one reusable
canopy definition and an opaque A character binding in its root document.
ThreeMD stores that declared reference without interpreting the characters as
placements, and binary wrapping preserves the same complete profile.

## Required Repository Gates

Use SpecSync 6.0.0 and Fledge 1.7.2. Trust must report 1.2.2 and be the isolated
latest plugin when the machine's installed plugin registry resolves an older
version. The authoritative workflow pins Trust's immutable release commit.

```text
specsync check --strict --force --require-coverage 100
fledge lanes run verify
fledge trust verify
specsync change check implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2
```

ThreeMD 2.1 adds the structured fixture check (`scripts/structured/generate.mjs
--check`) to the verify lane. It also adds the ThreeMD 2.0.0 compatibility task
`compat-2-0` (also a job in the Linux workflow) and a separate `perf` lane
(`bench-inputs`, `bench-storage`, `perf-gate`), neither of which is part of
`verify`. The macOS performance job is a required check for release branches and
tags.

The verify lane retains Swift format/build/tests, TypeScript tests, Rust
format/clippy/tests, generated web-component drift and VS Code grammar tests.
Browser UI checks are a separate existing lane; no new web behavior is added.
SpecSync check is structural contract validation, not a product-test runner.

Root owns the shared verification lane, preserves failed attempts, records
actual definition/implementation/review/finalization stages, and publishes the
authorized feature PR. Existing Attest identities and keys stay unchanged;
scope approval is not an independent human review or trusted signature.
The new full lane, strict contract and closing lifecycle evidence are pending
until root supplies actual receipts.

## Lifecycle prerequisite order

SpecSync 6 requires every prerequisite checkbox complete before change check.
Later review, publication and finalization belong to explicit pending milestones,
not checked-off promises. Task prose and requirement-evidence additions change
the definition digest; root must append an actual approval refresh with its own
agent claim before checking this scheduling correction. The feature scope and
approved semantic delta remain unchanged.

Root then runs the retained full native lane and pinned Trust gate, materializes
and checks the named change, and commits the real implementation/evidence as
required by the tool. A committed implementation and fresh verification are
prerequisites for scoped review. The workflow-v2 finalization command requires
current scoped review, then archives on the existing PR before any merge; its
handoff is not merge or release authority.

Three existing accepted workflow-v1 records are preserved:
CHG-0001-adopt-trust-1-and-specsync-5,
CHG-0002-assign-stable-requirement-ids, and
CHG-0003-address-final-trust-and-sdd-governance-review-corrections.
The workflow-v2 cutoff establishes their historical eligibility, not a blanket
waiver for changed delivery inputs. Root's actual audit determines whether any
accepted record is stale. If stale, use the tool's audited reopen and fresh
verification/closing acceptance path, preserving the old definition and evidence
history. Legacy records use accept then archive; finalize explicitly refuses
workflow-v1. Exact semantic-successor obligations must be declared before
approval, not silently inserted into the approved current change.

Reviewer labels in SpecSync are stable claims, not authenticated identities.
Actual peer review can be described as peer-agent evidence. It does not satisfy
an independent human claim or an Attest trusted-signer policy by relabelling the
agent as human or Claude. Unavailable provenance authority remains a reported
limitation while the configured policy stays intact.
