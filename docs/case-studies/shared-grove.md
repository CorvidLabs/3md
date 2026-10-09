# Shared grove

[`shared-grove.3md`](../../Examples/Extensions/shared-grove.3md) embeds one named document and points at it. The library does no filesystem or network I/O to follow that name.

Version and library limits that apply to every study are in the [index](README.md).

## What the document is

The root is a normal document: version `0.1`, axis `layer`, profile `3md-composition-1`. Its only plane is `z=0`, label Composition. The plane body is a JSON object, schema `3md-composition-1`, root id `grove`.

Two entries live in that object.

- `canopy` has an empty reference list. Its `source` string is the full text of [`canopy.3md`](../../Examples/Extensions/canopy.3md), the same bytes as that file. Axis `space`, title Reusable canopy, material `mint`, planes `top` (`z=0`) and `bottom` (`z=1`).
- `grove` has one reference. `targetID` is `canopy`. The attributes are `{"binding": "A"}`. Its source is a second document, also grammar `1.0` and axis `space`, title Shared grove, metadata `semantics` set to `application-defined character bindings`. The ground plane says the letter A stands for the canopy and that the plane places it three times. The picture is:

```
A.A
.A.
```

The canopy definition appears once. The grove entry references that definition. The binding `A` is opaque. The examples note says the root body repeats `A`, and that reading those characters as model placements is the consuming application's job.

All definitions are self-contained. The file names no path and no URL.

[`gdscript/examples/grove/scene.3md`](../../gdscript/examples/grove/scene.3md) is a separate sample. It keeps the lantern in another file and names it from a `3md-files` ledger. Shared grove already holds the canopy text.

## What you can open

The extension table in [`Examples/README.md`](../../Examples/README.md) and the [structured manifest](../../conformance/structured/manifest.json) name these files. All of them are under [`Examples/Extensions/`](../../Examples/Extensions).

| File | Container |
| --- | --- |
| [`shared-grove.3md`](../../Examples/Extensions/shared-grove.3md) | Readable composition. |
| [`shared-grove.3mdb`](../../Examples/Extensions/shared-grove.3mdb) | Envelope version 1, payload kind 1, compression 0. The profile text sits after the 40-byte header. |
| [`shared-grove.structured.3mdb`](../../Examples/Extensions/shared-grove.structured.3mdb) | Envelope version 1, payload kind 2, compression 0. The structured manifest marks it as the profile envelope. The decoded profile document has one plane. |
| [`shared-grove.lzfse.3mdb`](../../Examples/Extensions/shared-grove.lzfse.3mdb) | Envelope version 1, payload kind 1, compression 1. Apple LZFSE fixture. |
| [`canopy.3md`](../../Examples/Extensions/canopy.3md) | The document stored in the `canopy` entry. |

[`manifest.json`](../../Examples/Extensions/manifest.json) records container version 1, profile `3md-composition-1`, and a SHA-256 for each of the six Swift-generated files (the two readable documents, the two uncompressed kind 1 files, and the two LZFSE files). Those hashes document fixture integrity. They do not authenticate an author. The kind 2 files are the structured anchors. [`conformance/structured/README.md`](../../conformance/structured/README.md) lists them beside the kind 1 and LZFSE files.

The [composition profile](../../SPEC.md#12-self-contained-document-composition) is the format rule. [Linked file composition](../FILE-COMPOSITION.md) is the other mechanism, the `3md-files` ledger. Shared grove does not use it.

## What the libraries do

Swift, TypeScript, and Rust decode the profile to a library of named documents. The canopy entry is one definition. The grove entry is the root. Its single reference resolves to `canopy` inside that library. Documents keep their own axes. Attributes have no built-in voxel or layout meaning.

The same profile can be saved as readable text, as deprecated kind 1 (`encodeTextContainer`, for a 2.0 reader), or as kind 2 (`.binary`). `shared-grove.structured.3mdb` is that kind 2 profile envelope. The hosted verify lane checks Swift, TypeScript, and Rust across nine writer/reader pairs, including composition references.

GDScript can build and decode a composition from values in memory. Composition editing there implements `replaceEntry` only: the replacement must keep the definition id. `ThreeMDFiles.load_linked` is the other Godot entry point. It reads paths the game already chose when a document carries a `3md-files` ledger. Shared grove has no such ledger.

## What they do not do

The library does no filesystem or network I/O. It does not open `canopy.3md` while decoding the grove. The canopy source is already inside the entry. It does not flatten the three `A` characters into copies of the canopy planes. It does not assign a scene position to the binding `A`.

Gallery cards do not expand composition references. The viewer page opens this profile and shows the root document, and the inside control switches to the other entry. It decodes the uncompressed binaries and refuses the LZFSE fixture. The element bundle stays text-only.

TypeScript and Rust report `compressionUnavailable(lzfse)` for the LZFSE fixture. GDScript returns `compressionUnavailable` when the compression byte is 1. Swift on Apple is the backend that reads and writes that fixture. Kind 1 is deprecated for new files. Readers still open the uncompressed kind 1 file.

Parser, storage, composition, and editing scripts do not open files. The addon does not spawn gameplay nodes for the `A` marks.
