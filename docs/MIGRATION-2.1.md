# Migrating to ThreeMD 2.1

Status: preparation on branch `leif/structured-binary-2.1` (pull request 72).
Package manifests on that branch read 2.1.0. The `v2.1.0` tag is not cut, and
npm and crates.io still serve 2.0.0. These notes describe the library behavior
already on the branch. They are not a release announcement.

The package number is not the document version. Keep `3md: 1.0` (or an older
accepted string) in frontmatter. The parser stays version-lenient. Text grammar
1.0, container version 1 and profile `3md-composition-1` do not change.

## What changes

`DocumentStorageFormat.binary` now writes the binary save, payload kind 2:
the document's frames as fields inside the unchanged version 1 container
(magic `3mdbin\r\n`, 40-byte header). The text file stays the `.3md` you edit.
Kind 2 reads the fields directly. The same `.binary` call in ThreeMD 2.0 wrote
payload kind 1.

Kind 1 is deprecated. It is the text file copied after the 40-byte header, not
the field save. Readers still open old kind 1 files. Writers whose files a 2.0
reader must open should call `encodeTextContainer`. That function is the 2.0
binary writer, including its validation and error order.

A ThreeMD 2.0 reader stops on a new `.binary` file with
`unsupportedPayloadKind(2)` before it checks the checksum. Present that error
as "this file needs a newer ThreeMD". Rust composition decode wraps it as
`DocumentCompositionError::Storage(UnsupportedPayloadKind(2))`.

Old kind-1 `.3mdb` files still decode. `isBinary` is still the magic check.
`encode` and `decode` keep their signatures. Default storage limits are the
largest integer the language can use, so a 1 GB or 5 GB document is parsed and
saved when the process can hold it. A caller can still pass a lower positive
limit. Zero and negative limits are `invalidLimits`. Composition profile
ceilings and edit budgets stay as they were. Composition text stays
the readable `3md-composition-1` profile. A `.binary` composition bundle is
that profile stored as kind 2. Kind 3 stays reserved and is refused with
`unsupportedPayloadKind(3)`.

Two `validate` corrections land with the libraries:

- Rust spells canonical numbers with the shortest round-trip digits. ThreeMD
  2.0 rejected 92 powers of two whose spelling did not round-trip. Those values
  now validate, and their canonical text bytes change. Swift and TypeScript
  already used the short spelling.
- Swift trims with the frozen whitespace set W from SPEC 11.3.6: the 19 scalars
  U+0009, U+0020, U+00A0, U+1680, U+2000 through U+200B, U+202F, U+205F and
  U+3000. U+0085, U+000B, U+000C, U+180E, U+2028 and U+FEFF are not in W. On
  Darwin this set matches `CharacterSet.whitespaces`. Other Foundation builds
  can disagree, including at U+200B. TypeScript and Rust already used W.

TypeScript stores metadata and attribute keys in raw UTF-8 byte order, which
is Unicode code point order. JavaScript still enumerates integer-like keys
first, whatever the insertion order. Compare decoded documents by value. Do
not compare them by key enumeration order.

The `threemd` CLI on this branch is still the text tool: `validate`, `info`,
`links`, `check-links` and `html`. It does not decode `.3mdb`, and it has no
`convert` or `inspect` yet. Passing a kind-2 file to today's CLI parses it as
text and fails as text.

## Snippets

```swift
// 2.0 and 2.1: same call. In 2.1 the result is payload kind 2.
let bytes = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
// Deprecated. For a ThreeMD 2.0 reader, write payload kind 1 instead.
let legacy = try DocumentStorageCodec.encodeTextContainer(document)
// Which kind is this file?
if let info = try DocumentStorageCodec.containerInfo(bytes),
    !DocumentStorageCodec.supportedPayloadKinds.contains(info.payloadKind) {
    // This file needs a newer ThreeMD.
}
// A binary composition bundle is the profile envelope stored as kind 2.
let bundle = try DocumentStorageCodec.encode(
    DocumentCompositionCodec.document(for: composition), format: .binary(compression: .none))
let reopened = try DocumentCompositionCodec.decode(bundle)
```

```ts
const bytes = DocumentStorageCodec.encode(document, DocumentStorageFormat.binary()); // payload kind 2
const legacy = DocumentStorageCodec.encodeTextContainer(document); // deprecated payload kind 1
const kind = DocumentStorageCodec.containerInfo(bytes)?.payloadKind; // 2
```

```rust
let bytes = storage::encode(&document, DocumentStorageFormat::Binary(DocumentCompression::None), &limits, &options)?;
// Deprecated. For a ThreeMD 2.0 reader, write payload kind 1 instead.
let legacy = storage::encode_text_container(&document, DocumentCompression::None, &limits, &options)?;
let kind = storage::container_info(&bytes)?.map(|info| info.payload_kind); // Some(2)
```

## Converting a file

Decode a kind-1 `.3mdb` and encode it with `.binary`. The `Document` is the
same, and the new file is kind 2. Encoding that document with
`encodeTextContainer` reproduces the 2.0 kind-1 bytes.

The other direction is the same pair of calls: decode kind 2, then
`encodeTextContainer` for a 2.0 reader, or `encode` with `.text` for canonical
text. There is no CLI command for this yet.

## What you can leave alone

Text-only hosts, the `<three-md>` element and the VS Code extension do not
need a storage change. The element stays a text renderer, and the extension
stays syntax highlighting. Optional LZFSE is still the Apple Compression
backend in Swift, and TypeScript and Rust still return an explicit
unsupported-backend error. For a file all three libraries must read, use
the text file or uncompressed binary. Old kind-1 files still open. Kind 3
does not.
