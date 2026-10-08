# @corvidlabs/threemd

The **3md** library: Markdown with a Z axis. A `.3md`
file is ordinary Markdown extended along one free axis, so you can stack content
into **planes** and tell the reader what the depth means (time for a planner,
frames for an animation, layers for annotations, space for a scene).

ThreeMD 2.1 includes parsing/serialization, portable storage, self-contained
composition, linked file composition, optional stable identities, immutable
revision-checked snapshots, transactional typed patches and diagnostics.
`.binary` writes the binary save, payload kind 2. The text file stays the
`.3md`. Kind 1 is deprecated. `encodeTextContainer` still writes it for a 2.0
reader. There is no fixed size stop. A document is parsed and saved when the
process can hold it. A caller can still pass a lower positive limit. Swift,
TypeScript and Rust share canonical wire fixtures and a
public-API writer-reader matrix. This is finite behavioral evidence, not
exhaustive proof for arbitrary inputs or every runtime.

## Install

```bash
bun add @corvidlabs/threemd
```

The package version on this branch is 2.1.0. Public npm still serves 2.0.0
until the GitHub release publishes it. Older GitHub Packages scope
configuration must be changed when adopting a public npm release.

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

## 2.0.0 APIs

`DocumentStorageCodec` and `DocumentCompositionCodec` provide bounded canonical
text and general uncompressed containers. `DocumentIdentity`,
`DocumentSnapshot`, `DocumentCompositionSnapshot`, `DocumentEditor` and
`DocumentDiagnostics` provide explicit adoption and immutable atomic editing.
Exact canonical revisions are edit preconditions, not authentication.

`DocumentFileComposition.ledger`, `resolvePath` and `resolve(rootPath, sources)`
read an optional `3md-files` glyph ledger and resolve host-supplied
`Uint8Array` file bytes recursively into a self-contained composition that
`DocumentCompositionCodec` can bundle. Missing files, invalid paths or ledgers,
cycles and limits throw `DocumentFileCompositionError` without partial results.
See the repository's
[linked file contract](https://github.com/CorvidLabs/3md/blob/main/docs/FILE-COMPOSITION.md).

The library has no runtime package dependency and performs no file or network
I/O. Hosts own input byte limits, side effects and permissions. Operations are
synchronous and check an optional AbortSignal cooperatively; callbacks on the
same event loop cannot interrupt a synchronous call. LZFSE returns an explicit
unsupported-backend error in this port. Use uncompressed storage for interchange.

Frozen text grammar 1.0, general binary container version 1 and profile
`3md-composition-1` retain their own versions. On this branch `.binary` writes
payload kind 2 and `encodeTextContainer` writes payload kind 1. Header-only
inspection is `DocumentStorageCodec.containerInfo`. LZFSE stays unavailable in
this port. The element and viewer remain a text UI. See the
[2.1 preparation notes](../docs/RELEASE-2.1.0.md). The published
[2.0.0 release guide](https://github.com/CorvidLabs/3md/blob/main/docs/RELEASE-2.0.0.md)
still describes the packages the registries serve today.

## License

MIT
