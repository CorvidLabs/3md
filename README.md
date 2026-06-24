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
documents ([Examples/](Examples)), and `ThreeMD`, a cross-platform Swift parser.

## Why

Markdown is two dimensional. Plenty of documents are not: a planner moves
through time, an annotated contract has overlay layers, an ASCII animation is a
stack of frames. 3md keeps Markdown's plain-text simplicity and adds one axis,
with the author declaring what that axis means. Nothing comparable ships today;
the closest prior art renders existing Markdown into 3D rather than giving the
text a depth dimension of its own.

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

## Format at a glance

- A required `---` frontmatter block declares `3md:` (the version, and the file's
  magic marker), an optional `axis:`, an optional `title:`, and free metadata.
- `@plane z=... label="..."` directives start planes; the Markdown between
  directives is the plane body.
- A plain Markdown file with a 3md header and no directives is a valid one-plane
  document.

See [SPEC.md](SPEC.md) for the full grammar and conformance rules.

## Development

This repo uses the CorvidLabs trust toolchain. The single gate is:

```bash
fledge lanes run verify
```

which runs format, lint, build, and test. See [AGENTS.md](AGENTS.md) for the
standing rules every contributor and agent follows.

## Status

Version 0.1, experimental. The grammar may still change before 1.0.
