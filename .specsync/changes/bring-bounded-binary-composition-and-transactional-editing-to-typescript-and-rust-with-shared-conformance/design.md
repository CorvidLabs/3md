---
change: bring-bounded-binary-composition-and-transactional-editing-to-typescript-and-rust-with-shared-conformance
artifact: design
---

# Design

Portable uncompressed envelope uses the same 40-byte little-endian header, canonical UTF-8 payload and CRC as Swift. Composition keeps supplied definitions once and validates all nodes without I/O. A strict bounded duplicate-aware JSON scanner precedes ordinary decoding. Existing parse/serialize remains source compatible; new canonical storage/editing formatting is tested against shared Swift fixtures. Snapshots stage ordered operations privately, preserve optional namespaced IDs and compare complete canonical bytes. TypeScript may use AbortSignal and Rust a clonable atomic cancellation token; cancellation remains explicit and cooperative. LZFSE is recognized but reports unavailable without a platform backend.
