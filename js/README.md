# @corvidlabs/threemd

Parser and serializer for the **3md** format: Markdown with a Z axis. A `.3md`
file is ordinary Markdown extended along one free axis, so you can stack content
into **planes** and tell the reader what the depth means (time for a planner,
frames for an animation, layers for annotations, space for a scene).

This package is a faithful TypeScript port of the Swift reference parser
(`ThreeMD`). The two implementations are pinned to identical behavior by a shared
conformance suite, so parsing the same document in either language yields the
same result.

## Install

```bash
bun add @corvidlabs/threemd
```

## Usage

```ts
import { danglingLinks, linkGraph, parse, serialize } from "@corvidlabs/threemd";

const source = `---
3md: 0.1
axis: time
title: My Week
---
@plane z=0 label="Monday"
# Monday
- [ ] Standup

@plane z=1 label="Tuesday"
# Tuesday
`;

const document = parse(source);
console.log(document.axis);            // "time"
console.log(document.planes.length);   // 2
console.log(danglingLinks(document));  // unresolved [[z=N]] references
console.log(linkGraph(document));      // compact source -> target edge list

// Round trips back to text:
const text = serialize(document);
```

`parse` throws a `ParseError` on malformed input; its `code` property names the
canonical case (`missingFrontmatter`, `invalidFrontmatter`, `missingVersion`,
`missingPlanePosition`, `invalidPlaneDirective`, or `duplicatePlane`).

## License

MIT
