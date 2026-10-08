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
- As a developer, I want bounded general-document binary storage without
  changing the existing text grammar or application-specific readers.
- As a developer, I want a self-contained library of reusable named documents
  with explicit references, safe graph validation and no automatic external I/O.
- As a developer, I want binary documents that load several times faster than
  bounded text decoding, without building or parsing text, and that decode to
  exactly the document their canonical text gives in every language.
- As a developer whose consumers still run ThreeMD 2.0, I want an explicit
  writer for the 2.0 binary bytes and a header inspection that tells me which
  payload kind a file holds.

## Acceptance Criteria

### Functional Requirements

### REQ-threemd-001

`Parser.parse` SHALL require a complete frontmatter block and report missing or unclosed fences with typed parse errors.

Acceptance Criteria

- `Parser.parse` requires a frontmatter block:
  a line containing exactly `---`, zero or more content lines, and a closing
  line containing exactly `---`. Leading blank lines before the opening fence
  are skipped. A source with no opening `---` throws
  `ParseError.missingFrontmatter`. A frontmatter block that is never closed
  throws `ParseError.invalidFrontmatter`.

### REQ-threemd-002

Frontmatter SHALL declare a non-empty `3md` value that is stored as `Document.version`.

Acceptance Criteria

- Frontmatter MUST declare a `3md` key whose
  value is non-empty. Its presence is the format's magic marker. The value is
  stored as `Document.version`. A missing or empty `3md` value throws
  `ParseError.missingVersion`.

### REQ-threemd-003

The parser SHALL read frontmatter as case-insensitive `key: value` pairs while rejecting malformed content lines.

Acceptance Criteria

- Inside the fences, content lines are
  `key: value` pairs split on the first `:`. Blank lines and lines beginning
  with `#` are ignored. A non-blank, non-comment line with no `:` throws
  `ParseError.invalidFrontmatter`. Keys are matched case-insensitively. Values
  are trimmed, and a matching pair of surrounding single or double quotes is
  stripped.

### REQ-threemd-004

The parser SHALL normalize the optional `axis` value and default it to `Axis.layer` when absent.

Acceptance Criteria

- The optional `axis` key sets
  `Document.axis`. The `Axis` value trims and lowercases its raw string, so
  `axis` is normalized. When no `axis` key is present, the axis defaults to
  `Axis.layer`. Any axis string is permitted; `time`, `depth`, `layer`,
  `frame`, and `space` are provided as named constants.

### REQ-threemd-005

The parser SHALL map reserved frontmatter keys to document fields and preserve every other key in `Document.metadata`.

Acceptance Criteria

- The keys `3md`, `axis`, and
  `title` are reserved. `title` populates the optional `Document.title`. Every
  other frontmatter key is preserved verbatim in `Document.metadata` as a
  `[String: String]` pair.

### REQ-threemd-006

The parser SHALL recognize `@plane` directives and parse their quoted or unquoted `key=value` attributes.

Acceptance Criteria

- A plane begins with a line whose first
  whitespace-delimited token is `@plane`, followed by space-separated
  `key=value` attributes. A token with no `=`, or with an empty key, throws
  `ParseError.invalidPlaneDirective`. Attribute keys are lowercased. Attribute
  values may be quoted with single or double quotes; the tokenizer keeps quoted
  spans intact so a value may contain spaces, and surrounding quotes are
  stripped.

### REQ-threemd-007

Every explicit plane SHALL provide a numeric `z` attribute, including support for negative and decimal positions.

Acceptance Criteria

- Each `@plane` directive MUST carry a `z`
  attribute. A directive with no `z` throws
  `ParseError.missingPlanePosition(line:)`. A `z` value that does not parse as a
  `Double` throws `ParseError.invalidPlaneDirective(line:detail:)`. Numbers may
  be integer or decimal and may be negative. ASCII decimal validation scans
  linearly and retains optional signs, fractions and exponents; malformed
  suffixes cannot cause regular-expression backtracking.

### REQ-threemd-008

Plane directives SHALL parse optional numeric `x` and `y`, optional `label`, and preserve non-reserved attributes.

Acceptance Criteria

- The `x` and `y`
  attributes are optional in-plane offsets; when present each MUST parse as a
  `Double` or `ParseError.invalidPlaneDirective` is thrown. `label` is an
  optional human-readable string. The reserved plane attributes are `z`, `x`,
  `y`, and `label`; every other attribute is preserved in `Plane.attributes` as
  a `[String: String]` pair.

### REQ-threemd-009

The parser SHALL assign trimmed Markdown bodies to their planes and preserve pre-plane Markdown as the document preamble.

