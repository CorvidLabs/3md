---
change: bring-bounded-binary-composition-and-transactional-editing-to-typescript-and-rust-with-shared-conformance
artifact: testing
---

# Testing

Both ports consume shared portable fixtures and verify fixed header/CRC vectors, UTF-8 and canonical metadata, exact streams/limits, hostile declarations, duplicate escaped JSON keys, invalid unused graph nodes, occurrence/depth budgets, stable identity preservation, stale UTF-8 revisions, final-only atomic swaps and rollback, cancellation and diagnostic preflight/truncation. Root adds matching Swift tests for shared vectors. Existing Swift/JS/Rust text conformance, generated element bundle drift and editor grammar must remain green. Source feature support does not claim LZFSE where no backend exists.
