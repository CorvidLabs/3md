# 3md Format Specification

Version: 1.0
Status: stable (frozen grammar)
File extension: `.3md`
Media type (proposed): `text/3md`

This document defines version 1.0 of the 3md format. The `3md:` key inside a
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

## 11. Open questions for later versions

- Inline 3D model embeds, for example `@model src="scene.glb"`.
- Transclusion across documents.
- Per-plane transition or timing hints for `frame`/`time` axes.
- A binary or compressed container for large scenes.