Acceptance Criteria

- Every line after a directive, up
  to the next `@plane` directive or end of file, is that plane's Markdown body.
  Leading and trailing blank lines of a body are trimmed; an all-whitespace
  body collapses to an empty string. Markdown that appears after the
  frontmatter but before the first `@plane` directive is the document preamble,
  stored in the optional `Document.preamble` with the same blank-line trimming.

### REQ-threemd-010

A frontmatter document with non-empty content and no directive SHALL parse as one implicit plane at `z = 0`.

Acceptance Criteria

- A document with frontmatter but no
  `@plane` directives whose remaining content is non-empty parses as exactly one
  implicit plane at `z = 0`, with that content as the plane body and a `nil`
  preamble. This makes a plain Markdown file with a 3md frontmatter header a
  valid one-plane document.

### REQ-threemd-011

The parser SHALL reject duplicate plane `z` values with `ParseError.duplicatePlane(z:)`.

Acceptance Criteria

- No two planes in a document may share the
  same `z` value. A repeated `z` throws `ParseError.duplicatePlane(z:)`.

### REQ-threemd-012

`Document` SHALL preserve source plane order while providing ascending-Z lookup and sorting helpers.

Acceptance Criteria

- `Document.planes` holds planes in source
  order. `Document.planesByZ` returns them sorted by ascending `z`, and
  `Document.plane(atZ:)` returns the first plane whose `z` equals the argument,
  or `nil`.

### REQ-threemd-013

`Serializer.render` SHALL emit deterministic frontmatter, plane directives, attributes, and non-empty bodies.

Acceptance Criteria

- `Serializer.render` produces 3md text. It always
  emits a frontmatter block with `3md` and `axis` lines, then `title` when set,
  then metadata keys sorted alphabetically. For each plane it emits an `@plane`
  directive (`z`, then `label`, `x`, `y` when set, then extra attributes sorted
  alphabetically) followed by the non-empty body. Whole-number doubles render as
  integers; `label` and extra attribute values are always quoted, and embedded
  double quotes are escaped.

### REQ-threemd-014

Serialization output SHALL parse back to an equal document for representable content, including lossless scalar quoting.

Acceptance Criteria

- Serializing a representable `Document` and parsing the result yields
  an equal document, including literal apostrophes, quotes and scalar edge whitespace.

### REQ-threemd-015

Parsing SHALL normalize Windows CRLF line endings to LF before processing.

Acceptance Criteria

- Parsing normalizes `\r\n` to `\n`
  before processing, so Windows and Unix line endings parse identically.

### Non-Functional Requirements

### REQ-threemd-016

The module SHALL build under Swift 6 strict concurrency for supported Apple platforms, Linux, and Windows.

Acceptance Criteria

- The module builds under Swift 6 strict
  concurrency and targets all supported Apple platforms, Linux, and Windows. It
  relies only on portable Foundation string handling.

### REQ-threemd-017

Public model and service types SHALL provide the documented `Sendable`, value, coding, hashing, and error conformances.

Acceptance Criteria

- `Axis`, `Plane`, `Document`, `ParseError`,
  `Parser`, and `Serializer` are `Sendable`. `Axis`, `Plane`, and `Document`
  are immutable value types that are also `Hashable` and `Codable`;
  `ParseError` is `Equatable`.

### REQ-threemd-018

Library code SHALL handle optionals and conversions without force unwraps, `try!`, or `as!`.

Acceptance Criteria

- Library code uses no force unwraps, `try!`, or
  `as!`. Optionals and failable conversions are handled with `guard` and typed
  throws.

### REQ-threemd-019

The ThreeMD module SHALL depend only on Foundation and no third-party packages.

Acceptance Criteria

- The module depends only on
  Foundation. No third-party packages are used.

### REQ-threemd-020

Parsing SHALL be pure and serialization SHALL order metadata and extra attributes deterministically.

Acceptance Criteria

- Parsing is pure: the same
  input always yields the same `Document`. Serialization is deterministic,
  ordering metadata and extra attributes alphabetically so output is stable.

The original text-surface requirements above retain their stable IDs. The
approved storage/composition delta adds separately versioned Swift APIs; its
optional system Compression use does not introduce a third-party package or
change the portable text-parser dependency contract. The workflow-v2 check
materializes REQ-ThreeMD-021 through REQ-ThreeMD-025 from the approved delta.

## Constraints

- The format definition in `SPEC.md` is authoritative; this module implements
  the frozen 1.0 text grammar and the additive 1.2 storage/composition
  specification. SPEC.md 1.2 adds the structured document payload (payload
  kind 2, section 11.3) inside the unchanged version 1 container; sections 1 to
  10 do not change.
