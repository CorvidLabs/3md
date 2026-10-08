# 3md Format Specification

Version: 1.2 (additive storage, composition and linked file authoring specification)
Status: the 1.0 text grammar is frozen; sections 11 and 12 are implemented by ThreeMD 2.1.0 in Swift, TypeScript and Rust; section 11.3 (structured document payload, kind 2) is new in 1.2. ThreeMD 2.2.0 adds a Godot 4 addon for the same text, kind 1, kind 2, composition, linked files, and revision-checked document edits. That addon does not change this specification.
File extensions: `.3md` text; `.3mdb` general binary storage
Media type (proposed): `text/3md`

Sections 1–10 define the unchanged version 1.0 text format. Sections 11–12
define independently versioned storage, composition and linked file authoring
extensions. The Swift, TypeScript and Rust libraries implement portable
uncompressed storage, composition, linked file resolution and typed editing.
Since 1.2 the general binary container also carries a structured document
payload (section 11.3) that decodes without building or parsing text.
Apple LZFSE remains an optional Swift backend; the hosted viewer continues to
implement its existing text contract. The `3md:` key inside a
document's frontmatter declares which format version that document targets. See
section 10 (Stability) for the compatibility guarantees that version 1.0 makes.

### Format version and back-compatibility

The `3md:` frontmatter value identifies the format version a document was
authored against. It is a free string. A conforming parser records this value
and exposes it, but it does NOT reject a document on the basis of the version
string: the parser is version-lenient by design. Any version string is accepted,
and older markers stay valid. A document written as `3md: 0.1` continues to parse
exactly as it did before, so all existing 0.1 documents remain valid 1.0-era
files. The only hard requirement is that the `3md` key be present (it is the
file's magic marker); its value is never validated against a known set.

## 1. Overview

3md is Markdown extended along a single free axis, called the Z axis. An
ordinary Markdown document is two dimensional: characters flow left to right and
blocks flow top to bottom. 3md adds depth: a document is a stack of **planes**,
and each plane is ordinary Markdown.

The author declares what the Z axis means. It can be:

- **time**: a planner, an agenda, a timeline, a changelog
- **depth**: foreground to background stacking
- **layer**: independently toggled overlays (source, translation, annotations)
- **frame**: animation frames played back in order
- **space**: a literal coordinate for scene authoring

The axis label is just metadata. Tools render it; the format does not constrain
what it means.

## 2. Document structure

A 3md document is UTF-8 text with three regions, in order:

1. A required **frontmatter** block.
2. An optional **preamble** of Markdown.
3. Zero or more **planes**.

```
---
3md: 1.0
axis: time
title: My Week
---
Optional preamble Markdown.

@plane z=0 label="Monday"
# Monday
- [ ] Standup

@plane z=1 label="Tuesday"
# Tuesday
```

## 3. Frontmatter

The document MUST begin with a frontmatter block: a line containing exactly
`---`, one or more `key: value` lines, and a closing line containing exactly
`---`. Leading blank lines before the opening fence are allowed.

### 3.1 The 3md frontmatter mini-format

The frontmatter is its own small, flat, line-based key/value format, named here
the **3md frontmatter** mini-format. It is NOT YAML. It only resembles YAML on
the surface; do not feed it to a YAML parser and do not expect YAML semantics.
The grammar is deliberately tiny and is defined exactly as follows:

- Each non-ignored line is a single `key: value` pair, split on the FIRST colon
  on the line. Everything before that colon is the key, everything after it is
  the value. A line with no colon is invalid frontmatter.
- The key is trimmed of surrounding whitespace. The value is trimmed of
  surrounding whitespace before quote handling (see below).
- The `3md`, `axis`, and `title` keys are RESERVED and are matched
  case-insensitively (so `3MD`, `Axis`, and `TITLE` are recognized as the
  reserved keys).
- Every other key is preserved verbatim (its original casing and spelling are
  kept), and its value is ALWAYS a string. Non-reserved values are never coerced
  to numbers, booleans, dates, or any other type.
- Duplicate keys are last-wins: if a key appears more than once, the final
  occurrence in source order is the value that is used.
- Blank lines and lines whose first non-whitespace character is `#` are ignored.
  A `#` line is a comment; it is not a key/value pair.
- A value MAY be wrapped in a matching pair of single (`'`) or double (`"`)
  quotes. When it is, the outer quotes are stripped. Inside such a quoted value,
  `\\` is unescaped to a single backslash and `\"` is unescaped to a double
  quote. An unquoted value is taken verbatim.

Non-goals (it only looks like YAML): there is no nesting, no mappings within a
value, no lists or sequences, no anchors or aliases or references, and no
multi-line scalars (every pair lives on exactly one line). The format is flat by
construction.

### 3.2 Reserved keys

- `3md` (REQUIRED): the format version string. Its presence is the file's magic
  marker. A document without it is not a valid 3md document. The value is
  recorded but never validated; see the back-compatibility note in the header.
- `axis` (OPTIONAL): the meaning of the Z axis. Defaults to `layer`. The value
  is trimmed and lowercased; any string is permitted.
- `title` (OPTIONAL): a human-readable title.
- Any other key is preserved as string metadata, per section 3.1.

Two optional keys are conventional metadata that renderers MAY honor (the parser
treats them as ordinary string metadata, so they never affect parsing):

- `view`: a preferred default view for a renderer to open in. The canonical
  views are `stack` (a 3D deck), `play` (a flipbook for animations), `single` (a
  scrollable reader), `present` (slides), `blend` (a 3D voxel object), and `map`
  (a flat x/y board). A viewer SHOULD let the reader override it, and SHOULD
  accept the older names `layers`, `parallax`, `elevator`, and `scene` as
  aliases of the views that replaced them.
- `legend`: an optional, per-document character map applied only inside fenced
  blocks, given as whitespace- or comma-separated `char=replacement` pairs, e.g.
  `legend: g=🟩 w=🟦 .=·`. Each key is a single source character; the value is
  what it renders as (an emoji, symbol, or short string). With no legend, fenced
  content renders exactly as written; renderers MUST NOT substitute characters
  on their own.

## 4. Planes

A plane begins with a directive line whose first whitespace-delimited token is
`@plane`, followed by space-separated `key=value` attributes. Every attribute
token MUST contain an `=` (the split is on the first `=`); attribute keys are
lowercased. A directive MUST begin at column 0 and MUST lie outside a fenced code
block: a `@plane` line inside a ``` or `~~~` fence, or indented as a code block,
is body text, not a new plane. Every line after the directive, up to the next
`@plane` directive or end of file, is that plane's Markdown body. Leading and
trailing blank lines of a body are trimmed.

### 4.1 Attributes

- `z` (REQUIRED): a finite decimal number giving the plane's position on the Z
  axis. The grammar is an optional sign, digits with an optional fraction, and an
  optional decimal exponent (for example `0`, `-2.5`, `1e3`). Hexadecimal, `inf`,
  and `nan` are rejected so implementations in different languages agree.
- `x`, `y` (OPTIONAL): finite decimal numbers (same grammar as `z`) giving an
  in-plane offset for spatial viewers.
- `label` (OPTIONAL): a human-readable name for the plane.
- Any other attribute is preserved as a string on the plane; values are never
  coerced to numbers or booleans.

Inside a quoted value, `\\` and `\"` are escape sequences for a literal
backslash and a double-quote. An unterminated quote is an error. An unquoted
value is taken verbatim.

Values may be quoted; quote a value if it contains spaces. Numbers may be
integers or decimals and may be negative.

### 4.2 Rules

- Two planes MUST NOT share the same `z` value.
- Plane order in the source is preserved. Viewers MAY reorder by `z`.
- Markdown content before the first `@plane` is the document preamble.

## 5. The single-plane shorthand

If a document has frontmatter but no `@plane` directives, the entire body is one
implicit plane at `z = 0`. This means a normal Markdown file with a 3md
frontmatter header is a valid one-plane 3md document.

## 6. Errors

A conforming parser MUST reject:

- a document with no frontmatter block (`missingFrontmatter`)
- a frontmatter block that is never closed (`invalidFrontmatter`)
- a missing `3md` version key (`missingVersion`)
- a `@plane` directive with no `z` (`missingPlanePosition`)
- a `@plane` directive whose `z`, `x`, or `y` is not a finite decimal number,
  that carries an attribute token with no `=`, or that has an unterminated quote
  (`invalidPlaneDirective`)
- two planes with the same `z` (`duplicatePlane`)

## 7. Round tripping

Serializing a parsed document and parsing the result MUST yield an equivalent
document. Quoted values are escaped on the way out and unescaped on the way in,
so values containing spaces, quotes, or backslashes round-trip exactly.

A leading UTF-8 byte order mark (BOM) is ignored.

## 8. Cross-plane links

A plane body MAY reference another plane by its `z` position with a double-bracket
link:

```
See [[z=2]] for the details, or jump [[z=0|back to the start]].
```

The grammar is `[[z=` followed by a finite decimal (the same grammar as the `z`
attribute), an optional `|` and link text, then `]]`. The reference regular
expression is `\[\[z=([^\]|]+)(?:\|([^\]]*))?\]\]`; if the captured target is not
a finite decimal, the sequence is not a link and stays literal body text.

Cross-plane links live inside Markdown bodies, so the core parser leaves them in
the body verbatim. Implementations expose them through a separate step:

- Extraction returns, in document order (planes in source order, then links
  left to right within a body), one record per link with the source plane's `z`,
  the target `z`, the optional text (absent is null), and whether a plane with
  the target `z` exists in the document (`targetExists`, using the same numeric
  equality as duplicate detection).
- A renderer SHOULD resolve a link to an anchor whose target is the section for
  the plane at that `z`.

This makes link validation (find dangling references) and navigation portable
across implementations, and it is pinned by the shared conformance vectors.

## 9. Relation to prior art

3md borrows the parts of existing formats that work and avoids the parts that
make those formats hard to parse portably. The comparisons below explain what
3md takes and what it deliberately leaves out.

**YAML frontmatter (Jekyll, Hugo, Obsidian).** Static-site and notes tools put a
`---` fenced YAML block at the top of a Markdown file for metadata. YAML is
powerful but large: it has nesting, lists, anchors, typed scalars, and several
multi-line string modes, and its edge cases differ between implementations. 3md
keeps the familiar `---` fence and the `key: value` look, but replaces YAML with
the flat 3md frontmatter mini-format (section 3) so every conforming parser, in
any language, agrees on exactly what a frontmatter line means.

**CommonMark generic and fenced directives (the `:::` proposal).** The directive
proposal adds inline (`:span:`), leaf, and container (`::: name`) directives to
Markdown, fenced by runs of colons with an attribute syntax. It is a general
extension mechanism aimed at arbitrary custom blocks. 3md does not need a general
container syntax: it needs exactly one concept, a plane, so it uses a single
line-prefix directive (`@plane`) at column 0 instead of nestable colon fences,
which keeps plane boundaries unambiguous and easy to scan.

**reveal.js slide separators.** reveal.js splits a Markdown deck into slides with
horizontal rules or configured separator strings, and into vertical stacks with a
second separator, giving a fixed two-level slide structure. 3md generalizes that
idea: instead of a fixed horizontal/vertical split, it offers one free Z axis
whose meaning (time, depth, layer, frame, space) the author declares, and each
plane carries an explicit numeric `z` rather than relying on positional order.

**MDX.** MDX lets authors embed JSX components and JavaScript expressions inside
Markdown, which makes documents expressive but couples them to a JavaScript
toolchain and a compile step. 3md stays plain text and plain Markdown inside each
plane: a plane body is just CommonMark, so any Markdown renderer can display it
and no runtime is required to read the content.

Rationale for 3md's choices: a single free Z axis (one new dimension, with its
meaning chosen by the author rather than baked into the format), line-prefix
`@plane` directives anchored at column 0 (so plane boundaries are trivially
detectable and never ambiguous), and a flat non-YAML frontmatter (so metadata is
portable and parses identically everywhere).

