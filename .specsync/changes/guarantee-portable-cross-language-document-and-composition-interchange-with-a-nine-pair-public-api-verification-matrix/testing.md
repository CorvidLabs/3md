---
change: guarantee-portable-cross-language-document-and-composition-interchange-with-a-nine-pair-public-api-verification-matrix
artifact: testing
---

# Testing

Execute every declared case through Swift, TypeScript and Rust producers and all nine pairings for canonical text, uncompressed binary and composition text/binary. Also test legacy text when its representable semantics apply. Fixed byte goldens anchor the independent expectation; deterministic finite-number and Unicode/quoting corpora exercise thresholds and scalar ordering. Reimport adopted and edited outputs and compare graph preservation, stable identities and canonical revisions. Mutate header/version/flags/CRC/length/UTF-8 and strict composition JSON; require all adapters to reject each expected invalid input without partial output. Fail on unknown or missing manifest cases.

Run Swift format/build/tests, Bun tests/typecheck/declaration build, Node built-package interchange, Rust format/clippy/tests, bundle drift and editor gates. Run the pinned full Trust 1.2.2 lane and forced strict SpecSync. Review source at the exact implementation commit. Record actual unsigned Attest limitations without weakening policy. Do not claim exhaustive all-input proof, on-device runtime coverage or portable LZFSE from these tests.

## Requirement evidence

| Requirement | Evidence | Result |
| --- | --- | --- |
| REQ-ThreeMD-033 | All three public adapters and nine-pair matrix; 82 shared source cases, 43 automatically discovered legacy JSON sources, 45 fixed numbers, 256 seeded numbers; exact byte/bit and adopted/edit checks | Pass: 426 cases, 16,983 imports, all nine pairs at source 6b6be79eeda12b7ff20b5a06b2c2470a94de0eee, optional LZFSE excluded explicitly |
| REQ-ThreeMD-034 | Mandatory catalog/count/format checks; Swift protocol and watchdog regressions; required JS typecheck/build/Node execution; complete pinned Trust and strict SpecSync; complementary scoped peer reviews | Pass: complete Trust at 55efdaab7efd2a12e78f3602af35c7e7b08322c0 and final matrix/harness at 6b6be79; official materialization recheck follows, with unsigned provenance limitation preserved |

## Verified source and commands

Root executed the complete pinned Trust 1.2.2 lane on source
55efdaab7efd2a12e78f3602af35c7e7b08322c0. It passed eight steps in 35.388
seconds: 244 Swift tests, 141 TypeScript tests, 31 Rust tests plus three
doctests, formatting/strict Clippy, JS package typechecking/declaration builds,
the 426-case Node/Swift/Rust interchange matrix, bundle drift and editor grammar.
Trust reported Augur proceed at risk 35 and the existing unsigned progressive
provenance degradation. It did not verify a permitted signature.

The final catalog guard source 6b6be79eeda12b7ff20b5a06b2c2470a94de0eee
also passed `swift run threemd-interchange`: 1,887 imports per pair, 16,983
total, with permanent exact-key, malformed/oversized stream and Unix watchdog
regressions. Original fixture source bytes and element/dist remain unchanged.
Three actual agent technical reviews passed with stated authorship and
complementary peer coverage, not independent human approval.

Raw receipts are retained at /private/tmp/3md-interchange-trust-final.log and
/private/tmp/3md-interchange-matrix-final.log. The official check records the
materialized contract and exact implementation commit separately.
