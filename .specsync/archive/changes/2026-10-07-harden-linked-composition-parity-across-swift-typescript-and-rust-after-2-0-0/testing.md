---
change: harden-linked-composition-parity-across-swift-typescript-and-rust-after-2-0-0
artifact: testing
---

# Testing

Run the complete pinned Trust 1.2.2 gate with Fledge 1.7.2 on the exact implementation commit: lint, Swift build and tests, TypeScript typecheck, build and tests, Rust fmt, strict Clippy, tests and doctests, the nine-pair interchange, bundle drift and editor grammar. Run Swift, TypeScript and Rust suites, the interchange and the file-bundle host inside a Linux container and record toolchain versions. Finite cases are not exhaustive proof; Windows and musl execution are not established.

## Requirement evidence

| Requirement | Evidence | Result |
| --- | --- | --- |
| REQ-ThreeMD-036 | Swift DocumentFileCompositionTests, TypeScript file-composition and interchange-adapter tests, Rust file_composition and editing tests, shared files cases, complete pinned Trust at 4a0f8de and an earlier Linux container run | Pass: 283 Swift, 174 TypeScript, 67 Rust plus three doctests; 568 cases and 17,991 imports across nine pairs. Long-directory, attribute-bound order, lowered-limit, escape, cycle and ceiling cases agree. Linux for the final tree is the CI linux job; Windows and musl execution remain unverified. |
