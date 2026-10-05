---
change: add-stable-document-identities-transactional-patches-and-diagnostics-for-release-preparation
artifact: design
---

# Design

Use additive Swift 6 Sendable value types and stateless services in ThreeMD. Identity interpretation and editing validation are opt-in above Parser/Serializer. The namespaced 3md-id attribute carries optional plane identities and reference identities within each owning composition entry, leaving any existing id attributes uninterpreted. Explicit adoption assigns missing IDs while preserving valid existing IDs. A patch works on an immutable snapshot and publishes only the fully validated result. Revision matching compares canonical expected content exactly rather than relying on a short noncryptographic hash. Document and composition patches share bounded operation/diagnostic policy and validate complete final graphs, allowing atomic coordinate swaps. No global mutable state, external resolver, process, filesystem or network operation is added. Preserve existing z links and HTML anchors without silent link rewrites. If link diagnostics are collected, first replace the remaining backtracking decimal predicate with the shared linear scanner and keep diagnostic work bounded and cancellable.
