# ThreeMD

## ADDED

### REQUIREMENT REQ-ThreeMD-033

Swift, TypeScript and Rust SHALL import and export one another's representable readable documents, canonical text, portable uncompressed binary and self-contained composition profiles without losing supported content or references.

Acceptance Criteria
- Every producer's canonical document and composition output is imported by all three languages and re-exported to identical canonical bytes.
- Finite coordinates, Unicode spelling, quoting, source order, metadata, identities, revisions and graph references survive. Signed zero follows the existing canonical normalization to zero.
- Confirmed grammar interpretation differences are repaired without changing public parser signatures or the frozen grammar; all existing valid and invalid vectors remain mandatory.
- Optional Apple LZFSE is explicitly distinguished from portable text/uncompressed binary.

### REQUIREMENT REQ-ThreeMD-034

The repository SHALL execute a bounded mandatory public-API interchange matrix in its verification lane, including built JavaScript package execution in Node and no silently skipped manifest cases.

Acceptance Criteria
- A Swift development coordinator drives Swift, TypeScript and Rust adapters for all nine producer/consumer pairs with fixed byte goldens, generated numeric/Unicode cases, imported identity edits and hostile inputs.
- Canonical/profile/binary bytes and semantic numeric fields are checked with exact byte/bit comparisons under the existing zero normalization.
- JavaScript typechecking, declaration builds and package runtime execution are required, alongside all existing language, bundle and editor gates.
- Test transport is development-only, performs no library I/O, and does not establish a public snapshot/patch JSON format or an exhaustive all-input parity claim.
