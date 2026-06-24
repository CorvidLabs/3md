# 3md

**Markdown with a Z axis.** A `.3md` file is ordinary Markdown extended along
one free axis: stack your content into **planes** and tell the reader what the
depth means. Time for a daily planner. Frames for an animation. Layers for
annotations. Space for a scene.

```
---
3md: 0.1
axis: time
title: My Week
---
@plane z=0 label="Monday"
# Monday
- [ ] Standup

@plane z=1 label="Tuesday"
# Tuesday
```

This repository holds the format specification ([SPEC.md](SPEC.md)), example
documents ([Examples/](Examples)), `ThreeMD` (a cross-platform Swift parser), a
TypeScript port, and a shared cross-implementation conformance suite
([conformance/](conformance)).

## Why

Markdown is two dimensional. Plenty of documents are not: a planner moves
through time, an annotated contract has overlay layers, an ASCII animation is a
stack of frames. 3md keeps Markdown's plain-text simplicity and adds one axis,
with the author declaring what that axis means. Nothing comparable ships today;
the closest prior art renders existing Markdown into 3D rather than giving the
text a depth dimension of its own.

## Installation

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/CorvidLabs/3md", from: "0.3.0")
```

Then depend on the `ThreeMD` library product:

```swift
.product(name: "ThreeMD", package: "3md")
```

### JavaScript / TypeScript

A faithful TypeScript port of the Swift parser is published on npm. The two
implementations are kept in sync by the shared conformance suite
([conformance/](conformance)).

```bash
bun add @corvidlabs/threemd
```

```ts
import { parse, serialize } from "@corvidlabs/threemd";

const document = parse(source);
console.log(document.axis); // "time"

// Round trips back to text:
const text = serialize(document);
```

## Library usage

```swift
import ThreeMD

let document = try Parser().parse(source)
print(document.axis)          // Axis(rawValue: "time")
for plane in document.planesByZ {
    print(plane.label ?? "", plane.body)
}

// Round trips back to text:
let text = Serializer().render(document)
```

## Command-line tool

The `threemd` CLI ships with the package and self-documents (run `threemd
--help`). A path of `-` reads from standard input.

```bash
swift run threemd validate <file>   # parse a file; print "ok" or exit non-zero with the error
swift run threemd info <file>       # print version, axis, title, and each plane's position
swift run threemd html <file>       # render the document to HTML on stdout
```

## Format at a glance

- A required `---` frontmatter block declares `3md:` (the version, and the file's
  magic marker), an optional `axis:`, an optional `title:`, and free metadata.
- `@plane z=... label="..."` directives start planes; the Markdown between
  directives is the plane body.
- A plain Markdown file with a 3md header and no directives is a valid one-plane
  document.

See [SPEC.md](SPEC.md) for the full grammar and conformance rules.

## Examples

The [Examples/](Examples) directory has one document per axis:

- [`daily-planner.3md`](Examples/daily-planner.3md) - `axis: time`, one plane per day.
- [`animation.3md`](Examples/animation.3md) - `axis: frame`, one plane per frame.
- [`layered-notes.3md`](Examples/layered-notes.3md) - `axis: layer`, stacked overlay layers.

## Development

This repo uses the CorvidLabs trust toolchain. The single gate is:

```bash
fledge lanes run verify
```

which runs format, lint, and build. See [AGENTS.md](AGENTS.md) for the standing
rules every contributor and agent follows.

Each implementation has its own tests (the Swift suite has 53 tests, the
TypeScript suite 58), and both run the shared 36-vector conformance suite in
[conformance/](conformance), which is the cross-implementation contract that
keeps the parsers behaving identically.

## Status

The format and spec are at version 0.1 (experimental), and the grammar may still
change before 1.0. The packages are at v0.3.0.
