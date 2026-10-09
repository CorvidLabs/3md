---
hi: 1
families: [DOCS]
---

# Docs

## Intent

I want the public docs to tell me what ThreeMD 2.2.1 is, which registries actually serve it, and which programs are the format libraries.

## Criteria

- **DOCS-1**  I can open the README and see ThreeMD 2.2.1 as the current library: the text file I edit, and binary as the same frames stored as fields. Kind 1 is named as deprecated. The page says tag v2.2.1 and the GitHub release are published.
- **DOCS-2**  I can see that Sculpt.3md is the Mac app nested at apps/sculpt, that its package name stays Rook, and that it builds against the ThreeMD library in this checkout. The root package stays the cross-platform format library.
- **DOCS-3**  Install instructions match the registries: npm @corvidlabs/threemd 2.2.1 and @corvidlabs/three-md-element 2.2.1 are published. crates.io threemd 2.1.0 is still the published crate. The Homebrew formula threemd is 2.2.1. The docs do not say crates.io serves 2.2.1.
- **DOCS-4**  Contributor docs name four libraries, Swift, TypeScript, Rust, and GDScript, and they name the nested app. A format change lands in all four libraries. The app is not a fifth parser. Historical release notes and adoption receipts stay historical.
