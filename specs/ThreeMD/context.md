---
spec: ThreeMD.spec.md
---

## Context

ThreeMD is the Swift implementation of the 3md file format. 3md is Markdown
extended along one free third axis (the Z axis): an ordinary Markdown document
flows left to right and top to bottom, and 3md adds depth by stacking
**planes**, where each plane is itself ordinary Markdown. The author declares
what that Z axis means (time, depth, layer, frame, space, or any custom label);
the format records the intent but does not constrain it.

This module's job is narrow and well bounded: turn 3md source text into a typed
`Document`, and turn a `Document` back into 3md source text. It is a
parser/serializer and nothing more. It does not render planes, does not parse or
interpret the Markdown inside a plane body, and does not lay planes out for a
viewer. Plane bodies are carried as opaque strings.

The module is a single `ThreeMD` library target with no dependencies beyond
Foundation, built under Swift 6 with strict concurrency enabled (see
`Package.swift`). Every public type is a value type and `Sendable`, so a parsed
document can cross concurrency boundaries freely without locks or copies of
shared mutable state.

### Module purpose and boundaries

- In scope: lexing and parsing 3md source, a strongly typed document model,
  lossless serialization back to source, and typed parse errors.
- Out of scope (non-goals): rendering, Markdown processing of plane bodies,
  layout, validation of body content, file I/O. The module operates on
  `String` in and `String` out.

### File and type layout

Source lives in `Sources/ThreeMD/`. Each type has one focused responsibility:

- `Axis.swift` - `Axis`, a `RawRepresentable` struct wrapping the Z axis label.
  Its initializer trims whitespace and lowercases the value. It exposes named
  constants (`time`, `depth`, `layer`, `frame`, `space`) but accepts any string.
- `Plane.swift` - `Plane`, one slice of the document. Holds the required `z`
  position, optional `label`, optional in-plane `x`/`y` offsets, a string
  dictionary of any extra directive attributes, and the trimmed Markdown `body`.
- `Document.swift` - `Document`, the top-level model: format `version`, `axis`,
  optional `title`, a `metadata` dictionary for extra frontmatter keys, an
  optional `preamble`, and the `planes` array in source order. Convenience
  accessors `planesByZ` (sorted ascending) and `plane(atZ:)` are read-only views;
  they do not change stored order.
- `ParseError.swift` - `ParseError`, the typed error enum thrown by the parser,
  conforming to `LocalizedError` and `Equatable` with one case per documented
  failure mode.
- `Parser.swift` - `Parser`, the parsing pipeline (detailed below).
- `Serializer.swift` - `Serializer`, the inverse of the parser.

### Related modules

- `SPEC.md` is the prose format specification this code implements. The error
  cases, the frontmatter rules, the plane attribute rules, the single-plane
  shorthand, and the round-trip guarantee all trace directly to that document.
- There are no other modules; `ThreeMD` is self-contained.

## Design Decisions

- **Value types and `Sendable` everywhere.** `Document`, `Plane`, `Axis`,
  `Parser`, and `Serializer` are all `struct`s and `Sendable`. This is the
  primary concurrency-safety decision: there is no shared mutable state to guard,
  parsed documents are freely shareable across tasks and actors, and the strict
  concurrency build setting in `Package.swift` is satisfied without
  `@unchecked` escapes.

- **`Axis` as a `RawRepresentable` struct, not an enum.** The axis is
  deliberately free-form. The format treats the axis label as metadata that
  tools interpret, so a closed enum would be wrong. A struct over `String` gives
  type safety and named constants for the common cases while still accepting any
  custom label. The initializer normalizes (trim plus lowercase) so axis values
  compare consistently.

- **Frontmatter is required, and the `3md` key is the magic marker.** A valid
  document must open with a `---` fenced frontmatter block, and that block must
  carry a non-empty `3md` version key. The presence of the `3md` key is what
  identifies the file as 3md at all; without it, parsing fails with
  `missingVersion`. The `axis` key defaults to `layer` when absent. Any key that
  is not `3md`, `axis`, or `title` is preserved as string metadata rather than
  discarded.

- **The single-plane shorthand.** A document with valid frontmatter but no
  `@plane` directives is treated as one implicit plane at `z = 0`, whose body is
  the entire post-frontmatter content. This means a plain Markdown file with a
  3md header is a valid one-plane document. The parser produces this from the
  collapsed preamble; if there is no content at all, it produces an empty plane
  list rather than an empty plane.

- **Throwing parser with a typed `ParseError`.** Parsing fails loudly through
  Swift error handling, never through optionals or sentinel values. `ParseError`
  has a distinct case per documented failure (`missingFrontmatter`,
  `invalidFrontmatter`, `missingVersion`, `missingPlanePosition`,
  `invalidPlaneDirective`, `duplicatePlane`), several of which carry the offending
  line number, so callers can react programmatically and report precisely.

- **Lossless round-trip via the `Serializer`.** `Serializer.render` is the
  documented inverse of `Parser.parse`: parsing serialized output yields an
  equivalent document (for content that does not depend on quote escaping). The
  serializer emits `3md` and `axis` first, sorts extra metadata and plane
  attributes by key for stable output, formats whole-number doubles as integers,
  and quotes values only when needed (or always, for `label` and extra
  attributes, to keep spaces safe).

## Parsing pipeline

`Parser.parse(_:)` runs a small fixed pipeline:

1. **Normalize.** Convert `\r\n` to `\n` and split the source into lines. All
   later work is line-oriented.

2. **Extract frontmatter.** Skip leading blank lines, require an opening line
   that is exactly `---`, then read `key: value` pairs until a closing `---`.
   Inside the block, blank lines and `#` comment lines are ignored, the first
   `:` separates key from value, and matching surrounding single or double quotes
   are stripped. A block that never closes throws `invalidFrontmatter`; a missing
   opening fence throws `missingFrontmatter`. The extractor also records the
   1-based line number where the body begins, so plane errors can report
   accurate source lines.

3. **Interpret frontmatter.** Fold the raw fields into `version`, `axis`,
   `title`, and `metadata`, defaulting the axis to `layer` and rejecting a
   missing or empty `3md` version with `missingVersion`.

4. **Parse the body into preamble plus planes.** Walk the remaining lines. Lines
   whose first whitespace-delimited token is `@plane` open a new plane;
   everything else accumulates into the current plane's body, or into the
   preamble if no plane has started yet. Each `@plane` directive is parsed into
   attributes, and the previous pending plane is finalized. Bodies are collapsed
   (leading and trailing blank lines trimmed). A `z` is required
   (`missingPlanePosition`), `z`/`x`/`y` must parse as `Double`
   (`invalidPlaneDirective`), and a repeated `z` throws `duplicatePlane`. The
   reserved keys `z`, `x`, `y`, and `label` are pulled out; anything else lands
   in the plane's `attributes`. If no directives were seen, the single-plane
   shorthand applies.

5. **Tokenize directive attributes.** Directive attributes are split by a small
   tokenizer that keeps quoted spans intact, so a value like `label="Mon Day"`
   stays one token despite the space. Each token splits on the first `=` into a
   lowercased key and an unquoted value; an empty key or a token with no `=`
   throws `invalidPlaneDirective`.
