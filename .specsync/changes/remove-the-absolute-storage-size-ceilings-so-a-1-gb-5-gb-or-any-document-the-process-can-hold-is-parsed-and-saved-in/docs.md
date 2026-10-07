---
change: remove-the-absolute-storage-size-ceilings-so-a-1-gb-5-gb-or-any-document-the-process-can-hold-is-parsed-and-saved-in
artifact: docs
---

# Docs

- SPEC.md 11.1 D10 notes that the kind-2 bound saturates.
- SPEC.md 11.2 states the host-maximum default, the caller limit, the 32-bit integer, and that composition and edit ceilings stay.
- SPEC.md 11.3.3 splits the length and count Var (1 to 10 bytes) from the coordinate Var (1 to 4 bytes) and lists the 5 GB encoding.
- SPEC.md 11.3.11 and 11.3.12 match those rules.
- `specs/ThreeMD/ThreeMD.spec.md` rows for the five storage fields match the default. Composition and edit rows are unchanged.
- README.md "How big a file can be" replaces the 64 MB stop. The chart `docs/readme/size-ceiling.png` is removed.
- `docs/MIGRATION-2.1.md` and `docs/FILE-COMPOSITION.md` describe the new default.
- `docs/design/threemd-2.1/test-plan.md` says the 64 MiB memory files are samples under an explicit limit.
- `docs.3md` and `web/docs.3md` are regenerated from the README and SPEC.
