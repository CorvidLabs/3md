---
change: guarantee-portable-cross-language-document-and-composition-interchange-with-a-nine-pair-public-api-verification-matrix
artifact: testing
---

# Testing

Execute every declared case through Swift, TypeScript and Rust producers and all nine pairings for canonical text, uncompressed binary and composition text/binary. Also test legacy text when its representable semantics apply. Fixed byte goldens anchor the independent expectation; deterministic finite-number and Unicode/quoting corpora exercise thresholds and scalar ordering. Reimport adopted and edited outputs and compare graph preservation, stable identities and canonical revisions. Mutate header/version/flags/CRC/length/UTF-8 and strict composition JSON; require all adapters to reject each expected invalid input without partial output. Fail on unknown or missing manifest cases.

Run Swift format/build/tests, Bun tests/typecheck/declaration build, Node built-package interchange, Rust format/clippy/tests, bundle drift and editor gates. Run the pinned full Trust 1.2.2 lane and forced strict SpecSync. Review source at the exact implementation commit. Record actual unsigned Attest limitations without weakening policy. Do not claim exhaustive all-input proof, on-device runtime coverage or portable LZFSE from these tests.
