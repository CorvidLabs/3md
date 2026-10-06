---
change: add-linked-file-composition-with-a-glyph-ledger-recursive-supplied-file-resolution-and-portable-self-contained-bundling
artifact: testing
---

# Testing

Execute every case in docs/FILE-COMPOSITION.md, preserve IDs and attributes, verify moved bundles without folders, lowered limits and cancellation, and all nine writer/reader pairs. Retain new evidence separately.

## Requirement evidence

| Requirement | Evidence | Result |
| --- | --- | --- |
| REQ-ThreeMD-035 | Swift DocumentFileCompositionTests, TypeScript file-composition tests, Rust file_composition tests and 33 new shared file inputs; complete pinned Trust at ad17806; descriptor host probe; complementary source review repairs | Pass: 264 Swift, 153 TypeScript, 43 Rust plus three doctests; 459 cases and 17,343 imports across nine pairs. Metadata/IDs/sharing and portable source-free imports pass. Separate Claude review, Linux/Windows runtime and signed provenance remain open. |