## 10. Stability

Version 1.0 freezes the grammar described in this document. Concretely:

- The 1.0 grammar is frozen. The frontmatter mini-format, the `@plane` directive
  and its attribute grammar, the numeric grammar for `z`/`x`/`y`, the
  single-plane shorthand, cross-plane links, escaping, and the error set are
  stable and will not change within the 1.x line.
- Additive features ship in future MINOR spec versions (1.1, 1.2, and so on). A
  minor version may introduce new optional keys, attributes, or directives, but
  it must not invalidate any document that conforms to an earlier 1.x version.
- Only a new MAJOR version (2.0) may break compatibility. Because parsers are
  version-lenient (section header and section 3.2), bumping the `3md:` value does
  not by itself change how a document parses; compatibility is a property of the
  grammar, not of the version string.
- The shared conformance suite is the contract. The portable test vectors, not
  prose, are the authoritative definition of conforming behavior; any
  implementation that passes them is conforming, and any change that would alter
  their expected results is a breaking change.

### Optional editing identity convention

Swift, TypeScript and Rust editing APIs optionally interpret `3md-id` in plane attributes and composition reference attributes. Existing parsers preserve it as an ordinary string; they never assign IDs or reject otherwise valid text based on this convention. An existing `id` attribute remains application metadata. Identity-aware validation requires a 1...64-byte case-sensitive ASCII identifier, beginning with an alphanumeric and containing only alphanumerics, underscores or hyphens, unique within one document's planes or one composition entry's references.

Explicit identity adoption assigns only missing IDs and preserves valid existing ones. IDs survive changes to content, coordinates, order and reference targets. Existing z-based links and HTML anchors keep their current grammar and semantics. Generic attribute replacement cannot silently change an adopted identity.

Typed editing is an optional library layer above parsing/storage. A patch compares exact canonical expected content, stages bounded operations privately and publishes only a completely validated final document or composition. A revision is a concurrency precondition, not an authenticity claim. Cancellation, stale preconditions and invalid final values produce no partial result. These additions do not change the frozen text grammar or existing binary/composition versions.

## 11. General document storage

Binary storage contains a general 3md `Document`. It does not interpret an axis,
Markdown body, spatial coordinates, glyphs, assets, or application metadata. It
introduces no text directive and does not change `Parser` or `Serializer`.

`DocumentStorageCodec` accepts UTF-8 text or the complete binary magic and returns
a `Document`. The writer takes an explicit `.text` or `.binary(compression:)`
format. Since 1.2, `.binary` writes payload kind 2, the structured document
payload (11.3). Payload kind 1 is deprecated for new files. It remains the
ThreeMD 2.0 save: canonical text behind the binary header. Readers still accept
it, and `encodeTextContainer` still writes it, byte-identical to the ThreeMD 2.0
`.binary` output, for a consumer that still runs ThreeMD 2.0. Text remains the
portable interchange form. The binary extension is `.3mdb` for both payload
kinds; readers MUST identify content by its magic and payload kind rather than
an extension.

### 11.1 Version 1 binary envelope

The header is exactly 40 bytes. All multi-byte integers use little-endian order.
The payload immediately follows the header; no trailing bytes are permitted.

| Offset | Bytes | Field | Version 1 value |
|--------|-------|-------|-----------------|
| 0 | 8 | Magic | `3mdbin\r\n`, hexadecimal `33 6d 64 62 69 6e 0d 0a` |
| 8 | 2 | Container version | `1` |
| 10 | 1 | Payload kind | `1` or `2` (see the payload kind table below) |
| 11 | 1 | Compression | `0` for none; `1` for LZFSE |
| 12 | 4 | Flags | `0` |
| 16 | 4 | Reserved | `0` |
| 20 | 8 | Encoded payload length | Exact payload byte count |
| 28 | 8 | Decoded payload length | Exact uncompressed payload byte count |
| 36 | 4 | CRC-32/ISO-HDLC | Header bytes `0..<36`, followed by the encoded payload |

The payload kind selects the payload grammar. The container layout, magic and
checksum are the same for every kind.

| Kind | Payload | Since | Accepted by |
|------|---------|-------|-------------|
| 1 | Canonical UTF-8 3md text. Readers keep tolerating non-canonical text, as in ThreeMD 2.0 | 1.1 (ThreeMD 2.0) | Storage decode; composition decode, as a profile envelope |
| 2 | Structured document (11.3) | 1.2 (ThreeMD 2.1) | Storage decode; composition decode, as a profile envelope |
| 3 | Reserved for a structured composition payload (11.5) | — | Nothing: `unsupportedPayloadKind(3)` |
| 0, 4–255 | Reserved | — | Nothing: `unsupportedPayloadKind(k)` |

The checksum uses reflected polynomial `0xEDB88320`, initial value
`0xFFFFFFFF`, and final XOR `0xFFFFFFFF`. The check value for ASCII
`123456789` is `0xCBF43926`. The checksum field itself is excluded. CRC detects
accidental corruption; it does not authenticate an author or provide a signature.

Uncompressed payloads are mandatory and portable. LZFSE is optional and uses
Apple's system Compression framework where available. An implementation without
that framework MUST report unsupported compression explicitly. A compressed
stream must terminate exactly once and produce exactly the declared decoded
length.

**Validation order.** A decoder checks a binary input in this order. The first
failing check decides the error, and no later check runs.

| Step | Check | Error |
|------|-------|-------|
| D1 | The limits are invalid. Cancellation is also checked on entry, in the port's 2.0 order (below) | `invalidLimits` |
| D2 | The input is longer than `maximumEncodedBytes` | `oversizedInput` |
| D3 | The input does not begin with the 8-byte magic: decode it as text (11.2), unchanged | — |
| D4 | The input is shorter than 40 bytes | `invalidContainer` |
| D5 | The container version is not 1 | `unsupportedVersion(v)` |
| D6 | The payload kind is not 1 or 2 | `unsupportedPayloadKind(k)` |
| D7 | The compression identifier is not 0 or 1 | `unsupportedCompression(c)` |
| D8 | The flags are not 0 | `unsupportedFlags(f)` |
| D9 | The reserved field is not 0 | `nonzeroReserved` |
| D10 | The decoded payload length is greater than the kind's bound: `maximumDecodedBytes` for kind 1; `min(maximumEncodedBytes − 40, 2 × maximumDecodedBytes)` for kind 2 (11.3.2). The subtraction and the product saturate at the largest host integer | `oversizedOutput` |
| D11 | The encoded length is 0, the decoded length is 0, the encoded length differs from the input length − 40, or compression is 0 and the two lengths differ | `lengthMismatch` |
| D12 | The CRC does not match | `checksumMismatch` |
| D13 | Compression is 1: with no LZFSE backend, `compressionUnavailable(lzfse)`; otherwise decompress, and a stream that does not end exactly once or does not produce exactly the declared length is `lengthMismatch`, and a stream the backend cannot process is `compressionFailed` | as stated |
| D14 | Kind 1: the bounded text decode of 11.2. Kind 2: the structured decode of 11.3.8 | — |

Steps D2 to D13 are the ThreeMD 2.0 sequence, with the accepted kinds of D6
widened and the bound of D10 chosen by kind. A ThreeMD 2.0 reader therefore stops
at D6 with `unsupportedPayloadKind(2)` on a kind-2 file, before it computes the
CRC or reads a payload byte. For D1, each port keeps its ThreeMD 2.0 order of
limit validation and the entry cancellation check: TypeScript checks cancellation
first, Rust validates the limits first, and Swift validates them when
`DocumentDecodeLimits` is constructed. The order is not observable across ports,
because cancellation is not a cross-port outcome.

