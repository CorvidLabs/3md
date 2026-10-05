# @corvidlabs/threemd

The **3md** library: Markdown with a Z axis. A `.3md`
file is ordinary Markdown extended along one free axis, so you can stack content
into **planes** and tell the reader what the depth means (time for a planner,
frames for an animation, layers for annotations, space for a scene).

Prepared 2.0.0 includes parsing/serialization, portable uncompressed binary
storage, self-contained composition, optional stable identities, immutable
revision-checked snapshots, transactional typed patches and diagnostics.
Swift, TypeScript and Rust share canonical wire fixtures and a public-API
writer-reader matrix. This is finite behavioral evidence, not exhaustive proof
for arbitrary inputs or every runtime.

## Install

```bash
bun add @corvidlabs/threemd
```

The current repository publication workflow targets public npm. Version 2.0.0
is prepared metadata; it is not claimed to be published yet. Older GitHub
Packages scope configuration must be changed when adopting a public npm release.

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

## Prepared 2.0.0 APIs

`DocumentStorageCodec` and `DocumentCompositionCodec` provide bounded canonical
text and general uncompressed containers. `DocumentIdentity`,
`DocumentSnapshot`, `DocumentCompositionSnapshot`, `DocumentEditor` and
`DocumentDiagnostics` provide explicit adoption and immutable atomic editing.
Exact canonical revisions are edit preconditions, not authentication.

The library has no runtime package dependency and performs no file or network
I/O. Hosts own input byte limits, side effects and permissions. Operations are
synchronous and check an optional AbortSignal cooperatively; callbacks on the
same event loop cannot interrupt a synchronous call. LZFSE returns an explicit
unsupported-backend error in this port. Use uncompressed storage for interchange.

Frozen text grammar 1.0, general binary container version 1 and profile
`3md-composition-1` retain their own versions. The element/viewer remains a text
UI; it does not expose these new library operations. See the repository's
[release guide](https://github.com/CorvidLabs/3md/blob/main/docs/RELEASE-2.0.0.md)
for the capability matrix, migration and publication checks.

## License

MIT
