---
change: remove-the-absolute-storage-size-ceilings-so-a-1-gb-5-gb-or-any-document-the-process-can-hold-is-parsed-and-saved-in
artifact: plan
---

# Plan

1. Point `DocumentDecodeLimits` defaults at the host maximum in Swift, TypeScript, and Rust. Reject only non-positive values, and in TypeScript any value outside the safe-integer range.
2. Saturate the kind-2 D10 product and subtraction in Swift and TypeScript. Rust already saturates.
3. Read and write length and count Vars at up to 10 bytes. Keep coordinate Vars at 4 bytes. Keep minimal encodings of small values.
4. Retarget tests that allocated `standard.maximumRecordBytes + 1` or expected the old default to refuse 64 MiB + 1, 65,537 planes, or 100,001 lines. Pass an explicit historical limit where the test is a sample of cancellation or memory. Assert success for a path and a document past the old record and byte ceilings.
5. Update `var-five-bytes` and `var-four-continuation-truncated` expected codes, and the generator that writes them.
6. Update SPEC.md, the module spec, the README, the migration note, the linked-file contract, and the test-plan notes. Remove the README chart that says decoding stops at 64 MiB.
7. Prove a real 1 GB text and kind-2 round trip locally. Do not commit that allocation and do not add it to CI.
8. Run the focused Swift, Bun, and Rust tests, then `fledge trust verify`. Definition approval stays with the user. Do not tag `v2.1.0`.