*Implementation note (informative).* The CRC value is the same for every kind.
A table-driven loop that consumes at least 8 bytes per step (slicing-by-8 or
wider) keeps the kind-1 load time within 10% of the plain text decode; the
ThreeMD release gate measures this. Hardware CRC instructions are permitted but
not required, and every code path must produce the same value.

This magic is deliberately different from the older application-specific `3MDB`
voxel format used by Sculpt/Rook. Those containers do not become this standard;
applications keep their existing readers and explicitly migrate documents.

### 11.2 Validation and resource policy

Storage defaults are the largest integer the language can use as a size:
Swift `Int.max`, Rust `usize::MAX`, and TypeScript `Number.MAX_SAFE_INTEGER`.
That default covers encoded bytes, decoded bytes, physical lines, planes, and
the bytes of one line, scalar, preamble, or plane body. There is no smaller
absolute ceiling. A caller can set a lower positive limit. A limit that is not
a positive integer, or that JavaScript cannot hold exactly, is `invalidLimits`.
A value that fits in 64 bits but not in the host integer is `oversizedOutput`.
On a 32-bit process that integer stops near 2 GiB. That is the language, not a
library policy. A document of 1 GiB, 5 GiB, or any larger size is parsed and
saved when the process can hold it. A hostile file can exhaust the process.

The declared decoded size is checked against the payload kind's bound before
any decompression allocation (11.1, step D10). For payload kind 2 the remaining
limits apply to the document's canonical text, which the reader computes from
the payload without building it (11.3.7). Counts and byte sums
use bounded arithmetic, and long operations cooperatively check cancellation.
Errors return no partial document or encoded payload. Composition profile
ceilings (12.2) and edit budgets stay as specified. They are not this storage
default.

Direct `Document` values must have finite coordinates, unique plane positions,
and fields representable by the existing text grammar. The new storage writer
quotes every scalar and validates a semantic parse round trip. It preserves
literal quotes and backslashes. Legacy scalar quoting is also repaired for
representable values that would otherwise lose apostrophes or edge whitespace. Values
that would change through text serialization, including reserved-key collisions
or significant unrepresentable whitespace, are rejected explicitly.

Canonical extension writers compare dictionary keys by NFC-normalized Unicode
scalar order and preserve original spelling. Raw and bounded text decoding retain the
first spelling and last assigned value of equivalent keys, matching Swift's
dictionary semantics. Strict composition JSON rejects equivalent duplicate
keys. A direct Rust map with both equivalent spellings has no insertion history
and is rejected rather than selecting an arbitrary value. Canonical numeric
spelling is verified by shared IEEE754 fixtures, including the exact `2^53`
boundary. Signed zero normalizes to zero in canonical output, as in the existing
text contract; its sign bit is not stored. Compatibility repairs align the ports'
interpretation of existing whitespace and quoting grammar without new syntax or
changed parser signatures. Legacy numeric spelling may differ when it parses
to the same finite value; canonical storage spelling is exact across languages.
This order applies to canonical text. The structured payload instead stores
keys in raw UTF-8 byte order and rejects canonically equivalent spellings
(11.3.6.1). Trimming, blank-line and edge-whitespace tests use the frozen
whitespace set W (11.3.6) in every port, not the platform's current character
tables.

The API is synchronous and pure, and the package's existing deployment baseline
is unchanged. A caller may run it in a Swift task away from the UI actor.
Cooperative cancellation is checked where Swift concurrency is available:
macOS 10.15, iOS 13, tvOS 13, watchOS 6 or later, and supported non-Apple
platforms. On earlier Apple runtimes the cancellation check is a no-op;
synchronous validation and storage remain available. Cancellation propagates as
`CancellationError` when checked. TypeScript accepts an optional AbortSignal;
Rust accepts explicit OperationOptions with an optional shared CancellationToken.
The ports report typed cancellation and publish no partial result. Uncompressed
storage is supported in all three implementations; requesting LZFSE in either
port reports compressionUnavailable. The APIs do not open files, resolve URLs,
launch a process, or read the network. `encodeTextContainer` is the ThreeMD 2.0
binary writer, unchanged, including its validation and error order.

### 11.3 Structured document payload (kind 2)

#### 11.3.1 Overview and conventions

Payload kind 2 stores a `Document` as a sequence of length-prefixed records in document order, inside the unchanged
version 1 container (11.1). A reader consumes it with one forward cursor. The payload has no offsets, index, string
pool, padding or alignment.

- **Canonical encoding.** Every `Document` has exactly one uncompressed kind-2 encoding, and readers reject every
  other byte sequence. For any uncompressed input `x` and limits `L`, if `decode(x, L)` succeeds then
  `encode(decode(x, L), .binary(.none), L) == x`.
- **Text equivalence.** Under limits `L`, a kind-2 file decodes successfully exactly when (a) its `Document`
  passes the ThreeMD 2.1 `DocumentStorageCodec.validate` under `L` (which never compares the canonical text with
  `maximumEncodedBytes`), and (b) the uncompressed container fits `maximumEncodedBytes`. The 2.1 `validate` is the
  2.0 `validate` with two corrections and no other change: Rust spells numbers with `canonical_number` as fixed in
  2.1 (11.3.7; the 2.0 code rejected 92 powers of two whose spelling did not round-trip), and Swift trims with the
  frozen set W (11.2, 11.3.6) instead of the platform's `CharacterSet.whitespaces`. TypeScript `validate` is
  unchanged. Every later mention of `validate` in 11.3 means the 2.1 `validate`. The decoded
  value equals the bounded text decode (11.2) of that document's canonical text under `L` with
  `maximumEncodedBytes` raised to at least the canonical text length. Readers establish this from the bytes with
  local rules (11.3.6) and exact arithmetic (11.3.7); they build no text except for the rare directive check of
  11.3.6.6.
- **Determinism.** With compression 0, the Swift, TypeScript and Rust writers MUST produce byte-identical files for
  every `Document` that all three accept (11.3.9 lists the inputs outside this guarantee).

The keywords MUST, MUST NOT, SHOULD, SHOULD NOT and MAY follow RFC 2119.

Terms used throughout 11.3:

- **Payload.** The uncompressed payload bytes `P[0 ..< n]`. For compression 0 they are file bytes `40 ..< 40 + n`.
- **Cursor.** The offset in `P` of the next unread byte. It starts at 0 and only moves forward.
- **Remaining.** `n − cursor`, evaluated at the moment of the check. Every check that compares a length or count
  with *remaining* happens after all bytes of the field read so far have been consumed, including the field's own
  length prefix. A field that would extend past `P[n − 1]` is `lengthMismatch`.
- **R, Dmax, Lmax, Pmax, Emax.** The caller's `maximumRecordBytes`, `maximumDecodedBytes`, `maximumLines`,
  `maximumPlanes` and `maximumEncodedBytes`.
- **Canonical text.** The bytes the ThreeMD 2.0 storage text writer (`encode(_, format: .text)`) produces for the
  same `Document`. Its length is `T` and its physical line count is `Lines` (11.3.7).
- Step labels (D, V, C, Str, N, S, P, G, L, Q, W) name the checks below. Conformance vectors cite them.

#### 11.3.2 Container rules for kind 2

The header layout, magic, CRC and check order are those of 11.1. For kind 2:

- The decoded payload length is the uncompressed payload byte count `n`.
- Step D10 rejects `n > min(Emax − 40, 2 × Dmax)` with `oversizedOutput`, before any decompression allocation and
  before the CRC. Because the input length is at least 40 and at most `Emax` at that step, `Emax − 40` is never
  negative.
- After D13, step D14 decodes `P` with Phases S, L and Q (11.3.8).

**Why the bound accepts every valid file (normative note).** The bound never rejects a file that would otherwise
decode, because every payload that passes Phase L4 (`T ≤ Dmax`) satisfies `n < 2 × T ≤ 2 × Dmax`. Each payload part
is at most twice the canonical text it stands for, using the encodings of 11.3.3 (a Var is at most 4 bytes, a
number at most 8 bytes) and the text lengths of 11.3.7:

| Part | Payload bytes, at most | Canonical text bytes, at least |
|------|------------------------|--------------------------------|
| Document fields: flags, version, axis, metadata count, plane count | `17 + len(version) + len(axis)` | `25 + len(version) + len(axis)` (`---` twice, `3md: ""`, `axis: ""`, four LFs) |
| Title | `4 + len(title)` | `10 + len(title)` |
| One metadata entry | `8 + len(key) + len(value)` | `5 + len(key) + len(value)` |
| Preamble (never empty) | `4 + len(preamble)` | `2 + len(preamble)` |
| Plane fixed part: flags, z, attribute count, body length | `17` | `12` (blank line, `@plane z=`, one digit, LF) |
| Each present x or y | `8` | `4` (` x=` and at least one byte) |
| Label | `4 + len(label)` | `9 + len(label)` |
| One attribute | `8 + len(key) + len(value)` | `4 + len(key) + len(value)` |
| Body content | `len(body)` | `len(body) + 1` when the body is not empty |

Every row satisfies `payload ≤ 2 × text`, and the first row satisfies it strictly, so `n < 2 × T`. The tightest
measured case is a plane with form-3 z, x and y and an empty body: 27 payload bytes against 26 text bytes. A kind-2
file can still be larger than its canonical text, so `Emax` is checked on the file itself and never against `T`
(11.3.11).

Implementations SHOULD NOT build result maps or plane values for a payload before Phase L has passed. A reader that
first validates (Phases S, L and Q) and then materializes in a second pass conforms.

#### 11.3.3 Primitive encodings

All fields are byte-packed in the listed order with no padding or alignment. All multi-byte numbers are
little-endian.

**u8.** One byte. No byte remaining: `lengthMismatch`.

**Length and count Var: unsigned LEB128, 1 to 10 bytes.** Each byte carries 7 value bits, least significant group
first, and bit `0x80` means another byte follows. A reader processes the bytes in order; for each byte:

