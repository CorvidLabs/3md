# Linked composition parity hardening

## ADDED

### REQUIREMENT REQ-ThreeMD-036

The Swift, TypeScript and Rust linked-composition resolvers SHALL resolve ledger references without work or memory that grows with the containing file's path, SHALL refuse a ledger edge whose source-file attribute cannot fit the caller's reference attribute byte bound while resolving it, after record-bound and path-grammar refusals and before cycle, depth and missing-file refusals for that reference, and SHALL produce the same results and refusal categories for caller limits, refusal order, path grammar, ledger escapes, cycles and the cached-subtree discovery ceiling, verified through shared files interchange cases in all nine writer/reader pairs. Cancellation during resolution SHALL publish no partial result. The libraries SHALL remain free of file, process and network I/O, and grammar, container, profile and public signatures SHALL remain unchanged. The libraries SHALL build and pass their suites on Linux; Windows execution remains unverified unless separately established.

Acceptance Criteria:
- A multi-megabyte containing directory with thousands of references resolves or refuses quickly in all three ports.
- Lowered-limit, refusal-order, path-grammar, escape, cycle, ceiling, attribute-bound and rebundle cases pass identically in all nine pairs.
- Swift and Rust cancellation during a running resolution returns cancellation with no result.
- A Linux CI job runs all three suites and the interchange.
