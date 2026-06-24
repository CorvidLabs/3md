---
spec: ThreeMD.spec.md
---

# ThreeMD Requirements

These requirements describe the ThreeMD Swift module: a parser and serializer
for the 3md file format. They are traceable against `SPEC.md` (the format
definition) and the implementation in `Sources/ThreeMD/`. Each requirement is
numbered so tests and reviews can reference it directly.

## User Stories

- As a developer, I want to parse `.3md` source text into a typed `Document` of
  `Plane` values so I can read a stacked Markdown file programmatically.
- As a developer, I want to render a `Document` back to 3md text that re-parses
  to an equal document so I can edit and persist files without drift.
- As a developer, I want clear, typed errors when source is malformed so I can
  report exactly what went wrong and where.
- As a tool author, I want to know what the Z axis means and how planes are
  ordered so I can lay a document out correctly.

## Acceptance Criteria

### Functional Requirements

- **FR-1 (Frontmatter required).** `Parser.parse` requires a frontmatter block:
  a line containing exactly `---`, zero or more content lines, and a closing
  line containing exactly `---`. Leading blank lines before the opening fence
  are skipped. A source with no opening `---` throws
  `ParseError.missingFrontmatter`. A frontmatter block that is never closed
  throws `ParseError.invalidFrontmatter`.

- **FR-2 (Version marker required).** Frontmatter MUST declare a `3md` key whose
  value is non-empty. Its presence is the format's magic marker. The value is
  stored as `Document.version`. A missing or empty `3md` value throws
  `ParseError.missingVersion`.

- **FR-3 (Frontmatter fields).** Inside the fences, content lines are
  `key: value` pairs split on the first `:`. Blank lines and lines beginning
  with `#` are ignored. A non-blank, non-comment line with no `:` throws
  `ParseError.invalidFrontmatter`. Keys are matched case-insensitively. Values
  are trimmed, and a matching pair of surrounding single or double quotes is
  stripped.

- **FR-4 (Axis handling and default).** The optional `axis` key sets
  `Document.axis`. The `Axis` value trims and lowercases its raw string, so
  `axis` is normalized. When no `axis` key is present, the axis defaults to
  `Axis.layer`. Any axis string is permitted; `time`, `depth`, `layer`,
  `frame`, and `space` are provided as named constants.

- **FR-5 (Reserved frontmatter keys and metadata).** The keys `3md`, `axis`, and
  `title` are reserved. `title` populates the optional `Document.title`. Every
  other frontmatter key is preserved verbatim in `Document.metadata` as a
  `[String: String]` pair.

- **FR-6 (Plane directives).** A plane begins with a line whose first
  whitespace-delimited token is `@plane`, followed by space-separated
  `key=value` attributes. A token with no `=`, or with an empty key, throws
  `ParseError.invalidPlaneDirective`. Attribute keys are lowercased. Attribute
  values may be quoted with single or double quotes; the tokenizer keeps quoted
  spans intact so a value may contain spaces, and surrounding quotes are
  stripped.

- **FR-7 (Required z attribute).** Each `@plane` directive MUST carry a `z`
  attribute. A directive with no `z` throws
  `ParseError.missingPlanePosition(line:)`. A `z` value that does not parse as a
  `Double` throws `ParseError.invalidPlaneDirective(line:detail:)`. Numbers may
  be integer or decimal and may be negative.

- **FR-8 (Optional x, y, label, and extra attributes).** The `x` and `y`
  attributes are optional in-plane offsets; when present each MUST parse as a
  `Double` or `ParseError.invalidPlaneDirective` is thrown. `label` is an
  optional human-readable string. The reserved plane attributes are `z`, `x`,
  `y`, and `label`; every other attribute is preserved in `Plane.attributes` as
  a `[String: String]` pair.

- **FR-9 (Plane body and preamble handling).** Every line after a directive, up
  to the next `@plane` directive or end of file, is that plane's Markdown body.
  Leading and trailing blank lines of a body are trimmed; an all-whitespace
  body collapses to an empty string. Markdown that appears after the
  frontmatter but before the first `@plane` directive is the document preamble,
  stored in the optional `Document.preamble` with the same blank-line trimming.

- **FR-10 (Single-plane shorthand).** A document with frontmatter but no
  `@plane` directives whose remaining content is non-empty parses as exactly one
  implicit plane at `z = 0`, with that content as the plane body and a `nil`
  preamble. This makes a plain Markdown file with a 3md frontmatter header a
  valid one-plane document.

- **FR-11 (Duplicate z rejection).** No two planes in a document may share the
  same `z` value. A repeated `z` throws `ParseError.duplicatePlane(z:)`.

- **FR-12 (Source order preserved).** `Document.planes` holds planes in source
  order. `Document.planesByZ` returns them sorted by ascending `z`, and
  `Document.plane(atZ:)` returns the first plane whose `z` equals the argument,
  or `nil`.

- **FR-13 (Serialization).** `Serializer.render` produces 3md text. It always
  emits a frontmatter block with `3md` and `axis` lines, then `title` when set,
  then metadata keys sorted alphabetically. For each plane it emits an `@plane`
  directive (`z`, then `label`, `x`, `y` when set, then extra attributes sorted
  alphabetically) followed by the non-empty body. Whole-number doubles render as
  integers; `label` and extra attribute values are always quoted, and embedded
  double quotes are escaped.

- **FR-14 (Round-trip).** Serializing a `Document` and parsing the result yields
  an equal document, for content that does not rely on quote escaping.

- **FR-15 (Line-ending normalization).** Parsing normalizes `\r\n` to `\n`
  before processing, so Windows and Unix line endings parse identically.

### Non-Functional Requirements

- **NFR-1 (Swift 6, cross-platform).** The module builds under Swift 6 strict
  concurrency and targets all supported Apple platforms, Linux, and Windows. It
  relies only on portable Foundation string handling.

- **NFR-2 (Sendable value types).** `Axis`, `Plane`, `Document`, `ParseError`,
  `Parser`, and `Serializer` are `Sendable`. `Axis`, `Plane`, and `Document`
  are immutable value types that are also `Hashable` and `Codable`;
  `ParseError` is `Equatable`.

- **NFR-3 (No force-unwrap).** Library code uses no force unwraps, `try!`, or
  `as!`. Optionals and failable conversions are handled with `guard` and typed
  throws.

- **NFR-4 (Zero third-party dependencies).** The module depends only on
  Foundation. No third-party packages are used.

- **NFR-5 (Deterministic parsing and serialization).** Parsing is pure: the same
  input always yields the same `Document`. Serialization is deterministic,
  ordering metadata and extra attributes alphabetically so output is stable.

## Constraints

- The format definition in `SPEC.md` is authoritative; this module implements
  version 0.1 (draft) of that format.
- Frontmatter is parsed line-by-line as simple `key: value` pairs, not as full
  YAML. Nested structures, lists, and multi-line values are not supported.
- Quote handling is limited to a single matching pair of surrounding single or
  double quotes. Round-trip equivalence is only guaranteed for content that does
  not rely on quote escaping.
- `z`, `x`, and `y` are parsed as `Double`, so they carry double-precision
  range and rounding.

## Out of Scope

- Markdown parsing or rendering of plane bodies; bodies are carried as opaque
  text.
- Format extensions listed as open questions in `SPEC.md`, including inline 3D
  model embeds, cross-plane links and transclusion, per-plane transition or
  timing hints, and any binary or compressed container.
- Validation of axis semantics; the axis label is treated as free metadata.
- Networking, file I/O, and any rendering or viewer behavior.