| Step | Condition | Error |
|------|-----------|-------|
| V1 | No byte remains | `lengthMismatch` |
| V2 | The byte is the 10th and has `0x80` set, or the value does not fit in 64 bits | `invalidContainer` |
| V3 | The byte ends a Var of 2 or more bytes and equals `0x00` (non-minimal) | `invalidContainer` |

A value that fits in 64 bits but not in the host integer is `oversizedOutput`. On a 32-bit process that integer
stops near 2 GiB. That is the language, not a library policy.

**Coordinate Var: unsigned LEB128, 1 to 4 bytes.** Form 1 uses this shorter Var. The same V1 to V3 rules apply with
4 in place of 10, so a 4th byte with `0x80` set is `invalidContainer` whether or not a 5th byte exists.
Integer-form coordinates stay inside −2^27 through 2^27 − 1.

Writers emit the minimal form. `00` is 0, `7f` is 127, `80 01` is 128, `ff ff ff 7f` is 2^28 − 1,
`80 80 80 80 01` is 2^28 and `80 80 80 80 14` is 5,368,709,120 (5 GiB). `80 00` and `81 00` are rejected.
`ff ff ff ff 01` is 2^29 − 1 as a length or count. The same bytes are rejected as a coordinate.

**Count(min).** Read `k` as a Var. If `k > floor(remaining ÷ min)`, the result is `lengthMismatch`. `min` is the
smallest encoding of one element (given with each count). Implementations MUST divide rather than multiply, so that
a 32-bit `Int` cannot overflow, and MUST NOT reserve storage for `k` elements before this check.

**Str(class, limit).** A length-prefixed UTF-8 string:

| Step | Condition | Error |
|------|-----------|-------|
| Str1 | Read the length `m` as a Var. `m > remaining` | `lengthMismatch` |
| Str2 | `m > limit` | `oversizedRecord` |
| Str3 | The `m` bytes are not well-formed UTF-8 (Unicode Table 3-7: no overlong forms, no surrogates, nothing above U+10FFFF, no truncated sequence). Each Str is validated on its own; a scalar split across two fields is ill-formed in both | `invalidUTF8` |
| Str4 | Class *scalar*: the bytes contain `0x0A` or `0x0D`. Class *segment*: the rules of 11.3.6.4 | `invalidDocument` |

Strings are stored exactly as spelled: no normalization, no trimming, and U+FEFF and U+0000 are ordinary content.

**Number(form).** A finite binary64 coordinate in one of three forms. The form is a 2-bit code in the plane flags
(11.3.5). The reader applies the checks of a row from left to right:

| Form | Bytes | Value | Canonical when | Reader rejects |
|------|-------|-------|----------------|----------------|
| 0 | 0 | absent | x or y only | form 0 for z: `invalidContainer` (P1) |
| 1 | a Var `u`, 1 to 4 bytes | the zigzag integer `(u >> 1) XOR −(u AND 1)`, converted exactly to binary64 | the value is integral and `−2^27 ≤ v ≤ 2^27 − 1` | nothing beyond the Var rules; every `u` decodes inside the range |
| 2 | 4, IEEE binary32 | widened exactly to binary64 | not form 1, and `binary32(v) == v` | fewer than 4 bytes: `lengthMismatch`; non-finite: `invalidDocument`; a form-1 value, including −0: `invalidContainer` |
| 3 | 8, IEEE binary64 | itself | neither form 1 nor form 2 | fewer than 8 bytes: `lengthMismatch`; non-finite: `invalidDocument`; a form-1 or form-2 value, including −0: `invalidContainer` |

Negative zero has no encoding: zigzag 0 is +0, and forms 2 and 3 reject −0. A writer normalizes −0 to +0 and picks
the first form whose condition holds. The exactness tests round to nearest-even in every language:

- TypeScript: `Number.isInteger(v)` and `Math.fround(v) === v`;
- Swift: `v.rounded(.towardZero) == v` and `Double(Float(v)) == v`;
- Rust: `v.trunc() == v` and `f64::from(v as f32) == v`.

**Flag bytes.** A bit that this specification does not define MUST be 0; otherwise `invalidContainer`.

#### 11.3.4 Field sizes (informative summary)

| Field | Encoding | Smallest valid size |
|-------|----------|---------------------|
| Count and length prefixes | Var | 1 |
| Strings | Str | 1 (empty) |
| Coordinates | Number | 1 (form 1) |
| One metadata entry | key Str, value Str | 2 |
| One attribute | key Str, value Str | 3 (the key is never empty) |
| One plane | 11.3.5.2 | 4 (`01 00 00 00`) |
| One document | 11.3.5.1 | 6 (`00 01 31 00 00 00`) |

#### 11.3.5 Payload layout

The kind-2 payload is exactly one DocumentRecord, starting at payload offset 0.

##### 11.3.5.1 DocumentRecord

| Step | Field | Encoding | Present | Rule and error |
|------|-------|----------|---------|----------------|
| S1 | documentFlags | u8 | always | bit 0: title present; bit 1: preamble present; bits 2–7 set: `invalidContainer` |
| S2 | version | Str(scalar, R) | always | empty: `invalidDocument` |
| S3 | axis | Str(scalar, R) | always | rule R2 (11.3.6.2): `invalidDocument` |
| S4 | title | Str(scalar, R) | bit 0 | — |
| S5 | metadataCount M | Count(2) | always | — |
| S6 | M × (key, value) | key Str(scalar, R), value Str(scalar, R) | — | for each entry, in this order: the key's Str rules; key order (11.3.6.1, `invalidContainer`); rule R3 on the key (`invalidDocument`); the value's Str rules |
| S6b | — | — | — | after the last entry: key equivalence (11.3.6.1, `invalidDocument`) |
| S7 | preamble | Str(segment, R − 1) | bit 1 | segment rules with role *preamble* |
| S8 | planeCount P | Count(4) | always | `P > Pmax`: `tooManyPlanes`; preamble present and `P = 0`: `invalidDocument` |
| S9 | P × PlaneRecord | 11.3.5.2 | — | check cancellation before each plane |
| S10 | end | — | — | remaining ≠ 0: `lengthMismatch` |

##### 11.3.5.2 PlaneRecord

| Step | Field | Encoding | Present | Rule and error |
|------|-------|----------|---------|----------------|
| P1 | planeFlags | u8 | always | bits 0–1: z form (1 to 3); bits 2–3: x form (0 to 3); bits 4–5: y form (0 to 3); bit 6: label present; bit 7 set or z form 0: `invalidContainer` |
| P2 | z | Number(z form) | always | 11.3.3 |
| P3 | x | Number(x form) | x form ≠ 0 | 11.3.3 |
| P4 | y | Number(y form) | y form ≠ 0 | 11.3.3 |
| P5 | label | Str(scalar, R) | bit 6 | — |
| P6 | attributeCount A | Count(3) | always | — |
| P7 | A × (key, value) | key Str(scalar, R), value Str(scalar, R) | — | for each entry, in this order: the key's Str rules; key order (`invalidContainer`); the value's Str rules |
| P7a | — | — | — | after the last entry: key equivalence (`invalidDocument`) |
| P7b | — | — | — | if no key of this plane contains byte `0x22` (`"`) or `0x27` (`'`): rule R9 on each key in stored order (`invalidDocument`). Otherwise the plane is *marked* for Phase Q |
| P8 | body | Str(segment, R) | always | segment rules with role *body*; *final* is true only for the last plane |

#### 11.3.6 Representability rules

These rules describe exactly the documents whose ThreeMD 2.0 canonical text (11.2) parses back to an equal document,
the set that the 2.1 `DocumentStorageCodec.validate` (11.3.1) accepts once limits are set aside. Every violation is
`invalidDocument(detail)`, except key order (`invalidContainer`). Detail strings are informative and are not compared
across languages.

**W** is the frozen whitespace set: U+0009, U+0020, U+00A0, U+1680, U+2000 to U+200B, U+202F, U+205F and U+3000.
In UTF-8 these are `09`, `20`, `C2 A0`, `E1 9A 80`, `E2 80 80` to `E2 80 8B`, `E2 80 AF`, `E2 81 9F` and
`E3 80 80`. A *line* is a maximal run of bytes containing no `0x0A`. A line is *blank* when every scalar in it is in
W; the empty line is blank.

##### 11.3.6.1 Key order and key equivalence (S6, S6b, P7, P7a)

