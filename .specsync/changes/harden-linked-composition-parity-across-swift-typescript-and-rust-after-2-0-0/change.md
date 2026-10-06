---
id: harden-linked-composition-parity-across-swift-typescript-and-rust-after-2-0-0
state: implementing
type: feature
base_commit: ca2d1e34f20be3c5100d0fd1474a8ee9cc78d2d4
---

# Harden linked composition parity across Swift TypeScript and Rust after 2.0.0

## Intent

Harden linked composition parity across Swift TypeScript and Rust after 2.0.0

## Affected Canonical Specs

- `ThreeMD`

## Acceptance Criteria

- Swift TypeScript and Rust resolve linked files without work or memory that grows with the containing path and refuse over-bound edges at discovery in the same order; shared files cases covering caller limits and refusal order and path grammar and escapes and the cached-subtree ceiling agree in all nine pairs; Swift and Rust cancellation during resolution returns no partial result; the development file-bundle host compiles on Darwin and Glibc and Musl and names failing paths; Linux runs of all three suites and interchange are recorded and a Linux CI job runs them

## No-spec Rationale

Not applicable
