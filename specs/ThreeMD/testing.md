---
spec: ThreeMD.spec.md
---

## Test Plan

Tests assert public behavior and independent format/graph evidence. The existing
Swift text-parser, renderers, links, anchors, diagnostics and conformance suites
remain in Tests/ThreeMDTests. The TypeScript and Rust ports continue to run the
shared text vectors; new APIs do not claim parity in those ports.

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
