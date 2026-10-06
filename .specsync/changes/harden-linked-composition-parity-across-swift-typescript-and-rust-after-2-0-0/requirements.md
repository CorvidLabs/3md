---
change: harden-linked-composition-parity-across-swift-typescript-and-rust-after-2-0-0
artifact: requirements
---

# Requirements

- Resolve each ledger reference without work or memory proportional to the containing path: cache a repeated raw source per file and share the canonical target key.
- Refuse a ledger edge whose source-file attribute cannot fit the caller's maximumReferenceAttributeBytes while resolving it, computing the target length without building an over-long string, identically in all three ports.
- Accept strict optional `limits` and `documentLimits` objects in the development files interchange request, with correctly rounded integral number checks in every adapter.
- Add shared files cases for lowered limits and their order, the cached-subtree discovery ceiling, root and unreachable path grammar, ledger escapes, refusal order, existing and embedded ledger edges, rebundling, cycle spellings and the attribute bound.
- Add Swift and Rust tests that cancel a running resolution. Make TypeScript resolve independent of its `this` binding.
- Report adoption at the exact attribute bound with the same code in all three adapters through an additive Rust function, without changing public enums.
- Make the development file-bundle host compile on Darwin, Glibc and Musl, report an explicit unsupported-platform error elsewhere, and name failing paths.
- Add a Linux CI job running the Swift, TypeScript and Rust suites and the nine-pair interchange. Windows stays documented as unverified.
- Keep libraries free of file, process and network I/O and keep grammar, container, profile and public signatures unchanged.