- ThreeMD 2.1 is additive: no public enum gains a case, no existing signature
  changes and no error code is added. The one behavior change is that
  `.binary(compression:)` writes payload kind 2; `encodeTextContainer` writes the
  2.0 kind-1 bytes, and every 2.0 `.3mdb` file stays readable and
  byte-unchanged.
- Kind-2 keys are ordered by raw UTF-8 bytes and strings are stored verbatim, so
  written bytes never depend on Unicode data. Acceptance depends on Unicode data
  only where 2.0 text validation does; cross-port agreement is guaranteed for
  strings of code points assigned in Unicode 13.0 on the pinned CI toolchains.
- Every port trims with the frozen whitespace set W of SPEC.md 11.3.6 (U+0009,
  U+0020, U+00A0, U+1680, U+2000 to U+200B, U+202F, U+205F, U+3000), not the
  platform's character tables.
- The 2.1 `validate` is the 2.0 `validate` with two corrections only: Rust spells
  canonical numbers with the shortest round-trip digits (2.0 misspelled 92
  powers of two), and Swift trims with W instead of `CharacterSet.whitespaces`.
- Frontmatter is parsed line-by-line as simple `key: value` pairs, not as full
  YAML. Nested structures, lists, and multi-line values are not supported.
- Existing parser signatures and frozen syntax stay unchanged. Narrow interchange
  repairs align Unicode whitespace/source-key behavior and make legacy scalar
  quoting faithful. The canonical writer quotes every scalar and requires a
  faithful semantic round trip.
- `z`, `x`, and `y` are parsed as `Double`, so they carry double-precision
  range and rounding.

## Out of Scope

- Changes to the existing Markdown/HTML renderers. The TypeScript link extractor
  is repaired to follow the existing shared grammar without arbitrary truncation.
- External transclusion, inline model embeds, and application-specific placement,
  automatic flattening, voxel interpretation or timing behavior.
- Hosted binary/composition viewer features. The libraries now have the approved
  portable TypeScript/Rust implementations and a separate interchange gate.
- Validation of axis semantics; the axis label is treated as free metadata.
- Networking, file I/O, and any rendering or viewer behavior.
- Payload kind 3 (a structured composition payload), a key-table layout, an
  indexed archive for partial loading, a lazy or partial-access decode API and a
  portable LZFSE backend. Kind 3 is reserved and rejected; the others need a
  later specification revision.

### REQ-ThreeMD-021

The ThreeMD library SHALL round-trip general Document values through a separately versioned binary envelope with portable uncompressed storage and optional conditional Apple LZFSE while retaining existing text grammar and Parser/Serializer behavior.

Acceptance Criteria
- General Unicode, mixed-axis, metadata and finite-coordinate documents round-trip through uncompressed binary and text storage.
- Apple LZFSE round-trips where available and fails explicitly where unsupported.
- The new binary marker is disjoint from Rook's existing voxel-specific 3MDB marker.

### REQ-ThreeMD-022

Storage SHALL validate finite unique positions, serializable values, declared allocation limits, exact lengths, CRC32 integrity, full compression stream consumption and cooperative cancellation without partial output.

Acceptance Criteria
- Fixed header and CRC vectors are independently inspected.
- Corrupt, truncated, trailing, concatenated, oversized, unsupported and cancelled inputs fail predictably.
- Malformed decimal tokens within the byte limits are rejected with linear
  lexical work. Cancellation detected after a failing text parse takes priority
  over conversion of its `ParseError` to a storage validation failure.
- Existing text-parser conformance vectors remain unchanged.

### REQ-ThreeMD-023

Composition SHALL store a root and unique named Document definitions with explicit in-memory references and validate every node, including unused definitions, for safe IDs, target existence, cycles, bounded depth, unique bytes, references and traversal occurrences.

Acceptance Criteria
- Repeated and nested references serialize one definition per ID and preserve generic attributes and mixed axes.
- Missing targets, duplicate IDs, unused-node cycles, depth/byte/reference/occurrence overflow and cancellation fail without partial results.
- Resolution continues after imported original files are removed and never reads filesystem or network paths.

### REQ-ThreeMD-024

The composition codec SHALL use existing 3md syntax and a strict versioned JSON manifest without imposing voxel interpretation or automatic flattening, and its profile Document SHALL also be supported by binary storage.

Acceptance Criteria
- Unknown and duplicate JSON fields and invalid outer-profile structure are rejected.
- Canonical profile round-trips preserve root, definitions and reference order.
- A composition profile survives generic binary wrapping with all referenced definitions intact.

