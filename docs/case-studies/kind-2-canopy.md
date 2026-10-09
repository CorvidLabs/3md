# Kind 2 canopy

[`canopy.3md`](../../Examples/Extensions/canopy.3md) and [`canopy.structured.3mdb`](../../Examples/Extensions/canopy.structured.3mdb) are the same document in two containers. One is the text file. The other is payload kind 2.

Version and library limits that apply to every study are in the [index](README.md).

## What the document is

The text file is grammar `1.0`, axis `space`, title Reusable canopy, material `mint`. The preamble says a dot is open, a hash is a solid tile, and another document can place this piece by name. Two planes:

- `z=0`, label `top`
- `z=1`, label `bottom`

Each plane is a short Markdown picture of `.` and `#`. [Shared grove](shared-grove.md) embeds this exact file once and references it.

The kind 2 file is the version 1 binary envelope. The first eight bytes are `3mdbin\r\n`. The version field is 1. The payload-kind byte is 2. The compression byte is 0. The header is 40 bytes, then the structured payload. Kind 2 stores each frame as fields: the number, the name, and the body. It does not write the `@plane` line again. The [structured manifest](../../conformance/structured/manifest.json) lists `canopy.3md` as the source, `canopy.structured.3mdb` as the kind 2 file, two planes, and `compositionEnvelope` false.

Storage has no fixed size stop. A caller can pass a lower positive limit. This canopy is only the small example.

## What you can open

All four files are in [`Examples/Extensions/`](../../Examples/Extensions).

| File | Container |
| --- | --- |
| [`canopy.3md`](../../Examples/Extensions/canopy.3md) | Text you edit. |
| [`canopy.structured.3mdb`](../../Examples/Extensions/canopy.structured.3mdb) | Kind 2, compression 0. The structured payload of that document. |
| [`canopy.3mdb`](../../Examples/Extensions/canopy.3mdb) | Kind 1, compression 0. The text copied after the same 40-byte header. The extension table calls this the portable binary. Kind 1 is deprecated for new files. |
| [`canopy.lzfse.3mdb`](../../Examples/Extensions/canopy.lzfse.3mdb) | Kind 1, compression 1. The Apple LZFSE Swift fixture. |

The six-file [extension manifest](../../Examples/Extensions/manifest.json) covers the readable file, the kind 1 file, and the LZFSE file for canopy and for shared grove. Swift's public APIs generated those six and decoded them back to equal documents. The kind 2 names come from [`conformance/structured/README.md`](../../conformance/structured/README.md). That note keeps every older `.3mdb` byte-unchanged and puts the kind 2 file beside it.

The layout is [SPEC.md section 11](../../SPEC.md#11-general-document-storage). Since specification 1.2, `.binary` writes kind 2. `encodeTextContainer` still writes kind 1 for a reader on ThreeMD 2.0. A 2.0 reader stops on kind 2 with `unsupportedPayloadKind(2)`.

## What the libraries do

Swift, TypeScript, and Rust read and write kind 2. The structured fixture rules require those three ports to encode the decoded canopy document to `canopy.structured.3mdb` and to decode that file back to the same document: axis `space`, material `mint`, two planes. The hosted verify lane is those three libraries, nine writer/reader pairs. Uncompressed binary is part of that lane. LZFSE stays out of that lane.

GDScript `ThreeMDStorage.encode_binary` writes kind 2 (kind byte 2). `encode_text_container` writes kind 1 (kind byte 1). The addon reads both. The showcase in [`gdscript/examples/showcase.gd`](../../gdscript/examples/showcase.gd) checks those kind bytes on a different document, the linked grove scene.

Swift on Apple reads and writes LZFSE. `canopy.lzfse.3mdb` is that fixture: kind 1 with compression 1, generated with the other Swift extension files. SPEC 11.3.10 also allows LZFSE on a kind 2 payload. This committed fixture is the kind 1 file.

## What they do not do

Gallery cards stay on text. The viewer page decodes uncompressed `canopy.3mdb` and `canopy.structured.3mdb` and shows the text in the element. It does not decode `canopy.lzfse.3mdb`. Apple LZFSE stays unavailable. The element bundle stays text-only. CLI `convert` and `inspect` stay text-only.

TypeScript and Rust report `compressionUnavailable(lzfse)` for LZFSE, on decode and on encode. GDScript returns `compressionUnavailable` when the compression byte is 1. Those three libraries refuse `canopy.lzfse.3mdb`.

Binary storage does not interpret the axis, the Markdown, the `#` tiles, or the `mint` metadata. The library does not place the canopy into a scene. Parser, storage, composition, and editing scripts do not open the file. `ThreeMDFiles` reads a path the game already chose.

Sculpt.3md keeps its own compact `.3mdb`. That compact file is not the upstream binary standard. The upstream standard in this study is the `3mdbin` envelope of `canopy.structured.3mdb`.
