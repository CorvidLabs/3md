---
module: ThreeMD
version: 1
status: draft
files:
  - Sources/ThreeMD/Axis.swift
  - Sources/ThreeMD/Plane.swift
  - Sources/ThreeMD/Document.swift
  - Sources/ThreeMD/ParseError.swift
  - Sources/ThreeMD/Parser.swift
  - Sources/ThreeMD/Serializer.swift
  - Sources/ThreeMD/HTMLRenderer.swift

db_tables: []
depends_on: []
---

# ThreeMD

## Purpose

ThreeMD is a cross-platform Swift parser and serializer for the 3md format:
Markdown extended along one free Z axis. It turns `.3md` source text into a
typed `Document` of `Plane` values and renders that document back to text. The
authoritative format definition lives in `SPEC.md`; this module spec describes
the implementing API.

## Public API

### Structs & Enums

| Type | Description |
|------|-------------|
| `Axis` | The meaning of the Z axis (time, depth, layer, frame, space, or custom). |
| `Plane` | One Markdown slice with a `z` position and optional `x`, `y`, `label`, attributes. |
| `Document` | A parsed document: version, axis, title, metadata, preamble, planes. |
| `ParseError` | Errors thrown while parsing 3md source. |
| `Parser` | Parses 3md source text into a `Document`. |
| `Serializer` | Renders a `Document` back into 3md source text. |
| `HTMLRenderer` | Renders a `Document` as a standalone, accessible HTML5 document. |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `Parser.parse` | `func parse(_ source: String) throws -> Document` | Parse 3md source into a document. |
| `Serializer.render` | `func render(_ document: Document) -> String` | Render a document to 3md text. |
| `HTMLRenderer.render` | `func render(_ document: Document) -> String` | Render a document to a standalone HTML5 string. |
| `Document.planesByZ` | `var planesByZ: [Plane]` | Planes sorted by ascending z. |
| `Document.plane(atZ:)` | `func plane(atZ z: Double) -> Plane?` | Look up a plane by z. |

## Invariants

1. A valid document always has frontmatter declaring a non-empty `3md` version.
2. No two planes in a document share the same `z` value.
3. A document with frontmatter but no `@plane` directives yields exactly one
   plane at `z = 0`.
4. Serializing a document and re-parsing the result yields an equal document,
   for content that does not depend on quote escaping.

## Behavioral Examples

```
Given a frontmatter block with `3md: 0.1` and two `@plane` directives
When Parser.parse is called
Then the result has two planes ordered by source position, each carrying its
     own Markdown body
```

## Error Cases

| Error | When | Behavior |
|-------|------|----------|
| `missingFrontmatter` | Source has no opening `---` block | `parse` throws |
| `invalidFrontmatter` | Frontmatter is malformed or unclosed | `parse` throws |
| `missingVersion` | Frontmatter omits the `3md` key | `parse` throws |
| `missingPlanePosition` | A `@plane` directive has no `z` | `parse` throws |
| `invalidPlaneDirective` | `z`, `x`, or `y` is not numeric | `parse` throws |
| `duplicatePlane` | Two planes share a `z` value | `parse` throws |

## Dependencies

- Foundation (string handling only)

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1 | 2026-06-23 | Initial spec for the 0.1 parser and serializer. |
| 1 | 2026-06-23 | Add HTMLRenderer: standalone HTML5 output with per-plane sections, HTML escaping, axis and title metadata. |