**Order.** Within one map (the metadata, or one plane's attributes), keys are stored in strictly increasing order
of their raw UTF-8 bytes, compared lexicographically as unsigned bytes, where a proper prefix sorts first. A key
whose bytes are not greater than the previous key's bytes (including identical bytes) is `invalidContainer`. This
order uses no Unicode data. It equals Unicode code point order, and it is not UTF-16 code unit order: a TypeScript
writer MUST NOT sort with `<` on strings.

**Equivalence.** After the last entry of a map, if two keys of that map have equal NFC forms (they are canonically
equivalent but have different bytes), the result is `invalidDocument` ("Canonically equivalent dictionary keys cannot
be represented faithfully."). A map whose keys are all ASCII needs no check. Otherwise compare NFC forms with a hash
set or by sorting them; an ASCII key's NFC form is itself, but a non-ASCII key's NFC form can be ASCII (U+212A KELVIN
SIGN normalizes to `K`).

Swift `String` equality and hashing are canonical equivalence, so a `Set<String>` insertion that collides is exactly
this rule. Where a rule elsewhere needs byte equality, Swift code compares `utf8`.

##### 11.3.6.2 Field rules

- **R2, axis.** The axis bytes equal the port's own ThreeMD 2.0 axis normalization of the axis (trim W from both
  ends, then lowercase), compared byte for byte: Swift `Axis(rawValue:).rawValue` compared on `utf8`; TypeScript
  `trimFoundationWhitespace(axis).toLowerCase()`; Rust `threemd::axis(axis)`. The empty axis is valid. ASCII fast
  path: an all-ASCII axis passes exactly when it contains no `A` to `Z` and does not begin or end with `0x20` or
  `0x09`.
- **R3, metadata key.** All of the following hold; the empty key is valid:
  - it contains no `:`;
  - its first and last scalars are not in W;
  - its first byte is not `#`;
  - an ASCII case-insensitive comparison does not equal `3md`, `axis` or `title`. (No non-ASCII scalar's full
    lowercase mapping produces those strings, so the ASCII comparison is exact.)
- **R9, attribute key, for planes where no key contains a quote character.** All of the following hold:
  - it is not empty;
  - it contains no `0x20`, `0x09` or `=`;
  - its first and last scalars are not in W;
  - it equals its own lowercase mapping under the port's ThreeMD 2.0 writer function: Swift `lowercased()`,
    TypeScript `toLowerCase()`, Rust `to_lowercase()`. ASCII fast path: no `A` to `Z`;
  - it is not `z`, `x`, `y` or `label`.

  Planes where some key contains a quote character are decided entirely by Phase Q (11.3.6.6).
- **Values** (the title, metadata values, labels and attribute values) need only the scalar rule. The canonical
  writer quotes them and escapes `"` and `\`.

##### 11.3.6.3 Document rules

- **R7, unique positions.** No two planes have equal z. Checked at L0 (11.3.8). Because −0, NaN and infinities
  cannot be stored, equal bit patterns and equal numeric values coincide.
- **R8.** A preamble requires at least one plane (S8).

##### 11.3.6.4 Segment rules (preamble and bodies)

The input is a well-formed UTF-8 segment `S`, its role (*preamble* or *body*) and the flag *final*, which is true
only for the last plane's body. The checks run in this order:

| Step | Rule |
|------|------|
| G1 | `S` is empty: a body is valid and the scan ends; a preamble is invalid (an empty preamble collapses to absent) |
| G2 | The last byte of `S` is `0x0D`: invalid (the writer's following LF would form CRLF) |
| G3 | `S` contains `0D 0A`: invalid (the parser normalizes CRLF) |
| G4 | Split `S` at every `0x0A` into lines L1 to Ln, n = LF(S) + 1. L1 or Ln is blank: invalid (the parser trims blank edge lines) |
| G5 | Scan the lines in order with `fence = none`. For each line Li, let U be Li with its leading W scalars removed. If fence is backtick and U starts with three backticks, or fence is tilde and U starts with `~~~`, set fence to none. Otherwise, if fence is none and U starts with three backticks, set fence to backtick; otherwise, if fence is none and U starts with `~~~`, set fence to tilde; otherwise, if fence is none and Li itself equals `@plane` or starts with `@plane` followed by `0x20` or `0x09`: invalid (the line would start a plane). While a fence is open, a line that starts with the other fence character changes nothing |
| G6 | *final* is false and fence is not none at the end: invalid (an open fence would swallow the next directive). The preamble always has *final* false |

G2, G3 and G4 to G6 may be evaluated in one pass, but the reported rule (and therefore only the detail text) can
differ; the code is `invalidDocument` either way. The scan also outputs `LF(S)` for 11.3.7. An implementation MAY
scan the decoded string instead of the bytes: every rule inspects only LF, CR and BMP scalars of W, so the results
are identical.

##### 11.3.6.5 Rules that need no check

The bounded text decode also enforces the record limit on physical lines inside bodies and the preamble. That limit
is implied by Str2 on the whole segment. Version strings are never interpreted. Numbers other than coordinates do not
exist in the payload.

##### 11.3.6.6 Phase Q: the directive round trip for keys that contain quotes

For each marked plane, in plane order, build its canonical directive line exactly as the ThreeMD 2.0 storage writer
does:

```
"@plane z=" N(z) [" label=" q(label)] [" x=" N(x)] [" y=" N(y)] { " " key "=" q(value) }
```

Here `N(v)` is the canonical storage number spelling (11.3.7) and `q(s)` is `"`, then `s` with every `"` and `\`
preceded by `\`, then `"`. The attributes appear in the port's ThreeMD 2.0 writer order (NFC scalar order: Swift
`String <`, TypeScript `canonicalKeys`, Rust `normalized_key`), not in stored order. Parse the line with the port's
ThreeMD 2.0 plane-directive grammar (section 4).

The plane is representable exactly when the parse succeeds and yields the stored z, x, y and label and an attribute
map whose keys and values are byte-equal to the stored ones. Anything else is `invalidDocument`.

Implementations SHOULD reuse their 2.0 parser, for example by parsing the minimal document
`---\n3md: "1"\naxis: "a"\n---\n\n` + line + `\n`. This keeps keys such as `a''b`, `a'b c'd` and `"x y"` valid and
`a'b`, `a"b` and a key pair `a'`, `b'` invalid, exactly as in text.

#### 11.3.7 Canonical text metrics

These formulas give exactly the length and line count of the canonical text the ThreeMD 2.0 writer would produce.
They were checked against the real writer on every corpus document and at limit edges N and N + 1.

- `esc(s)` is the number of bytes `0x22` and `0x5C` in `s`; `Q(s) = len(s) + 2 + esc(s)` is the quoted length.
- `N(v)` is the canonical storage number spelling and `Nn(v)` its byte length, 1 to 24: integral values with
  `|v| < 10^15` as integers; values with `0 < |v| < 10^-4` or `|v| > 2^53` in shortest round-trip scientific notation
  with an explicit exponent sign and at least two exponent digits (`1e-05`, `-2.5e+20`); all other values in shortest
  round-trip decimal notation, with `.0` appended to integral values (`1000000000000000.0`). Ports: TypeScript
  `canonicalNumber`; Swift `formatted3MD()`; Rust `storage::canonical_number`, which 2.1 fixes to emit the same
  shortest round-trip digits (it misspelled 92 powers of two in 2.0). A form-1 value spells as its decimal digits,
  plus one byte for a leading `-`.
- Frontmatter line lengths, without the LF: version `5 + Q(version)`; axis `6 + Q(axis)`; title `7 + Q(title)`;
  each metadata entry `len(key) + 2 + Q(value)`.
- Directive line length of plane p:
  `DirLen(p) = 9 + Nn(z) + [7 + Q(label)] + [3 + Nn(x)] + [3 + Nn(y)] + Σ attributes (2 + len(key) + Q(value))`.
- Canonical text length:
  `T = 4 + (6 + Q(version)) + (7 + Q(axis)) + [8 + Q(title)] + Σ metadata (3 + len(key) + Q(value)) + 4 + [2 + len(preamble)] + Σ planes (2 + DirLen(p) + [len(body) + 1 if body is not empty])`.
- Physical lines:
  `Lines = 5 + [1 if title] + M + [2 + LF(preamble) if preamble] + Σ planes (2 + [1 + LF(body) if body is not empty])`.

A form-2 or form-3 number needs formatting only when the bound `1 ≤ Nn ≤ 24` cannot decide a check. An
implementation MAY skip formatting whenever the bound decides; the result is exact either way.

#### 11.3.8 Decoding

The decoder runs Phase S, then Phase L, then Phase Q, then returns. The first failing check in this order is the
reported error. Implementations MAY fuse loops or materialize strings during Phase S, but MUST report errors in this
precedence.

**Phase S (structure and fields)** runs S1 to S10 and P1 to P8 and accumulates the inputs to 11.3.7: string lengths,
`esc` of every quoted scalar (version, axis, title, metadata values, labels and attribute values), `LF` counts and
the form-2 and form-3 numbers. Phase S also enforces the per-string record limits (every scalar at most R, the
preamble at most R − 1, each body at most R) and Pmax. The R − 1 bound reproduces the bounded decoder's preflight,
which charges the blank line before the preamble.

**Phase L (limits).**

| Step | Check | Error |
|------|-------|-------|
| L0 | Two planes have equal z (R7). Any algorithm may be used, for example a hash set of bit patterns or a sorted copy | `invalidDocument` ("Plane positions must be unique.") |
| L1 | `R < 3` (the canonical text always contains a 3-byte `---` line) | `oversizedRecord` |
| L2 | Any frontmatter line (version, axis, title, then metadata in stored order) is longer than R | `oversizedRecord` |
| L3 | Any `DirLen(p) > R`, in plane order | `oversizedRecord` |
| L4 | `T > Dmax` | `oversizedOutput` |
| L5 | `Lines > Lmax` | `tooManyLines` |

**Phase Q** runs 11.3.6.6 for each marked plane in plane order, with a cancellation check before and after each
plane's parse.

**Result.** The decoded value is built from the stored strings and numbers. It equals the bounded text decode of the
document's canonical text (11.3.1). Per port:

- **Swift:** `Document(version:axis:title:metadata:preamble:planes:)` with `Axis(rawValue:)` (R2 guarantees the
  stored bytes survive) and `[String: String]` maps (S6b and P7a guarantee no two keys collide).
- **TypeScript:** the plain-object shape of the 2.0 bounded decoder. The document object has the properties
  `version, axis, title, metadata, preamble, planes`, created in that order; each plane has `z, label, x, y,
  attributes, body`, in that order. Absent values are `null`. Metadata and attribute objects are created with
  `Object.create(null)`, so `__proto__` is an ordinary key, and keys are inserted in stored order (raw UTF-8 byte
  order). JavaScript enumerates integer-like keys (such as `"9"` and `"10"`) first in ascending numeric order
  whatever the insertion order, and the 2.0 bounded decode inserts keys in canonical text order, so `Object.keys`
  order can differ from the text decode's; the 2.0 `documentsEqual` comparison, which ignores key order, defines
  equality. Nothing is frozen.
- **Rust:** `threemd::Document` with `BTreeMap` maps.

**Resource bounds.** Phase S does linear work and allocates at most a constant factor of `n`, which D10 bounds by
`2 × Dmax`. Phase Q runs only after L3 and L4 have bounded each directive line by R and the whole text by Dmax, so
its total work is linear in `T`. No partial document is ever observable.

