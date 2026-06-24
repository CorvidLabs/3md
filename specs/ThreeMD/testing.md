---
spec: ThreeMD.spec.md
---

## Test Plan

The ThreeMD module is covered by a single XCTest suite, `ParserTests`, in
`Tests/ThreeMDTests/ParserTests.swift`. It exercises the parser end to end
against the behavior described in `SPEC.md`, plus the serializer and the small
value types (`Axis`, `ParseError`). At the time of writing the suite holds 32
test methods.

### How to run

The suite runs through the standard Swift toolchain:

```
swift test
```

The canonical CI gate is the `verify` lane defined in `fledge.toml`. It runs the
format check, the build, and the tests in order:

```
fledge lanes run verify
```

The `verify` lane is `lint` then `build` then `test`, where `lint` is
`swift-format lint --strict`, `build` is `swift build`, and `test` is
`swift test`. The `ci` lane is an alias for the same three steps. Run
`fledge introspect` or check `fledge.toml` if the task list changes.

### Approach

The suite follows a few consistent patterns:

- **Inline-source fixtures.** Every test builds its `.3md` input as a Swift
  multi-line string literal inside the test method and feeds it to a shared
  `Parser()` instance. There are no on-disk fixture files; the input and the
  expected result sit side by side so each test reads as a self-contained
  example.
- **Error assertions per `ParseError` case.** Failure paths are checked with
  `XCTAssertThrowsError`. Where the error case is simple the test compares it
  directly with `XCTAssertEqual(error as? ParseError, .someCase)`; where the
  case carries positional payload (`line:`) it uses a `guard case` pattern match
  and `XCTFail` on mismatch, so the assertion does not depend on the exact line
  number.
- **Round-trip equality.** Several tests parse a document, render it with
  `Serializer()`, parse the rendered text again, and assert the reparsed
  `Document` equals the original (or that specific fields survive). This relies
  on `Document` and `Plane` being `Equatable` via their `Hashable` conformance.

### Coverage inventory

Grouped by area, with the asserting behavior of each test.

#### Frontmatter

- `testParsesFrontmatter` - parses `3md`, `axis`, `title`, and an extra key, and
  checks the extra key lands in `metadata`.
- `testMissingFrontmatterThrows` - plain Markdown with no `---` block throws
  `.missingFrontmatter`.
- `testMissingVersionThrows` - frontmatter without a `3md` key throws
  `.missingVersion`.
- `testUnclosedFrontmatterThrows` - a `---` block that is never closed throws
  `.invalidFrontmatter`.
- `testAxisDefaultsToLayer` - omitting `axis` yields `Axis.layer`.
- `testFrontmatterIgnoresCommentLines` - lines beginning with `#` inside the
  frontmatter are skipped.
- `testFrontmatterStripsQuotedValues` - a double-quoted `title` value has its
  quotes stripped.
- `testLeadingBlankLinesBeforeFrontmatter` - blank lines before the opening
  `---` are tolerated.

#### Planes, coordinates, and attributes

- `testParsesMultiplePlanes` - two `@plane` directives produce two planes with
  correct `z`, `label`, and trimmed bodies.
- `testParsesPlaneCoordinatesAndAttributes` - parses decimal `z`, integer `x`,
  negative `y`, and two extra attributes (`color`, quoted `note`).
- `testNegativeZValue` - `z=-1` parses as `-1`.
- `testDecimalZValue` - `z=0.5` parses as `0.5`.
- `testPlaneBodyTrimsLeadingAndTrailingBlanks` - surrounding blank lines are
  trimmed from a plane body.
- `testReservedAttributeKeysNotInExtras` - `z`, `x`, `y`, and `label` are not
  duplicated into the `attributes` dictionary; a non-reserved key is.

#### Single-plane shorthand

- `testPlainMarkdownBecomesSinglePlane` - frontmatter with no `@plane`
  directives yields exactly one plane at `z=0` whose body is the whole content,
  and a nil preamble.
- `testEmptyDocumentProducesNoPlanes` - frontmatter with no body yields no
  planes and a nil preamble.

#### Preamble

- `testPreambleBeforeFirstPlane` - Markdown before the first `@plane` is captured
  as `document.preamble`, separate from the first plane's body.

#### Error cases

Each maps to one `ParseError` case from `SPEC.md` section 6:

- `testMissingPlanePositionThrows` - `@plane` with no `z` throws
  `.missingPlanePosition`.
- `testNonNumericPositionThrows` - `z=soon` throws `.invalidPlaneDirective`.
- `testNonNumericXThrows` - `x=left` throws `.invalidPlaneDirective`.
- `testNonNumericYThrows` - `y=top` throws `.invalidPlaneDirective`.
- `testDuplicatePositionThrows` - two planes at the same `z` throw
  `.duplicatePlane(z:)`, checked with the exact value.
- `testInvalidDirectiveTokenThrows` - a bare token with no `=` on a directive
  throws `.invalidPlaneDirective`.
- `testParseErrorDescriptions` - every `ParseError` case returns a non-nil
  `errorDescription`.

#### Lookups and sorting

- `testPlanesByZAreSorted` - `document.planesByZ` returns planes ordered by
  ascending `z` regardless of source order, and `plane(atZ:)` finds the right
  body.
- `testPlaneAtZReturnsNilForMissingPosition` - `plane(atZ:)` returns nil for a
  `z` that is not present.

#### CRLF normalization

- `testWindowsLineEndingsNormalized` - a source using `\r\n` line endings parses
  correctly, with the plane body recovered as `"body"`.

#### Axis normalization

- `testAxisRawValueNormalized` - `Axis(rawValue:)` trims whitespace and
  lowercases, so `"  TIME  "` becomes `"time"`.
- `testKnownAxesMatchSpec` - the five named axes (`time`, `depth`, `layer`,
  `frame`, `space`) carry the raw values from the spec.

#### Round-trip

- `testRoundTripThroughSerializer` - parse, render, reparse, and assert the
  reparsed `Document` equals the original (multi-plane with title and labels).
- `testRoundTripWithMetadataAndAttributes` - extra frontmatter metadata (`fps`)
  and a plane `label` survive a round trip; the body contains a fenced code
  block.
- `testRoundTripWithPreamble` - a document preamble survives a round trip.

### Gaps and future test ideas

The suite is behavior-focused and intentionally narrow. Known gaps:

- **Property-based / fuzz parsing.** There is no randomized or generative
  testing. A fuzzer that throws arbitrary byte sequences and arbitrary but
  well-formed directives at `Parser.parse` would harden the lexer (`tokenize`,
  `unquote`) and surface crashes or unexpected throws the inline fixtures miss.
- **Performance on large documents.** There are no measurements. Documents with
  many thousands of planes or very large bodies are untested; an XCTest
  `measure` block or a benchmark would catch quadratic regressions in body
  accumulation or sorting.
- **Shared conformance vectors.** Tests assert against this implementation's
  behavior, not against a portable suite of `.3md` input/expected-output
  fixtures that other implementations could also run. Extracting such a vector
  set would let the spec be validated independently of the Swift parser.
- **Quote-escaping round trips.** `SPEC.md` section 7 scopes round-trip
  guarantees to content that does not rely on quote escaping, and the serializer
  does escape embedded double quotes, but no test round-trips a value containing
  an embedded quote. That edge is currently unverified.
- **Single-quoted directive values and mixed quoting.** The tokenizer accepts
  single quotes, but the tests only exercise double-quoted attribute values.
- **Codable round trips.** `Document`, `Plane`, and `Axis` are `Codable`, but no
  test encodes and decodes them.
