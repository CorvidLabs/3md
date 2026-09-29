---
change: CHG-0001-adopt-trust-1-and-specsync-5
artifact: research
---

# Research

The previous workflow duplicated lifecycle, contract, risk, and provenance
ordering in each repository. Trust 1.0.0 provides the same ordered gates from a
committed `.trust.toml` policy and pins SpecSync 5.0.1 internally.

The consumer workflow pins Trust's immutable 1.0.0 commit. Existing dependency
setup remains before the Trust step, and provenance remains progressive until
the repository has a durable remote notes ledger.
