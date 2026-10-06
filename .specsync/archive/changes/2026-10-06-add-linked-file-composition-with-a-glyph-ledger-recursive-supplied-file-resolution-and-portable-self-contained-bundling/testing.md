---
change: add-linked-file-composition-with-a-glyph-ledger-recursive-supplied-file-resolution-and-portable-self-contained-bundling
artifact: testing
---

# Testing

Execute every case in docs/FILE-COMPOSITION.md, preserve IDs and attributes, verify moved bundles without folders, lowered limits and cancellation, and all nine writer/reader pairs. Retain new evidence separately.

## Requirement evidence

| Requirement | Evidence | Result |
| --- | --- | --- |
| REQ-ThreeMD-035 | Swift DocumentFileCompositionTests, TypeScript file-composition tests, Rust file_composition tests and shared file inputs; complete pinned Trust at 2c544e0; literal semantic oracle; fresh descriptor host probe; exact-source Claude review with root source-equality check | Pass: 268 Swift, 157 TypeScript, 49 Rust plus three doctests; 479 cases and 17,451 imports across nine pairs. Metadata/IDs/sharing, error ordering and portable source-free imports pass. Claude scoped review passes. Linux/Windows runtime, optional LZFSE and signed provenance remain outside this evidence. |
