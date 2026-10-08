---
change: remove-the-absolute-storage-size-ceilings-so-a-1-gb-5-gb-or-any-document-the-process-can-hold-is-parsed-and-saved-in
artifact: requirements
---

# Requirements

IDs `UC-01` to `UC-06` are local to this change. The canonical requirement is `REQ-ThreeMD-043` in `deltas/ThreeMD.md`. Unless a requirement names a port, it holds in Swift, TypeScript, and Rust.

## Storage size

- **UC-01 No absolute storage ceiling.** `DocumentDecodeLimits` keeps its five fields. Each default is the largest positive integer the host can use: Swift `Int.max`, Rust `usize::MAX`, TypeScript `Number.MAX_SAFE_INTEGER`. A document larger than 64 MiB, including a 1 GB document and a 5 GB limit value, is parsed and saved as text and as payload kind 2 when the process can hold it. CI does not allocate 1 GB or 5 GB.
- **UC-02 Caller limits.** A caller can set any lower positive limit. A non-positive limit is `invalidLimits`. JavaScript also rejects a value that is not an integer in `1 ... Number.MAX_SAFE_INTEGER`. The kind-2 D10 bound `min(maximumEncodedBytes − 40, 2 × maximumDecodedBytes)` saturates at the host maximum.
- **UC-03 Wide length integers.** A length or count Var is minimal unsigned LEB128 of 1 to 10 bytes. A continuation on the 10th byte, or a value that does not fit in 64 bits, is `invalidContainer`. A value that fits in 64 bits but not the host integer is `oversizedOutput`. `80 80 80 80 01` is 2^28. `80 80 80 80 14` is 5,368,709,120. `ff ff ff ff 01` is 2^29 − 1 and is a legal length.
- **UC-04 Coordinate integers stay 4 bytes.** Form 1 still uses a 1 to 4 byte Var. A 4th coordinate byte with `0x80` set is `invalidContainer`. Integer-form coordinates stay inside −2^27 through 2^27 − 1. Small kind-2 files stay byte-identical.
- **UC-05 Other ceilings stay.** Composition profile ceilings and edit budgets are unchanged. File-composition standalone path and ledger checks read the standard document `maximumRecordBytes`, which is now the host maximum, so a path the process can hold is saved.
- **UC-06 Prose matches the libraries.** SPEC.md 11.2, 11.3.3, 11.3.11, and 11.3.12, the ThreeMD module spec, the README, the 2.1 migration note, and the linked-file contract describe this default. They do not say the library stops at 64 MiB.
