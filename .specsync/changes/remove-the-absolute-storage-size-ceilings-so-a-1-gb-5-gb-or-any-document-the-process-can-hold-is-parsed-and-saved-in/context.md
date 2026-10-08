---
change: remove-the-absolute-storage-size-ceilings-so-a-1-gb-5-gb-or-any-document-the-process-can-hold-is-parsed-and-saved-in
artifact: context
---

# Context

ThreeMD 2.1 storage refused any input longer than 64 MiB (67,108,864 bytes). The same absolute ceiling covered decoded bytes. Records stopped at 8 MiB and could be raised only to 64 MiB. Planes stopped at 65,536 and physical lines at 100,000. A 1 GB document, including a cube of 1024 by 1024 by 1024 letters, was refused before the payload was read.

The request is to parse and save a 1 GB document, a 5 GB document, or any larger document the process can hold. A new smaller cap is not a fix. Callers can still pass a lower positive limit. Zero and negative limits stay `invalidLimits`.

Composition profile ceilings (1,024 definitions, 20 MiB profile bytes, and the rest of SPEC.md 12.2) and edit budgets (4,096 operations, 64 MiB diagnostic and payload bytes) stay. They are not the document storage path.

Kind 2 is not yet tagged. Widening length and count integers before `v2.1.0` does not break a published kind-2 reader. Existing small kind-2 files stay byte-identical because small values keep their minimal encoding and coordinate integers stay 4 bytes.

On a 32-bit process the host integer stops near 2 GiB. That is the language. JavaScript rejects a limit above `Number.MAX_SAFE_INTEGER`. A hostile file can exhaust memory. The library does not add a hidden stop to prevent that.

This work is on `leif/uncapped-documents` in the `fix-main-clippy` worktree, based on `d5f0730`. It does not tag `v2.1.0`, does not merge pull request 73, and does not touch the primary checkout.
