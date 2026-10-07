---
change: remove-the-absolute-storage-size-ceilings-so-a-1-gb-5-gb-or-any-document-the-process-can-hold-is-parsed-and-saved-in
artifact: tasks
---

# Tasks

- [x] Raise storage defaults to the host maximum in Swift, TypeScript, and Rust.
- [x] Saturate the kind-2 D10 bound.
- [x] Widen length and count Vars to 10 bytes and keep coordinate Vars at 4 bytes.
- [x] Retarget Swift, TypeScript, and Rust tests that assumed the old defaults.
- [x] Update the two Var conformance vectors and their generator.
- [x] Update SPEC.md, the module spec, the README, the migration note, and the linked-file contract.
- [x] Run the focused tests and a local 1 GB round trip.
- [x] Run `fledge trust verify` before calling the change complete. The verify lane passed on this working tree (2026-10-07). Provenance stayed degraded because the change is uncommitted, and Augur's range `origin/main..HEAD` does not include it.
- [ ] Ask for definition approval. Do not self-approve, accept, or archive.
