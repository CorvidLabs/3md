---
change: add-stable-document-identities-transactional-patches-and-diagnostics-for-release-preparation
artifact: testing
---

# Testing

Test identity retention across text and binary; coordinate changes retain IDs; legacy no-ID documents remain valid; duplicate/invalid IDs and missing targets report paths. Test exact stale revision rejection, all-or-nothing multi-operation failure, operation limits, cancellation and Codable round trips. Preserve old text conformance. Execute pinned Trust 1.2.2 with Fledge 1.7.2 and SpecSync 6.0.0, including Swift/TypeScript/Rust existing checks and generated bundle drift. Tests and signer policy evidence are distinct.

