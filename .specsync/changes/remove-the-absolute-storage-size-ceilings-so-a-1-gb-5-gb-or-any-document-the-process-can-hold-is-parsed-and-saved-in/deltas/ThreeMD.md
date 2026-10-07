# Remove the absolute storage size ceiling

## ADDED

### REQUIREMENT REQ-ThreeMD-043

The Swift, TypeScript, and Rust libraries SHALL parse and save a document of any size the process can hold, including a document larger than 64 MiB, as text and as payload kind 2. `DocumentDecodeLimits` SHALL keep its five fields and SHALL default each of them to the largest positive integer the host can use. A caller SHALL be able to set a lower positive limit. A non-positive limit SHALL be `invalidLimits`. A length or count integer SHALL use a minimal unsigned LEB128 of 1 to 10 bytes. A coordinate integer SHALL stay a 1 to 4 byte Var. Small kind-2 files SHALL stay byte-identical. Composition profile ceilings and edit budgets SHALL stay as already specified. (Change requirements UC-01 to UC-06.)

Acceptance Criteria:
- Default limits encode and decode a body of 64 MiB + 1 letters as text and as kind 2, and a document of 100,001 non-blank lines, in Swift, TypeScript, and Rust. A body of only newlines is still collapsed by the text format.
- A limit value of 5 GiB is accepted. Zero is rejected. TypeScript rejects a value above `Number.MAX_SAFE_INTEGER`.
- `80 80 80 80 01` is the length 2^28. `80 80 80 80 14` is the length 5,368,709,120. `ff ff ff ff 01` is a legal length of 2^29 − 1 and an invalid coordinate.
- The kind-2 D10 bound saturates at the host maximum.
- A local 1 GB round trip is recorded for this machine. CI does not allocate 1 GB or 5 GB.
- SPEC.md, the module spec, and the README describe this default and do not say the library stops at 64 MiB.
