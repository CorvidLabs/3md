---
hi: 1
families: [DOCS]
---

# Docs

## Intent

<!-- What is this for, and what should it feel like? Write it as a person. -->

## Criteria

- **DOCS-1**  I can open the README and see ThreeMD 2.2.0 as the library in this repository: the text file I edit, and binary as the same frames stored as fields. Kind 1 is named as deprecated. The page says the 2.2.0 tag is not pushed yet.
- **DOCS-2**  I can see that Sculpt.3md is the Mac app nested at apps/sculpt, that its package name stays Rook, and that it builds against the ThreeMD library in this checkout. The root package stays the cross-platform format library.
- **DOCS-3**  Install instructions match the registries: npm @corvidlabs/threemd 2.1.0 and crates.io threemd 2.1.0 are published. The docs do not say those registries are still on 2.0.0. They say this repository's manifests read 2.2.0.
- **DOCS-4**  Contributor docs name the nested app and still require a format change to land in the Swift, TypeScript, and Rust parsers. The app is not a fourth parser. Historical release notes and adoption receipts stay historical.
