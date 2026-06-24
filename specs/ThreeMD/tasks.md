---
spec: ThreeMD.spec.md
---

## Tasks

ThreeMD is a cross-platform Swift parser and serializer for the 3md format
(Markdown extended along one free Z axis). The 0.1 draft in SPEC.md is fully
implemented and covered by a 32-test suite. The sections below track what is
done and what is still open.

### Done

Core types and the full parse/serialize/round-trip path are implemented in
`Sources/ThreeMD/` and verified by `Tests/ThreeMDTests/ParserTests.swift`.

- [x] `Axis` type with known axes (time, depth, layer, frame, space) and
      raw-value normalization (trimmed and lowercased)
- [x] `Plane` value type: `z`, optional `label`, `x`, `y`, extra `attributes`,
      and trimmed Markdown `body`
- [x] `Document` value type: `version`, `axis`, `title`, `metadata`,
      `preamble`, `planes`
- [x] `Document.planesByZ` (sorted by ascending z) and `Document.plane(atZ:)`
      lookup
- [x] `ParseError` enum with all six spec error cases and `LocalizedError`
      descriptions (missingFrontmatter, invalidFrontmatter, missingVersion,
      invalidPlaneDirective, missingPlanePosition, duplicatePlane)
- [x] `Parser.parse(_:)`: frontmatter extraction, `key: value` interpretation,
      and body/plane parsing
- [x] Frontmatter rules: required `---` fences, required `3md` version key,
      `axis` defaults to `layer`, comment (`#`) and blank lines ignored,
      quoted values stripped, leading blank lines before the opening fence
      allowed
- [x] `@plane` directive parsing with quote-aware tokenizer: required numeric
      `z`, optional numeric `x`/`y`, optional `label`, extra attributes
      preserved; reserved keys kept out of `extras`
- [x] Numeric handling: negative and decimal `z`/`x`/`y` values
- [x] Single-plane shorthand: frontmatter with no `@plane` directives yields one
      implicit plane at `z = 0`; empty body yields zero planes
- [x] Preamble capture: Markdown before the first `@plane` is preserved
- [x] Body trimming: leading and trailing blank lines dropped from each plane
- [x] Windows line endings (`\r\n`) normalized before parsing
- [x] Duplicate-`z` detection across planes
- [x] `Serializer.render(_:)`: frontmatter, preamble, and directive emission;
      whole numbers formatted as integers; values quoted when needed
- [x] Round-trip guarantee: parse, render, and re-parse yields an equal document
      (covered for plain docs, metadata plus attributes, and preambles)
- [x] `Sendable`, `Hashable`, and `Codable` conformances on `Axis`, `Plane`,
      and `Document`
- [x] 32-test XCTest suite covering frontmatter, planes, errors, lookups, axis,
      ParseError descriptions, and round-trips

### Next

Near-term work that builds directly on the 0.1 surface.

- [ ] Conformance test vectors: a shared set of `.3md` input/expected fixtures
      so other implementations can validate against the same cases
- [ ] DocC documentation: a documentation catalog with the format overview,
      symbol docs, and usage articles

### Later

Open questions from SPEC.md section 8, targeted at versions after 0.1. These
require format-level decisions before implementation.

- [ ] Inline 3D model embeds, for example `@model src="scene.glb"`
- [ ] Cross-plane links and transclusion between planes
- [ ] Per-plane transition or timing hints for `frame` and `time` axes
- [ ] A binary or compressed container for large scenes
