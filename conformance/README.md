# 3md Conformance Vectors

This directory holds language-agnostic test vectors for the 3md format. Every
3md implementation (the canonical Swift parser, the TypeScript package under
`js/`, and any future implementation) MUST pass all of these vectors. They are
the shared contract that keeps implementations behaving identically.

The vectors are derived directly from `SPEC.md` and the canonical Swift parser
in `Sources/ThreeMD`.

## Vector format

Each vector is a single JSON file in this directory. There are two kinds of
vector, distinguished by whether the object has an `expected` key (valid input)
or an `error` key (invalid input).

### Valid case

```json
{
  "name": "human-readable description",
  "source": "<the full .3md source text>",
  "expected": {
    "version": "0.1",
    "axis": "layer",
    "title": null,
    "metadata": {},
    "preamble": null,
    "planes": [
      {
        "z": 0,
        "label": null,
        "x": null,
        "y": null,
        "attributes": {},
        "body": ""
      }
    ]
  }
}
```

Parsing `source` MUST produce a document deep-equal to `expected`. Field rules:

- `version`: the required `3md` frontmatter value (the format's magic marker).
- `axis`: trimmed and lowercased; defaults to `"layer"` when absent.
- `title`: the `title` frontmatter value, or `null` when absent.
- `metadata`: all frontmatter keys other than `3md`, `axis`, and `title`.
- `preamble`: Markdown before the first plane, or `null`. It is always `null`
  in the single-plane shorthand (no `@plane` directives).
- `planes`: an array, in source order. Each plane has a numeric `z`, a `label`
  (or `null`), numeric `x`/`y` (or `null`), an `attributes` object of any other
  directive keys, and a `body` whose surrounding blank lines are trimmed.

### Invalid case

```json
{
  "name": "human-readable description",
  "source": "<the full .3md source text>",
  "error": "duplicatePlane"
}
```

Parsing `source` MUST throw, and the thrown error MUST identify the named case.
The `error` value is one of the canonical parser error names:

- `missingFrontmatter`: the document does not begin with a `---` block.
- `invalidFrontmatter`: the frontmatter is never closed, or a line is not
  `key: value`.
- `missingVersion`: the frontmatter omits the required `3md` version key.
- `missingPlanePosition`: a `@plane` directive has no `z` attribute.
- `invalidPlaneDirective`: a `@plane` directive has a non-numeric `z`, `x`, or
  `y`, or carries an attribute token with no `=`.
- `duplicatePlane`: two planes share the same `z` value.

## Notes for implementers

- Normalize `\r\n` to `\n` before parsing.
- A `@plane` attribute token with no `=` is an error. It MUST NOT be silently
  skipped.
- Numbers may be integers or decimals and may be negative.
- The single-plane shorthand applies only when a document has frontmatter but
  no `@plane` directives: the whole body becomes one plane at `z = 0`.
