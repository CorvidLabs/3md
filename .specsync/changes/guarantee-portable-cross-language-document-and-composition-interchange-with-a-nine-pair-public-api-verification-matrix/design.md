---
change: guarantee-portable-cross-language-document-and-composition-interchange-with-a-nine-pair-public-api-verification-matrix
artifact: design
---

# Design

A Swift development executable coordinates bounded JSON-lines adapters using public Swift, built TypeScript and Rust APIs. Requests carry kind and exact input bytes as hexadecimal. Responses carry canonical, binary and legacy text bytes, exact numeric bit patterns, semantic content, identity adoption and a deterministic atomic edit result. This is a test protocol, not a new public snapshot/patch wire format. Producers are tested independently against fixed expectations and then their outputs are imported by all consumers, including the same language. No library process or filesystem resolver is added.

Manifest case IDs and formats are mandatory, not optional skips. Canonical/profile/binary bytes must agree exactly; legacy text spelling may vary but must preserve its documented semantics. The existing canonical normalization of signed zero is explicit. Errors compare stable categories/codes, not localized prose. Core repairs align existing grammar interpretations and retain all legacy vectors. Rust uses sets for duplicate coordinates to avoid quadratic scans. Orchestration is Swift; adapters use the language under test.