### REQ-ThreeMD-025

Meaningful changes SHALL remain governed by SpecSync 6.0.0 workflow-v2 definition and actual later verification/review/finalization evidence, with immutable Trust 1.2.2 retaining the existing verification lane and risk/provenance policies.

Acceptance Criteria
- The recorded definition accurately cites Leif's direct scope approval with a delegated agent actor and no claim of human implementation review.
- Strict SpecSync coverage and the existing cross-language native checks are executed by the root verification lane.
- Managed agent rules are updated only with Trust adopt; historical evidence is not fabricated or rewritten, and unavailable signer authority is reported without weakening Attest policy.

### REQ-ThreeMD-026

The library SHALL expose optional stable plane identities and per-owning-entry reference identities through the preserved namespaced 3md-id attribute without changing frozen text parsing, legacy z links or composition definition IDs.

Acceptance Criteria
- Identity-aware validation reports empty, unsafe or duplicate IDs with an exact plane path.
- Text and supported binary round trips preserve IDs and arbitrary existing metadata.
- Explicit adoption preserves valid existing IDs and assigns missing identities without interpreting ordinary id attributes.
- Identity-aware edits can change a plane coordinate, source order or reference target without changing its ID.

### REQ-ThreeMD-027

Typed document and composition patches SHALL be immutable Sendable values applied transactionally with exact canonical-content revision comparison and bounded operation counts.

Acceptance Criteria
- Insert, remove, replace and reorder operations target stable IDs and preserve unrelated content.
- Invalid operations, final duplicate positions or reference graphs, stale expected content and cancellation return no partial document or composition.
- Existing no-ID documents remain parseable and identities can be explicitly assigned before ID-targeted edits.

### REQ-ThreeMD-028

Additive diagnostics SHALL expose stable codes, explanatory text and available source line or plane/reference paths without changing existing ParseError cases.

Acceptance Criteria
- Parse failures reuse actual line evidence and never invent a line for value-only diagnostics.
- Identity and patch failures identify the offending plane or operation.
- Diagnostics preserve legacy parser and serializer behavior and do not perform external I/O.

### REQ-ThreeMD-029

Release preparation SHALL publish accurate capability, compatibility and migration documentation while preserving current text conformance and historical lifecycle evidence.

Acceptance Criteria
- New editing and binary/composition APIs are declared Swift-first until other implementations support them.
- No library release/tag, protection change or signer claim is invented.
- Existing format/source APIs remain compatible and later indexed storage, materials and timing remain labeled planned.

### REQ-ThreeMD-030

TypeScript and Rust SHALL expose bounded general-document uncompressed binary and self-contained composition APIs compatible with the Swift format.

Acceptance Criteria
- Readers identify complete magic and enforce exact streams, CRC, UTF-8 and allocation limits.
- Unsupported compression is explicit; LZFSE is unavailable without a platform backend.
- Rust may use exact unicode-normalization 0.1.25 solely for canonical key comparison; no compression dependency is introduced. This records the reviewed Unicode parity repair to the original dependency-free plan.
- Composition validates strict duplicate-aware JSON, all definitions and graph budgets without external I/O.

### REQ-ThreeMD-031

TypeScript and Rust SHALL expose namespaced stable identities, exact canonical-byte revision snapshots, atomic typed patches and bounded structured diagnostics.

Acceptance Criteria
- IDs survive metadata/body/order/position/target edits and legacy id metadata stays opaque.
- Final-only validation supports coordinated swaps and invalid later operations publish no partial result.
- Exact stale revisions, budgets and cooperative cancellation reject safely.
- Diagnostics retain actual line/path evidence and preflight work before expensive validation.

### REQ-ThreeMD-032

All language implementations SHALL share verified portable extension vectors and accurate capability contracts while preserving existing text conformance.

Acceptance Criteria
- Shared vectors exercise canonical numeric and Unicode edge cases, fixed envelopes, composition and identities in Swift, TypeScript and Rust.
- Existing parser/serializer APIs, conformance vectors, viewer behavior and historical archives remain unchanged. The generated web bundle may refresh deterministic compiler output from the new module graph; element/dist stays untouched.
- Complete pinned Trust and strict SpecSync pass with actual scoped agent review and honest provenance limits.
- PRs remain open for Leif and no release or Sculpt dependency migration occurs.

### REQ-ThreeMD-033

Swift, TypeScript and Rust SHALL import and export one another's representable readable documents, canonical text, portable uncompressed binary and self-contained composition profiles without losing supported content or references.

