# ThreeMD

## ADDED

### REQUIREMENT REQ-ThreeMD-030

TypeScript and Rust SHALL expose bounded general-document uncompressed binary and self-contained composition APIs compatible with the Swift format.

Acceptance Criteria
- Readers identify complete magic and enforce exact streams, CRC, UTF-8 and allocation limits.
- Unsupported compression is explicit; LZFSE is unavailable without a platform backend.
- Rust may use exact unicode-normalization 0.1.25 solely for canonical key comparison; no compression dependency is introduced. This records the reviewed Unicode parity repair to the original dependency-free plan.
- Composition validates strict duplicate-aware JSON, all definitions and graph budgets without external I/O.

### REQUIREMENT REQ-ThreeMD-031

TypeScript and Rust SHALL expose namespaced stable identities, exact canonical-byte revision snapshots, atomic typed patches and bounded structured diagnostics.

Acceptance Criteria
- IDs survive metadata/body/order/position/target edits and legacy id metadata stays opaque.
- Final-only validation supports coordinated swaps and invalid later operations publish no partial result.
- Exact stale revisions, budgets and cooperative cancellation reject safely.
- Diagnostics retain actual line/path evidence and preflight work before expensive validation.

### REQUIREMENT REQ-ThreeMD-032

All language implementations SHALL share verified portable extension vectors and accurate capability contracts while preserving existing text conformance.

Acceptance Criteria
- Shared vectors exercise canonical numeric and Unicode edge cases, fixed envelopes, composition and identities in Swift, TypeScript and Rust.
- Existing parser/serializer APIs, conformance vectors, viewer behavior and historical archives remain unchanged. The generated web bundle may refresh deterministic compiler output from the new module graph; element/dist stays untouched.
- Complete pinned Trust and strict SpecSync pass with actual scoped agent review and honest provenance limits.
- PRs remain open for Leif and no release or Sculpt dependency migration occurs.
