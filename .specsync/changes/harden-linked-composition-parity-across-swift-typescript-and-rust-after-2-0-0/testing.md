---
change: harden-linked-composition-parity-across-swift-typescript-and-rust-after-2-0-0
artifact: testing
---

# Testing

Run the complete pinned Trust 1.2.2 gate with Fledge 1.7.2 on the exact implementation commit: lint, Swift build and tests, TypeScript typecheck, build and tests, Rust fmt, strict Clippy, tests and doctests, the nine-pair interchange, bundle drift and editor grammar. Run Swift, TypeScript and Rust suites, the interchange and the file-bundle host inside a Linux container and record toolchain versions. Finite cases are not exhaustive proof; Windows and musl execution are not established.