Acceptance Criteria
- Every producer's canonical document and composition output is imported by all three languages and re-exported to identical canonical bytes.
- Finite coordinates, Unicode spelling, quoting, source order, metadata, identities, revisions and graph references survive. Signed zero follows the existing canonical normalization to zero.
- Confirmed grammar interpretation differences are repaired without changing public parser signatures or the frozen grammar; all existing valid and invalid vectors remain mandatory.
- Optional Apple LZFSE is explicitly distinguished from portable text/uncompressed binary.

### REQ-ThreeMD-034

The repository SHALL execute a bounded mandatory public-API interchange matrix in its verification lane, including built JavaScript package execution in Node and no silently skipped manifest cases.

Acceptance Criteria
- A Swift development coordinator drives Swift, TypeScript and Rust adapters for all nine producer/consumer pairs with fixed byte goldens, generated numeric/Unicode cases, imported identity edits and hostile inputs.
- Canonical/profile/binary bytes and semantic numeric fields are checked with exact byte/bit comparisons under the existing zero normalization.
- JavaScript typechecking, declaration builds and package runtime execution are required, alongside all existing language, bundle and editor gates.
- Test transport is development-only, performs no library I/O, and does not establish a public snapshot/patch JSON format or an exhaustive all-input parity claim.

### REQ-ThreeMD-035

The library SHALL provide glyph-ledger composition of supplied files and portable self-contained bundling in Swift, TypeScript and Rust under docs/FILE-COMPOSITION.md. Resolution SHALL preserve document semantics, identities, nested references and shared children, and refuse invalid paths, missing files, cycles, resource overflow and cancellation atomically. Core SHALL perform no file or network I/O. Existing grammar, container and composition profile versions SHALL remain.

Acceptance Criteria:
- Resolve repeated/nested text and binary child files once per normalized path.
- Preserve document/plane identities and opaque reference attributes.
- Portable text/binary bundles reopen without source folders.
- Shared fixtures and all nine writer/reader pairs pass.

### REQ-ThreeMD-036

The Swift, TypeScript and Rust linked-composition resolvers SHALL resolve ledger references without work or memory that grows with the containing file's path, SHALL refuse a ledger edge whose source-file attribute cannot fit the caller's reference attribute byte bound while resolving it, after record-bound and path-grammar refusals and before cycle, depth and missing-file refusals for that reference, and SHALL produce the same results and refusal categories for caller limits, refusal order, path grammar, ledger escapes, cycles and the cached-subtree discovery ceiling, verified through shared files interchange cases in all nine writer/reader pairs. Cancellation during resolution SHALL publish no partial result. The libraries SHALL remain free of file, process and network I/O, and grammar, container, profile and public signatures SHALL remain unchanged. The libraries SHALL build and pass their suites on Linux; Windows execution remains unverified unless separately established.

Acceptance Criteria:
- A multi-megabyte containing directory with thousands of references resolves or refuses quickly in all three ports.
- Lowered-limit, refusal-order, path-grammar, escape, cycle, ceiling, attribute-bound and rebundle cases pass identically in all nine pairs.
- Swift and Rust cancellation during a running resolution returns cancellation with no result.
- A Linux CI job runs all three suites and the interchange.

### REQ-ThreeMD-044

The public docs SHALL describe ThreeMD 2.2.0 as the library in this repository, with the text file and binary named as the two saves, and SHALL name Kind 1 as deprecated. They SHALL identify the release commit for tag `v2.2.0`, and SHALL say npm and crates.io still serve 2.1.0 until the GitHub release is published.

Acceptance Criteria:
- The README leads with ThreeMD 2.2.0, the text file, binary, and Kind 1 as deprecated, and identifies the release commit for tag `v2.2.0`.
- Install docs say npm `@corvidlabs/threemd` 2.1.0 and crates.io `threemd` 2.1.0 stay published until the GitHub release, and Swift `from: "2.2.0"` resolves from tag `v2.2.0`.

### REQ-ThreeMD-045

The public docs SHALL identify Sculpt.3md as the nested Mac app at `apps/sculpt`, package name Rook, building against this checkout. They SHALL keep Swift, TypeScript, and Rust as the three format parsers. They SHALL NOT call the app a fourth parser or call its compact `.3mdb` the upstream binary standard.

Acceptance Criteria:
- Contributor docs name Sculpt.3md at `apps/sculpt`, package name Rook, and still require a format change in Swift, TypeScript, and Rust.
- The docs do not call the app a fourth parser and do not call compact `.3mdb` the upstream binary standard.

