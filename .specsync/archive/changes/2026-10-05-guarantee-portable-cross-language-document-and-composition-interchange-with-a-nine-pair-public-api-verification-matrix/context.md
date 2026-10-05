---
change: guarantee-portable-cross-language-document-and-composition-interchange-with-a-nine-pair-public-api-verification-matrix
artifact: context
---

# Context

Leif directly requested that all supported languages import and export each other's files. Swift, TypeScript and Rust already implement the portable extensions, but language-local fixtures do not execute the nine producer/consumer pairings. Audits identified Unicode trimming, source key collisions and link extraction differences. This scope adds executable interchange evidence and repairs confirmed compatibility defects while retaining APIs and the frozen grammar.

Work starts at PR62 head f44ba6704050752155c6324fc43854db35daac24 in an isolated checkout. Historical archives and element/dist remain untouched. Sculpt dependency adoption and release publication are separate. Portable text and uncompressed binary are mandatory. Apple LZFSE is an explicit optional capability while the separate user compression question is pending.
