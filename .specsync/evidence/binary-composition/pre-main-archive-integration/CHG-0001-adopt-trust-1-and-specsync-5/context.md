---
change: CHG-0001-adopt-trust-1-and-specsync-5
artifact: context
---

# Context

The repository already has a real Fledge verify lane and separate SpecSync,
Augur, and Attest checks. This migration keeps the existing runner and language
setup while making Trust 1.0.0 the single orchestration surface.

SpecSync 5.0.1 enables its verified SDD policy, records this migration as a
no-product-contract change, and installs native workflows for Claude, Cursor,
Codex, and Gemini.
