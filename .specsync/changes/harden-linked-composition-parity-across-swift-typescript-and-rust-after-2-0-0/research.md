---
change: harden-linked-composition-parity-across-swift-typescript-and-rust-after-2-0-0
artifact: research
---

# Research

The parity audit compared DocumentFileComposition.swift, js/src/file-composition.ts and rust/src/file_composition.rs line by line. Two adversarial review passes of the follow-up confirmed the directory-scaling, Rust literal-rounding, Rust adoption-code and shared-case defects, with measured before and after timings for a 1 MiB directory in all three ports.
