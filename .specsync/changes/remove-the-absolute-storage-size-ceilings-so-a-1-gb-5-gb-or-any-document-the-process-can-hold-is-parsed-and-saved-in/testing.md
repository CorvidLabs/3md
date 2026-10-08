---
change: remove-the-absolute-storage-size-ceilings-so-a-1-gb-5-gb-or-any-document-the-process-can-hold-is-parsed-and-saved-in
artifact: testing
---

# Testing

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| UC-01 | REQ-ThreeMD-043 | Swift `testADocumentPastTheOldCeilingRoundTrips`, Rust `a_document_past_the_old_ceiling_round_trips`, TypeScript "a document past the old 64 MiB ceiling round-trips". Each encodes and decodes a body of 64 MiB + 1 letters as text and as kind 2, and a document of 100,001 lines of `a`. A local cube of 1024 by 1024 by 1024 letters was encoded and decoded as text and as kind 2 in Swift, TypeScript, and Rust, and the three writers produced the same bytes (text 1,074,804,681, kind 2 1,074,796,532). Rust also saved one plane of 5,368,709,120 letters `a`. Those runs are not committed. |
| UC-02 | REQ-ThreeMD-043 | Swift `testLimitsArePositiveAndHaveNoAbsoluteCeiling`, the Rust test above, and the TypeScript constructor test accept a 5 GB limit value and reject 0. TypeScript also rejects `Infinity` and `Number.MAX_SAFE_INTEGER + 1`. |
| UC-03 | REQ-ThreeMD-043 | Swift and Rust unit-test the bytes of 2^28 and of 5 GB without allocating them. TypeScript decodes a 5-byte length of 2^28 with no body as `lengthMismatch`, and ten continuation bytes as `invalidContainer`. `var-five-bytes` expects `lengthMismatch`. |
| UC-04 | REQ-ThreeMD-043 | Existing kind-2 goldens. Coordinate `ff ff ff ff 01` stays `invalidContainer` in the TypeScript `withZ` case and the Rust `coordinate_var` case. `var-four-continuation-truncated` is a length and expects `lengthMismatch`. |
| UC-05 | REQ-ThreeMD-043 | Swift `testStandalonePathsAndLedgersPastTheOldRecordSizeAreSaved`, the Rust file-composition path test, and the TypeScript ledger test save an 8 MiB + 1 path. Composition `limits-invalid-above-ceiling` still rejects 1,025 definitions. |
| UC-06 | REQ-ThreeMD-043 | Review of SPEC.md, `specs/ThreeMD/ThreeMD.spec.md`, README.md, `docs/MIGRATION-2.1.md`, and `docs/FILE-COMPOSITION.md`. |

## Commands

- `swift test --filter DocumentStorageBoundsTests`
- `swift test --filter DocumentFileCompositionTests`
- `bun test js/test/storage.test.ts js/test/structured.test.ts js/test/file-composition.test.ts`
- `cargo test --test extensions a_document_past_the_old_ceiling_round_trips`
- `cargo test --test structured`
- `fledge trust verify` before the change is called complete

CI does not allocate 1 GB or 5 GB. The 64 MiB memory and mid-CRC samples keep an explicit limit.