#### 11.3.9 Writing

`DocumentStorageCodec.encode(document, format: .binary(compression), limits)` runs:

| Step | Action | Error |
|------|--------|-------|
| W1 | Validate the limits and check cancellation, in the port's 2.0 order (11.1, D1) | `invalidLimits` |
| W1b | `Emax < 40` | `oversizedInput` |
| W2 | Normalize as each port's 2.0 text writer does (below) | as stated |
| W3 | Emit the fields of 11.3.5 in order into a buffer capped at `Emax − 40` payload bytes; the cap is checked before each append, so nothing is allocated past it | `oversizedInput` |
| W4 | Self-check: run the reader's Phases S, L and Q over the emitted payload under the same limits. The first failure is the writer's error | the reader's codes |
| W5 | Compression: LZFSE without a backend: `compressionUnavailable(lzfse)`; an unknown identifier (TypeScript only): `unsupportedCompression`; LZFSE with a backend: compress, with the output capped at `Emax − 40` | as stated |
| W6 | Write the header (version 1, kind 2, flags 0, reserved 0, both lengths, CRC) and the payload; check cancellation; return | — |

All cap arithmetic MUST be checked or saturating; W1b makes `Emax − 40` non-negative.

**W2 per port.**

- **TypeScript.** Canonically equivalent keys in one map are merged, keeping the first spelling in insertion order
  and the last value, exactly as the 2.0 `canonicalStrings`. When a map of the input actually contains equivalent
  keys, the writer first runs the 2.0 `validateRecords` check on the unmerged input, including its rejection of
  lone surrogates in strings that the merge would drop (`invalidDocument`); this keeps acceptance identical to 2.0
  `validate`. A string that holds a lone surrogate is `invalidDocument` ("Strings must contain losslessly
  representable Unicode scalar values."), never a U+FFFD substitution.
- **Rust.** A map with canonically equivalent spellings is `invalidDocument`, as in 2.0.
- **Swift.** A `[String: String]` cannot hold two canonically equivalent keys.
- **All ports.** −0 becomes +0. Keys are written in raw UTF-8 byte order of the (merged) spellings: Swift sorts with
  `$0.key.utf8.lexicographicallyPrecedes($1.key.utf8)`; TypeScript compares code points; Rust iterates the
  `BTreeMap`. Non-finite coordinates, duplicate z and unrepresentable fields are left to W4, and W2 MUST NOT reject
  them. W3 emits a non-finite coordinate with the same form tests as any other value: ±∞ fails the form-1 range
  test and is binary32-exact, so it takes form 2 (4 bytes); NaN fails both tests and takes form 3 (8 bytes). Those
  bytes count against the W3 cap like any others, and W4 then rejects the value with `invalidDocument`. A document
  with a non-finite coordinate therefore reports `oversizedInput` in every port when its emission exceeds the cap;
  otherwise W4 reports the first failure in reader order, which is `invalidDocument` at that coordinate unless an
  earlier check fails.

**W4 is the same predicate as decoding.** The self-check MUST call the same reader routine that decoding uses. It MAY
skip building the result values, and it MAY skip UTF-8 validation of bytes the writer produced from native strings
that are well-formed by construction (Swift `String`, Rust `&str`, and TypeScript strings that passed the
lone-surrogate check and were encoded by `TextEncoder`). It MUST NOT substitute a separate predicate on the source
values.

**Determinism rules.**

1. Fields, flags and counts are exactly as in 11.3.5, with no extra bytes.
2. Every Var is minimal.
3. Numbers use the canonical form, and −0 is written as +0.
4. Keys are in raw UTF-8 byte order and keep their spelling; values are verbatim; planes keep their order.
5. Strings are never normalized; byte order marks and line endings are never changed.
6. LZFSE bytes are outside the byte-identity contract, as in 2.0; their decoded payload is canonical.

The writers of the three ports produce identical bytes for every input that all three accept. Two kinds of input are
outside this guarantee and MUST NOT appear in cross-port interchange or fuzz vectors: maps with canonically
equivalent keys (TypeScript merges them, Rust rejects them, Swift cannot hold them), and LZFSE output.

**Error precedence.** For an invalid document the writer reports the structured precedence above. This can differ
from the code that `format: .text` reports for the same document, but the accept or reject decision is always the
same as the 2.1 `validate` (11.3.1), except that kind 2 additionally requires the file to fit `Emax` and does not
compare `T` with `Emax`.

#### 11.3.10 Compression

LZFSE (compression 1) applies to kind 2 as to kind 1: the whole payload is compressed, the CRC covers the compressed
bytes, D10 bounds the decompression allocation, and the 2.0 single end-marker rule applies. Swift on Apple platforms
reads and writes LZFSE. TypeScript and Rust report `compressionUnavailable(lzfse)`: after the CRC on decode (D13) and
after the self-check on encode (W5). Compression never changes acceptance, because every rule is defined on the
uncompressed payload, and the uncompressed container must fit `Emax` whether or not it is compressed.

#### 11.3.11 Limits

`DocumentDecodeLimits` keeps the same five fields. No limit is added. Each field defaults to the largest positive
integer the host can use. A caller can lower any field. A non-positive value is `invalidLimits`.

| Limit | Text and kind 1 | Kind 2 |
|-------|-----------------|--------|
| `maximumEncodedBytes` (Emax) | input bytes | the input, and the uncompressed container (`40 + n ≤ Emax`); never compared with `T` |
| `maximumDecodedBytes` (Dmax) | decompressed text bytes | the canonical text length `T` (L4); also bounds `n ≤ 2 × Dmax` at D10 |
| `maximumLines` (Lmax) | physical lines | `Lines` (L5) |
| `maximumPlanes` (Pmax) | planes | planeCount (S8) |
| `maximumRecordBytes` (R) | each line, scalar, preamble and body | each scalar ≤ R, preamble ≤ R − 1, body ≤ R (Phase S); frontmatter lines and directive lines ≤ R and R ≥ 3 (L1 to L3) |

A length or count Var holds any host integer, in at most 10 bytes. A coordinate Var holds at most 2^28 − 1, and
integer-form coordinates have magnitude at most 2^27. A kind-2 file may be accepted under an `Emax` that its
canonical text would exceed (80 empty planes: a 382-byte file, `T = 1056`); decoding it and saving it as text under
the same limits then fails with `oversizedInput`. Conversion succeeds whenever the target encoding fits `Emax`.

#### 11.3.12 Error codes

No code is added. Kind 2 maps onto the existing stable codes of `DocumentStorageError`:

| Condition | Code |
|-----------|------|
| A truncated field; a Var or Str longer than remaining; count framing; trailing bytes; container length rules | `lengthMismatch` |
| A 10th length or count Var byte with `0x80`; a 4th coordinate Var byte with `0x80`; a non-minimal Var; a value that does not fit in 64 bits; an undefined flag bit; z form 0; a non-canonical number form or −0; keys out of byte order or identical | `invalidContainer` |
| Ill-formed UTF-8 | `invalidUTF8` |
| A string over R, or the preamble over R − 1; `R < 3`; a frontmatter or directive line over R | `oversizedRecord` |
| A kind-2 decoded length over `min(Emax − 40, 2 × Dmax)`; `T > Dmax`; a length or count that fits in 64 bits but not the host integer | `oversizedOutput` |
| `Lines > Lmax` | `tooManyLines` |
| `planeCount > Pmax` | `tooManyPlanes` |
| A file longer than Emax; a writer payload over `Emax − 40`; `Emax < 40` on write | `oversizedInput` |
| A non-finite coordinate, duplicate z, a scalar line break, an empty version, R2, R3, R9, the segment rules, a preamble without planes, a Phase Q failure, equivalent keys, a TypeScript lone surrogate | `invalidDocument(detail)` |
| Payload kind 0 or 3 to 255 | `unsupportedPayloadKind(k)` |
| Cancellation | Swift `CancellationError`, the TypeScript AbortSignal reason, Rust `Cancelled` |

Inside `DocumentCompositionCodec.decode` and `DocumentFileComposition.resolve`, a binary envelope or child is
decoded with storage decode, as in 2.0: `oversizedInput`, `oversizedOutput` and `oversizedRecord` become
`profileBytesExceeded` for envelopes; every other storage code is raised as `DocumentStorageError` (Rust:
`DocumentCompositionError::Storage(code)`), including `unsupportedPayloadKind(3)`.

Only descriptions change: Swift `invalidContainer` becomes "The binary container or its structured payload encoding
is invalid.", and `unsupportedPayloadKind` becomes "Unsupported 3md binary payload kind N for this operation."

#### 11.3.13 Cancellation and partial results

Cancellation is checked:

- on entry, before or after limit validation in the port's 2.0 order (11.1, D1);
- during the CRC at least every 65,536 payload bytes, and after it;
- before each plane (S9), during decoding and during emission (W3);
- within every hand-written byte scan (scalar scans, segment scans) at least every 65,536 bytes;
- within UTF-8 validation of a string longer than 65,536 bytes, at least every 65,536 bytes;
- before and after each Phase Q parse;
- before returning.

Between two checks an implementation performs at most 65,536 bytes of scanning or validation (plus up to 3 bytes to
complete a scalar), or one native string construction of at most R bytes, or one Phase Q parse of one directive line
of at most R bytes.

Chunked UTF-8 validation is exact: split a string at a scalar boundary at most 65,536 bytes after the previous split
(step back over at most 3 continuation bytes). If no boundary exists within 3 bytes, the string is ill-formed in any
case. The concatenation of well-formed chunks is well-formed, and an ill-formed string always has an ill-formed
chunk, provided that every chunk, including the last, is validated as a complete string. Examples: TypeScript
`TextDecoder.decode(chunk)` with `fatal: true` and no `stream` option on each chunk (because every chunk ends at a
scalar boundary, no call needs to stream); Rust `std::str::from_utf8` on chunks; Swift `String(decoding:as:)` plus a
byte comparison per chunk.

A TypeScript implementation MAY instead split at arbitrary byte offsets and stream: every chunk except the last is
decoded with `{ stream: true }`, and the last chunk with `{ stream: false }`, which flushes the decoder and reports
a truncated trailing sequence. A decoder whose last call was streamed holds pending bytes, so it MUST NOT be reused
for another string, and a decoder MUST NOT be reused after a decode error; such an implementation creates a new
decoder for each chunked string. (If the last chunk were also streamed, a string ending in `E2 82` would decode
without error and its pending bytes would join the next string: on Node 26 and Bun 1.4,
`decode([61 E2 82], {stream: true})` returns `"a"` and a following `decode([AC 62])` returns `"€b"`, so two
ill-formed strings would be accepted where Swift and Rust report `invalidUTF8`.)

A cancelled or failed operation returns no document and no encoded bytes.

#### 11.3.14 Compatibility

- **ThreeMD 2.0 readers on 2.1 files.** Every 2.0 reader stops at D6 with `unsupportedPayloadKind(2)`, or earlier
  with `oversizedInput` when the file exceeds its Emax. This covers storage decode, composition decode (Rust:
  `Storage(UnsupportedPayloadKind(2))`) and the linked-file resolver. No 2.0 reader computes the CRC of, or
  interprets, a kind-2 payload. Plain text parsers see `3mdbin` and report `missingFrontmatter`. Sculpt and Rook
  `3MDB` files have a different magic.
- **2.1 readers on 2.0 files.** Text and kind 1 decode exactly as in 2.0, including the leniency toward
  non-canonical text and every error.
- **2.1 writers.** `.binary(compression:)` writes kind 2. `encodeTextContainer` writes the 2.0 kind-1 bytes,
  byte-identical, for consumers that must stay on 2.0. `DocumentCompositionCodec.encode` still writes the readable
  profile text.
- **Unchanged APIs.** `isBinary`, the error enums and the limit types do not change. `validate` keeps its signature
  and changes only by the two corrections of 11.3.1 (Rust number spelling, Swift frozen whitespace set).

#### 11.3.15 Unicode data

Kind-2 bytes never depend on Unicode data: key order is byte order and strings are stored verbatim. Acceptance
depends on Unicode data in the same places as 2.0 text validation: key equivalence (NFC), R2 and R9 (lowercase
mapping; W trimming uses the frozen set and no tables) and Phase Q (the parser lowercases keys). Each port uses its
runtime's data: Swift its standard library and Foundation, TypeScript its engine's ICU, and Rust
`unicode-normalization` 0.1.25 and the standard library's case tables. The reference toolchains used to produce the
fixtures (Swift 6.3.3, Node 26.10, Bun 1.4, Rust 1.95 with `unicode-normalization` 0.1.25) carry Unicode 17.0 data;
the CI and release receipts record each runtime's Unicode version.

**Cross-port guarantee.** The three ports agree on acceptance, on the code reported and on the decoded value for
every input whose strings contain only code points assigned in Unicode 13.0, when they run on the pinned ThreeMD 2.1
CI toolchains (Swift 6.3.3, Node 24, Bun 1.4.2, and Rust 1.95 with `unicode-normalization` 0.1.25, as pinned by the
repository's Linux and perf workflows). Unicode's normalization stability policy keeps the NFC form of such a string unchanged in every later
version, and its case-pair stability policy keeps the case pairs among such code points, so a later Unicode version
in a pinned toolchain is not expected to change a result; the interchange gate runs again whenever a pinned toolchain
changes. Runtimes older than the pinned toolchains are outside this guarantee: ThreeMD declares no runtime
minimum (`Package.swift` names no `platforms`, so SwiftPM's defaults apply, and `js/package.json` has no `engines`
field), and an older OS ICU or engine may carry Unicode data older than 13.0. This restriction replaces running the
interchange gate on the oldest supported runtimes.

The assigned set is committed as `scripts/structured/unicode-13.0-assigned.json`: the inclusive code point ranges
whose DerivedAge is 13.0 or earlier (283,506 code points in 686 ranges, including private use, surrogates and
noncharacters). The fixture generator rejects any anchor or cross-port vector string outside the set, and the P4 and
P7 generators of the test plan exclude such inputs. Per-port skew vectors outside that set (for example U+0897 after
U+0316, and the Garay case pair U+10D50 and U+10D70, all assigned in Unicode 16.0) record the expected result on
Unicode 17 data and run only in single-port suites.

#### 11.3.16 Implementation notes (informative)

- **Swift UTF-8.** `String(decoding:as: UTF8.self)` replaces ill-formed input with U+FFFD, which always changes the
  bytes. The input is well-formed exactly when the result's UTF-8 equals the input byte for byte (`withUTF8` and
  `memcmp`). This works on every deployment target; no hand-written validator is needed.
- **Swift equality.** `String ==`, `Hashable` and `Dictionary` use canonical equivalence. Byte-exact comparisons
  (axis normalization, Phase Q results, key identity) compare `utf8`.
- **TypeScript.** Decode strings with one lazily created `TextDecoder("utf-8", { fatal: true, ignoreBOM: true })`
  and only non-streaming calls, so the shared decoder never holds pending bytes (11.3.13); `ignoreBOM: true` is
  required because a string may begin with U+FEFF. Read the u64 header lengths with `getBigUint64`. Copy, or read
  once, any caller buffer.
- **32-bit platforms.** Count uses division; every length fits 28 bits; cap arithmetic is checked.
- **Speed.** The ThreeMD release gate measures and enforces the load-time targets (kind 2 at least 4 times faster
  than the bounded text decode and faster than the legacy parser, kind 1 within 10% of the bounded text decode).
  They are not part of the format.

#### 11.3.17 Worked examples

All values are hexadecimal. Each example is a complete file.

**Example 1: a document.** The canonical text is 144 bytes and 13 physical lines:

```
---
3md: "1.0"
axis: "time"
title: "Week"
owner: "ops"
---

@plane z=0 label="Mon"
# Standup

@plane z=1.5 label="Tue" x=-2 kind="note"
Ship it
```

The kind-2 file is 113 bytes, with CRC-32 `0x8A5B3B70`:

```
offset  bytes                                            meaning
0       33 6d 64 62 69 6e 0d 0a                          magic "3mdbin\r\n"
8       01 00                                            container version 1
10      02                                               payload kind 2
11      00                                               compression 0
12      00 00 00 00                                      flags 0
16      00 00 00 00                                      reserved 0
20      49 00 00 00 00 00 00 00                          encoded length 73
28      49 00 00 00 00 00 00 00                          decoded length 73
36      70 3b 5b 8a                                      CRC-32 0x8A5B3B70 over bytes 0..<36 and 40..<113
40      01                                               S1 documentFlags: title present
41      03 31 2e 30                                      S2 version "1.0"
45      04 74 69 6d 65                                   S3 axis "time"
50      04 57 65 65 6b                                   S4 title "Week"
55      01                                               S5 metadataCount 1
56      05 6f 77 6e 65 72                                S6 key "owner"
62      03 6f 70 73                                      S6 value "ops"
66      02                                               S8 planeCount 2
67      41                                               P1 plane 0: z form 1, label present
68      00                                               P2 z = 0 (zigzag 0)
69      03 4d 6f 6e                                      P5 label "Mon"
73      00                                               P6 attributeCount 0
74      09 23 20 53 74 61 6e 64 75 70                    P8 body "# Standup"
84      46                                               P1 plane 1: z form 2, x form 1, label present
85      00 00 c0 3f                                      P2 z = 1.5 (binary32)
89      03                                               P3 x = -2 (zigzag 3)
90      03 54 75 65                                      P5 label "Tue"
94      01                                               P6 attributeCount 1
95      04 6b 69 6e 64                                   P7 key "kind"
100     04 6e 6f 74 65                                   P7 value "note"
105     07 53 68 69 70 20 69 74                          P8 body "Ship it"
```

Metrics: `T = 4 + 11 + 13 + 14 + 13 + 4 + (2 + 22 + 10) + (2 + 41 + 8) = 144`; `Lines = 5 + 1 + 1 + 3 + 3 = 13`;
`DirLen` is 22 for plane 0 and 41 for plane 1. A 2.0 reader stops at offset 10 with `unsupportedPayloadKind(2)`.

**Example 2: number forms and escaping.** Version `1.0`, axis `layer`, one plane with `z=0.1`, `x=0.5`,
`y=268435456`, attribute `note` = `say "hi"` and an empty body. The canonical text is 83 bytes (7 lines):

```
---
3md: "1.0"
axis: "layer"
---

@plane z=0.1 x=0.5 y=268435456 note="say \"hi\""
```

The kind-2 file is 86 bytes, with CRC-32 `0xDB5A2326`:

```
offset  bytes                                            meaning
0       33 6d 64 62 69 6e 0d 0a 01 00 02 00 00 00 00 00  magic, version 1, kind 2, compression 0, flags 0
16      00 00 00 00                                      reserved 0
20      2e 00 00 00 00 00 00 00                          encoded length 46
28      2e 00 00 00 00 00 00 00                          decoded length 46
36      26 23 5a db                                      CRC-32 0xDB5A2326
40      00                                               S1 documentFlags: none
41      03 31 2e 30                                      S2 version "1.0"
45      05 6c 61 79 65 72                                S3 axis "layer"
51      00                                               S5 metadataCount 0
52      01                                               S8 planeCount 1
53      2b                                               P1: z form 3, x form 2, y form 2 (2^28 is outside the integer form)
54      9a 99 99 99 99 99 b9 3f                          P2 z = 0.1 (binary64)
62      00 00 00 3f                                      P3 x = 0.5 (binary32)
66      00 00 80 4d                                      P4 y = 268435456 (binary32)
70      01                                               P6 attributeCount 1
71      04 6e 6f 74 65                                   P7 key "note"
76      08 73 61 79 20 22 68 69 22                       P7 value: say "hi", stored unescaped
85      00                                               P8 empty body
```

**Example 3: key byte order.** Version `1`, empty axis, metadata `z` = `1` and `é` = `2` where `é` is spelled
decomposed (U+0065 U+0301, bytes `65 CC 81`), and one plane at `z=-3` with attributes `b` = `x` and `a` = `y`. The
canonical text (67 bytes, 9 lines) lists `z` before `é`, because text uses NFC scalar order (U+007A < U+00E9):

```
---
3md: "1"
axis: ""
z: "1"
é: "2"
---

@plane z=-3 a="y" b="x"
```

The kind-2 file stores `é` before `z`, because its first byte `65` is smaller than `7a`. The file is 68 bytes, with
CRC-32 `0x649EB26B`:

```
offset  bytes                                            meaning
0       33 6d 64 62 69 6e 0d 0a 01 00 02 00 00 00 00 00  magic, version 1, kind 2, compression 0, flags 0
16      00 00 00 00                                      reserved 0
20      1c 00 00 00 00 00 00 00                          encoded length 28
28      1c 00 00 00 00 00 00 00                          decoded length 28
36      6b b2 9e 64                                      CRC-32 0x649EB26B
40      00                                               S1 documentFlags: none
41      01 31                                            S2 version "1"
43      00                                               S3 axis ""
44      02                                               S5 metadataCount 2
45      03 65 cc 81                                      S6 key "é" (decomposed)
49      01 32                                            S6 value "2"
51      01 7a                                            S6 key "z"
53      01 31                                            S6 value "1"
55      01                                               S8 planeCount 1
56      01                                               P1: z form 1
57      05                                               P2 z = -3 (zigzag 5)
58      02                                               P6 attributeCount 2
59      01 61                                            P7 key "a"
61      01 79                                            P7 value "y"
63      01 62                                            P7 key "b"
65      01 78                                            P7 value "x"
67      00                                               P8 empty body
```

Storing the metadata keys in text order (`z`, then `é`) is `invalidContainer` (vector
`order-nfc-instead-of-bytes`). Adding the precomposed `é` (`C3 A9`) as a third key, after `z` in byte order, is
`invalidDocument` at S6b, because it is canonically equivalent to the decomposed key.

#### 11.3.18 Conformance

Conformance requires all three ports to agree on:

- the structured anchors in `conformance/structured/` and the four `conformance/extensions/*.structured.3mdb`
  files (together one kind-2 file for every valid interchange case, including the profile envelopes of the
  composition cases), byte for byte on write and as the same `Document` on read;
- the hostile and limit vectors in `conformance/structured/vectors.json`, by error code under each vector's limits;
- the differential properties of the ThreeMD test plan (writer acceptance equals the 2.1 `validate`, decode equals
  the bounded text decode, re-encoding is byte-identical, and the three ports report the same code for every mutated
  file), for inputs inside the Unicode 13.0 set of 11.3.15;
- the interchange gate (protocol `3md-interchange-2`) and a job that runs the ThreeMD 2.0.0 readers on the
  structured anchors and vectors.

### 11.4 Rationale (informative)

- **Flat records.** Structure is about 1% of the bytes; the measured cost per byte is in strings (UTF-8 validation,
  string construction, line scans and the CRC). Of three prototyped layouts (flat records, a string pool, an indexed
  archive), the flat layout was the fastest in both measured languages and the simplest to make canonical.
- **Tagged numbers.** 94.6% of measured coordinates are small integers (99.0% in the Examples). Three forms keep the
  exact bits with no decimal conversion.
- **Byte-order keys.** Unicode normalization data differs between runtime versions. Byte order makes the written
  bytes independent of that data; equivalence is still rejected, so a stored map is always representable as text.
- **Text equivalence.** A binary file can always be saved as text and a valid text document as binary, subject to
  `Emax` for the target encoding. The cost is a few integer sums per field and the rare Phase Q parse.
- **No lazy API.** A full decode of a 4 MB file takes 6 to 10 ms; partial validity was measured to cost more than it
  saves.

### 11.5 Reserved extension points

- **Payload kind 3** is reserved for a structured composition payload (definitions as embedded document records,
  references as indices). It needs a specification revision with its own measurements. ThreeMD 2.1 readers reject it
  with `unsupportedPayloadKind(3)` from storage decode, composition decode and the file resolver.
- **Payload kinds 4 to 255.** Candidates include a key-table layout for voxel-style stacks (3.0 to 5.3% smaller on
  Sculpt inputs in the measurements) and an indexed archive for partial loading.
- **Flag bits** in documentFlags (bits 2–7), planeFlags (bit 7) and the container flags field: optional features.
- **Compression identifiers 2 to 255:** a portable codec.

Each needs a specification revision. ThreeMD 2.1 readers reject all of them with the existing codes.

## 12. Self-contained document composition

A composition stores one root ID and a library of unique named `Document`
definitions. Each definition has ordered references to IDs in that same
library. The documents keep their own axes, metadata and Markdown; reference
attributes are opaque strings interpreted by the consuming application.
No voxel placement, rendering transform, automatic flattening, or external
transclusion is implied.

IDs are case-sensitive ASCII strings of 1–64 bytes matching
`[A-Za-z0-9][A-Za-z0-9_-]*`. An ID is never a filesystem path or URL. A target
must exist in the supplied library. Definitions are stored once even when
referenced repeatedly. Validation covers every definition, including unused
ones, so an unreachable missing target or cycle is an error.

### 12.1 The `3md-composition-1` profile

The readable profile uses existing 3md syntax: version `0.1`, axis `layer`,
metadata exactly `profile: 3md-composition-1`, no title or preamble, and one
plane at `z=0` labelled `Composition`, without coordinates or extra attributes.
The plane body is one fenced `json` object with exactly these fields:

```json
{
  "schema": "3md-composition-1",
  "rootID": "root",
  "entries": [
    {
      "id": "root",
      "source": "---\n3md: \"0.1\"\naxis: \"layer\"\n---\n\n@plane z=0\n# Collection\n",
      "references": [
        {"targetID": "chapter", "attributes": {"role": "first"}},
        {"targetID": "chapter", "attributes": {"role": "again"}}
      ]
    },
    {
      "id": "chapter",
      "source": "---\n3md: \"0.1\"\naxis: \"time\"\n---\n\n@plane z=0\n# Reusable chapter\n",
      "references": []
    }
  ]
}
```

`source` is canonical readable 3md text, not a path. Writers sort definitions by
ID, preserve reference order, and use the general storage text writer for each
definition. Readers reject unknown or duplicate JSON fields, invalid envelope
structure, malformed child documents, and unsupported profiles. The profile's
outer document can itself be stored through the general binary
codec, keeping all definitions and references intact: `.binary` stores it as
payload kind 2, and `encodeTextContainer` as payload kind 1 for ThreeMD 2.0
readers. Composition decode accepts readable text and kind-1 and kind-2
envelopes. Payload kind 3 is reserved (11.5) and reported as
`unsupportedPayloadKind(3)`.

### 12.2 Graph and resource limits

The standard policy permits at most 1,024 definitions, 16,384 reference records,
64 nodes along a dependency path, 16 MiB summed unique canonical definition
bytes, and 20 MiB profile bytes. Each definition's reachable traversal has at
most 1,000,000 occurrences, counting shared targets each time they are reached.
Each reference permits at most 64 attributes and 16 KiB summed UTF-8 key/value
bytes. Callers can lower each limit but cannot raise these ceilings.

The codec uses an explicit 20 MiB outer record policy for the escaped JSON
manifest while child documents use their separately supplied document policy.
A binary envelope is decoded by storage decode with `maximumEncodedBytes`,
`maximumDecodedBytes` and `maximumRecordBytes` equal to `maximumProfileBytes`
and `maximumPlanes` equal to 1. For kind 2 the decoded-length bound is therefore
`maximumProfileBytes − 40`. Oversized storage results map to
`profileBytesExceeded`; every other storage failure keeps its storage code.
Before object decoding it bounds JSON nesting and record counts and rejects
duplicate decoded keys. Missing roots or targets, duplicate IDs, cycles,
excessive depth, byte/count/occurrence overflow, and available task cancellation fail without
partial output. Lookup only returns a definition supplied in memory; source
files may be removed after import without affecting the composition.

### 12.3 Linked file authoring

The optional ordinary-document metadata string `3md-files` is a strict JSON
glyph-to-relative-filename ledger. A host explicitly supplies file bytes to the
Swift, TypeScript or Rust file-composition API. Core performs no filesystem or
network I/O. Recursive resolution deduplicates normalized paths and preserves
generic document content, existing identities and nested self-contained graphs.
Portable bundling removes the external ledger and writes the existing
`3md-composition-1` profile, retaining glyph and source-file provenance
attributes; a binary bundle is that profile document stored as payload kind 2.
Supplied children may be text or payload kind 1 or 2 (uncompressed, or LZFSE
where a backend exists); a kind-3 child is refused with
`unsupportedPayloadKind(3)`.
The normative path, ordering, bounds and refusal contract is
[FILE-COMPOSITION.md](docs/FILE-COMPOSITION.md). Existing parser grammar and
container/profile versions do not change. Placement remains a host concern.

## 13. Open questions for later versions

- Inline 3D model embeds, for example `@model src="scene.glb"`.
- Hosted/remote transclusion, filesystem watchers and linked-file editor policy.
- Per-plane transition or timing hints for `frame`/`time` axes.
- Hosted viewer adoption of the storage, composition and editing extensions.
- A portable optional LZFSE backend for TypeScript and Rust.
- Payload kind 3 (structured composition), a key-table layout and an indexed
  archive for partial loading (11.5).
