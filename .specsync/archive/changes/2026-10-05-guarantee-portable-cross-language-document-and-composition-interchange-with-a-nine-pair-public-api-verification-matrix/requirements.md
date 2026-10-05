---
change: guarantee-portable-cross-language-document-and-composition-interchange-with-a-nine-pair-public-api-verification-matrix
artifact: requirements
---

# Requirements

REQ-ThreeMD-033 requires every supported language to consume every producer's readable/canonical documents and self-contained composition profiles, plus the portable uncompressed envelope. Content, finite coordinates, Unicode spelling, opaque strings, identities and references survive within the existing representable-value contract. Signed zero follows the existing canonical normalization to zero rather than a new bit-preservation promise.

REQ-ThreeMD-034 requires a permanent public-API producer/consumer matrix with mandatory manifest execution, deterministic generated cases, canonical byte checks, semantic/numeric checks, imported editing/revision checks and hostile input cases. The verification lane builds and typechecks the JavaScript package and executes it in Node. Optional compression and language-specific rendering/JSON transport capabilities are documented explicitly.
