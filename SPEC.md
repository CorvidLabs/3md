# 3md Format Specification

Version: 1.1 (additive storage and composition specification)
Status: the 1.0 text grammar is frozen; the new extensions are implemented on this branch, not a published release
File extensions: `.3md` text; `.3mdb` general binary storage
Media type (proposed): `text/3md`

Sections 1–10 define the unchanged version 1.0 text format. Sections 11–12
define independently versioned storage and composition extensions. The Swift,
TypeScript and Rust libraries implement portable uncompressed storage,
composition and typed editing. Apple LZFSE remains an optional Swift backend;
the hosted viewer continues to implement its existing text contract. The `3md:` key inside a
document's frontmatter declares which format version that document targets. See
section 9 (Stability) for the compatibility guarantees that version 1.0 makes.

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
format. Text remains the portable interchange form. The binary extension is
`.3mdb`; readers MUST identify content by its magic rather than an extension.

### 11.1 Version 1 binary envelope

The header is exactly 40 bytes. All multi-byte integers use little-endian order.
The payload immediately follows the header; no trailing bytes are permitted.

| Offset | Bytes | Field | Version 1 value |
|--------|-------|-------|-----------------|
| 0 | 8 | Magic | `3mdbin\r\n`, hexadecimal `33 6d 64 62 69 6e 0d 0a` |
| 8 | 2 | Container version | `1` |
| 10 | 1 | Payload kind | `1`, canonical UTF-8 3md text |
| 11 | 1 | Compression | `0` for none; `1` for LZFSE |
| 12 | 4 | Flags | `0` |
| 16 | 4 | Reserved | `0` |
| 20 | 8 | Encoded payload length | Exact payload byte count |
| 28 | 8 | Decoded payload length | Exact UTF-8 text byte count |
| 36 | 4 | CRC-32/ISO-HDLC | Header bytes `0..<36`, followed by the encoded payload |

The checksum uses reflected polynomial `0xEDB88320`, initial value
`0xFFFFFFFF`, and final XOR `0xFFFFFFFF`. The check value for ASCII
`123456789` is `0xCBF43926`. The checksum field itself is excluded. CRC detects
accidental corruption; it does not authenticate an author or provide a signature.

Uncompressed payloads are mandatory and portable. LZFSE is optional and uses
Apple's system Compression framework where available. An implementation without
that framework MUST report unsupported compression explicitly. A decoder MUST
reject an unknown version, kind, compression identifier, flags, reserved value,
inconsistent length, checksum mismatch, truncated or concatenated stream, or
unused trailing input. A compressed stream must terminate exactly once and
produce exactly the declared decoded length.

This magic is deliberately different from the older application-specific `3MDB`
voxel format used by Sculpt/Rook. Those containers do not become this standard;
applications keep their existing readers and explicitly migrate documents.

### 11.2 Validation and resource policy

Storage defaults to 64 MiB encoded bytes, 64 MiB decoded bytes, 100,000 physical
lines, 65,536 planes, and 8 MiB per line, scalar, preamble, or plane body.
Callers can lower these limits. The record limit can be raised explicitly up to
the absolute 64 MiB ceiling; other limits cannot exceed their defaults. Declared
decoded size is checked before decompression allocation. Counts and byte sums
use bounded arithmetic, and long operations cooperatively check cancellation.
Errors return no partial document or encoded payload.

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
launch a process, or read the network.

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
outer document can itself be stored through the general binary codec, keeping
all definitions and references intact.

### 12.2 Graph and resource limits

The standard policy permits at most 1,024 definitions, 16,384 reference records,
64 nodes along a dependency path, 16 MiB summed unique canonical definition
bytes, and 20 MiB profile bytes. Each definition's reachable traversal has at
most 1,000,000 occurrences, counting shared targets each time they are reached.
Each reference permits at most 64 attributes and 16 KiB summed UTF-8 key/value
bytes. Callers can lower each limit but cannot raise these ceilings.

The codec uses an explicit 20 MiB outer record policy for the escaped JSON
manifest while child documents use their separately supplied document policy.
Before object decoding it bounds JSON nesting and record counts and rejects
duplicate decoded keys. Missing roots or targets, duplicate IDs, cycles,
excessive depth, byte/count/occurrence overflow, and available task cancellation fail without
partial output. Lookup only returns a definition supplied in memory; source
files may be removed after import without affecting the composition.

## 13. Open questions for later versions

- Inline 3D model embeds, for example `@model src="scene.glb"`.
- Explicit external transclusion and resolver policy.
- Per-plane transition or timing hints for `frame`/`time` axes.
- Hosted viewer adoption of the storage, composition and editing extensions.
- A portable optional LZFSE backend for TypeScript and Rust.
