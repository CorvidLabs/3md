# 3md Format Specification

Version: 0.1 (draft)
Status: experimental
File extension: `.3md`
Media type (proposed): `text/3md`

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
3md: 0.1
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

- `3md` (REQUIRED): the format version string. Its presence is the file's magic
  marker. A document without it is not a valid 3md document.
- `axis` (OPTIONAL): the meaning of the Z axis. Defaults to `layer`. The value
  is trimmed and lowercased; any string is permitted.
- `title` (OPTIONAL): a human-readable title.
- Any other key is preserved as string metadata.

Blank lines and lines beginning with `#` inside the frontmatter are ignored.
Values may be wrapped in matching single or double quotes; the quotes are
stripped.

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

## 9. Open questions for later versions

- Inline 3D model embeds, for example `@model src="scene.glb"`.
- Transclusion across documents.
- Per-plane transition or timing hints for `frame`/`time` axes.
- A binary or compressed container for large scenes.
