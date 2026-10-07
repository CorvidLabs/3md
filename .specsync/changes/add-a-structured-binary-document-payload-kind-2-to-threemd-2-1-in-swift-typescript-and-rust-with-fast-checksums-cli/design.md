---
change: add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli
artifact: design
---

# Design

The normative format is SPEC.md 1.2, which WP0 brings into the repository:

- [11.1 Version 1 binary envelope](/SPEC.md#111-version-1-binary-envelope) (payload kind table and the
  validation order D1 to D14)
- [11.2 Validation and resource policy](/SPEC.md#112-validation-and-resource-policy)
- [11.3 Structured document payload (kind 2)](/SPEC.md#113-structured-document-payload-kind-2)
- [11.4 Rationale](/SPEC.md#114-rationale-informative) and
  [11.5 Reserved extension points](/SPEC.md#115-reserved-extension-points)
- [12 Self-contained document composition](/SPEC.md#12-self-contained-document-composition) (binary
  envelopes and bundles)

This file summarizes that design and then carries the full public API for Swift, TypeScript and Rust, the error
mapping, `containerInfo`, `encodeTextContainer` and the CLI surface. The API text comes from the specification
package's `api.md`; this archive is where it lives in the repository. Section numbers such as 11.3.9 refer to SPEC.md.
`plan.md` orders the work and `testing.md` maps requirements to tests.

## Summary

Payload kind 2 stores a `Document` as one sequence of length-prefixed records in document order, inside the unchanged
version 1 container. A reader consumes it with one forward cursor: there are no offsets, no index, no string pool and
no padding. Decoding never builds or parses text, except for the rare directive check of Phase Q. Validity is defined
so that kind 2 accepts exactly the documents that canonical text accepts under the same limits, and decodes to the
same value, so a file can always move between text and binary when the target fits `maximumEncodedBytes`.

`DocumentStorageFormat.binary(compression:)` writes kind 2. The 2.0 kind-1 bytes (canonical text behind the header)
move to a new writer, `encodeTextContainer`, for consumers that still run ThreeMD 2.0. Compositions keep the readable
`3md-composition-1` profile, whose envelope may be stored as kind 2 like any other document. Payload kind 3 (a
structured composition) is reserved.

## Container and payload kinds

The 40-byte header, magic `3mdbin\r\n`, little-endian fields and CRC-32/ISO-HDLC are those of 2.0. Header byte 10 is
the payload kind, and the decoded length at offset 28 is the exact uncompressed payload byte count.

| Kind | Payload | Since | Accepted by |
|---|---|---|---|
| 1 | Canonical UTF-8 3md text (readers keep tolerating non-canonical text, as in 2.0) | SPEC 1.1, ThreeMD 2.0 | storage decode; composition decode as a profile envelope |
| 2 | Structured document (11.3) | SPEC 1.2, ThreeMD 2.1 | storage decode; composition decode as a profile envelope |
| 3 | Reserved for a structured composition (11.5) | not defined | nothing: `unsupportedPayloadKind(3)` |
| 0, 4 to 255 | Reserved | not defined | nothing: `unsupportedPayloadKind(k)` |

A decoder checks a binary input in this order; the first failing check decides the error:

| Step | Check | Error |
|---|---|---|
| D1 | Invalid limits; cancellation on entry, in each port's 2.0 order | `invalidLimits` |
| D2 | Input longer than `maximumEncodedBytes` | `oversizedInput` |
| D3 | No 8-byte magic: decode as text (11.2), unchanged | none |
| D4 | Fewer than 40 bytes | `invalidContainer` |
| D5 | Container version not 1 | `unsupportedVersion(v)` |
| D6 | Payload kind not 1 or 2 | `unsupportedPayloadKind(k)` |
| D7 | Compression not 0 or 1 | `unsupportedCompression(c)` |
| D8 | Flags not 0 | `unsupportedFlags(f)` |
| D9 | Reserved field not 0 | `nonzeroReserved` |
| D10 | Decoded length over the kind's bound: `Dmax` for kind 1; `min(Emax − 40, 2 × Dmax)` for kind 2 | `oversizedOutput` |
| D11 | Zero lengths, encoded length not input length − 40, or uncompressed lengths that differ | `lengthMismatch` |
| D12 | CRC mismatch | `checksumMismatch` |
| D13 | LZFSE: no backend, a stream that does not end exactly once or does not produce the declared length, a stream the backend cannot process | `compressionUnavailable(lzfse)`, `lengthMismatch`, `compressionFailed` |
| D14 | Kind 1: bounded text decode (11.2). Kind 2: structured decode (11.3.8) | as stated there |

D2 to D13 are the 2.0 sequence with D6 widened and D10 chosen by kind, so a 2.0 reader stops at D6 with
`unsupportedPayloadKind(2)` before it computes the CRC. The kind-2 bound in D10 never rejects a valid file: every part
of the payload is at most twice the canonical text it stands for, so a payload that passes L4 (`T ≤ Dmax`) has
`n < 2 × T ≤ 2 × Dmax`. Because the bound also applies to LZFSE input, a lowered `maximumDecodedBytes` bounds
decompression, and the uncompressed container must fit `Emax` whether or not it is compressed.

## Payload encoding

Terms: `P[0 ..< n]` is the uncompressed payload; the cursor only moves forward; *remaining* is `n − cursor`, measured
after every byte of the field read so far, including its own length prefix. R, Dmax, Lmax, Pmax and Emax are
`maximumRecordBytes`, `maximumDecodedBytes`, `maximumLines`, `maximumPlanes` and `maximumEncodedBytes`.

**Primitives (11.3.3).**

| Primitive | Encoding | Reader rules |
|---|---|---|
| u8 | one byte | none left: `lengthMismatch` |
| Var | unsigned LEB128, 1 to 4 bytes, 0 to 2^28 − 1, minimal | V1 none left: `lengthMismatch`; V2 a 4th byte with `0x80`: `invalidContainer`; V3 a final `0x00` byte in a multi-byte Var: `invalidContainer` |
| Count(min) | a Var `k` | `k > floor(remaining ÷ min)`: `lengthMismatch`; divide, never multiply; reserve nothing before the check |
| Str(class, limit) | Var length `m`, then `m` UTF-8 bytes stored verbatim | Str1 `m > remaining`: `lengthMismatch`; Str2 `m > limit`: `oversizedRecord`; Str3 ill-formed UTF-8 (each Str on its own): `invalidUTF8`; Str4 a scalar holding LF or CR, or a segment failing 11.3.6.4: `invalidDocument` |
| Number(form) | form 0 absent (x and y only); form 1 zigzag Var integer in `−2^27 ..< 2^27`; form 2 binary32 widened exactly; form 3 binary64 | form 0 for z: `invalidContainer`; truncated: `lengthMismatch`; non-finite: `invalidDocument`; a value that fits an earlier form, or −0: `invalidContainer` |
| Flag bytes | defined bits only | any undefined bit: `invalidContainer` |

A writer normalizes −0 to +0 and picks the first form whose condition holds (TypeScript `Number.isInteger` and
`Math.fround`; Swift `rounded(.towardZero)` and `Double(Float(v))`; Rust `trunc()` and `f64::from(v as f32)`).

**DocumentRecord (11.3.5.1).** The payload is exactly one record:

| Step | Field | Encoding | Rule |
|---|---|---|---|
| S1 | documentFlags | u8 | bit 0 title present, bit 1 preamble present; bits 2 to 7: `invalidContainer` |
| S2 | version | Str(scalar, R) | empty: `invalidDocument` |
| S3 | axis | Str(scalar, R) | rule R2 |
| S4 | title | Str(scalar, R), if bit 0 | none |
| S5 | metadataCount M | Count(2) | none |
| S6 | M × (key, value) | Str(scalar, R) each | per entry: key Str rules, key byte order (`invalidContainer`), R3 on the key, value Str rules |
| S6b | | | after the last entry: key equivalence (`invalidDocument`) |
| S7 | preamble | Str(segment, R − 1), if bit 1 | segment rules, role preamble |
| S8 | planeCount P | Count(4) | `P > Pmax`: `tooManyPlanes`; a preamble with `P = 0`: `invalidDocument` |
| S9 | P × PlaneRecord | | cancellation check before each plane |
| S10 | end | | remaining ≠ 0: `lengthMismatch` |

**PlaneRecord (11.3.5.2).**

| Step | Field | Encoding | Rule |
|---|---|---|---|
| P1 | planeFlags | u8 | bits 0 to 1 z form (1 to 3); bits 2 to 3 x form; bits 4 to 5 y form; bit 6 label present; bit 7 or z form 0: `invalidContainer` |
| P2 to P4 | z, x, y | Number(form) | x and y only when their form is not 0 |
| P5 | label | Str(scalar, R), if bit 6 | none |
| P6 | attributeCount A | Count(3) | none |
| P7 | A × (key, value) | Str(scalar, R) each | per entry: key Str rules, key byte order (`invalidContainer`), value Str rules |
| P7a | | | after the last entry: key equivalence (`invalidDocument`) |
| P7b | | | no key holds `"` or `'`: R9 on each key; otherwise the plane is marked for Phase Q |
| P8 | body | Str(segment, R) | segment rules, role body; *final* only for the last plane |

The smallest document is 6 bytes (`00 01 31 00 00 00`) and the smallest plane 4 bytes (`01 00 00 00`).

## Representability (11.3.6)

These rules describe exactly the documents whose 2.0 canonical text parses back to an equal document, which is the set
the 2.1 `validate` accepts once limits are set aside. Every violation is `invalidDocument`, except key order
(`invalidContainer`).

- **W** is the frozen whitespace set of 19 scalars: U+0009, U+0020, U+00A0, U+1680, U+2000 to U+200B, U+202F, U+205F
  and U+3000. Every port trims and tests blank lines with W, never with platform tables.
- **Key order and equivalence.** Keys in a map are in strictly increasing raw UTF-8 byte order (equal to code point
  order, not UTF-16 order). After the last entry, keys with equal NFC forms are rejected. All-ASCII maps need no NFC
  work; a non-ASCII key can normalize to ASCII (U+212A becomes `K`).
- **R2, axis.** Equals the port's own 2.0 normalization of itself (trim W, lowercase), compared byte for byte.
- **R3, metadata key.** No `:`; first and last scalars not in W; first byte not `#`; not `3md`, `axis` or `title`
  under ASCII case folding. The empty key is valid.
- **R9, attribute key (planes without quote characters).** Not empty; no space, tab or `=`; first and last scalars
  not in W; equal to its own 2.0 lowercase mapping; not `z`, `x`, `y` or `label`.
- **Values** need only the scalar rule (no LF or CR).
- **R7** no two planes share a z (L0). **R8** a preamble needs at least one plane (S8).
- **Segments (preamble and bodies), G1 to G6.** An empty preamble is invalid (G1); a trailing CR (G2) or any CRLF
  (G3) is invalid; a blank first or last line is invalid (G4); outside a fence, a line equal to `@plane` or starting
  with `@plane` and a space or tab is invalid, and a fence closes only with three copies of the character that opened
  it (G5); an open fence at the end of the preamble or a non-final body is invalid (G6).
- **Phase Q.** For each marked plane, build its canonical directive line exactly as the 2.0 writer does (attributes
  in the port's 2.0 NFC writer order) and parse it with the port's 2.0 parser, for example inside
  `---\n3md: "1"\naxis: "a"\n---\n\n` + line + `\n`. The plane is representable exactly when the parse returns the
  stored z, x, y, label and byte-equal attributes.

## Canonical text metrics (11.3.7)

The reader computes the canonical text length T and physical line count Lines without building the text. With
`Q(s) = len(s) + 2 + esc(s)` (esc counts `"` and `\`) and `Nn(v)` the byte length of the canonical number spelling:

- `DirLen(p) = 9 + Nn(z) + [7 + Q(label)] + [3 + Nn(x)] + [3 + Nn(y)] + Σ (2 + len(key) + Q(value))`
- `T = 4 + (6 + Q(version)) + (7 + Q(axis)) + [8 + Q(title)] + Σ metadata (3 + len(key) + Q(value)) + 4 +
  [2 + len(preamble)] + Σ planes (2 + DirLen(p) + [len(body) + 1 if the body is not empty])`
- `Lines = 5 + [1 if title] + M + [2 + LF(preamble)] + Σ planes (2 + [1 + LF(body) if the body is not empty])`

A form-2 or form-3 number needs formatting only when the bound `1 ≤ Nn ≤ 24` cannot decide a check.

## Decoding (11.3.8)

The decoder runs Phase S, then Phase L, then Phase Q, and reports the first failing check in that order.

- **Phase S** runs S1 to S10 and P1 to P8, enforces the per-string limits and Pmax, and accumulates lengths, escape
  counts, LF counts and the non-integer numbers.
- **Phase L:** L0 duplicate z (`invalidDocument`); L1 `R < 3` (`oversizedRecord`); L2 a frontmatter line over R
  (`oversizedRecord`); L3 a directive line over R (`oversizedRecord`); L4 `T > Dmax` (`oversizedOutput`); L5
  `Lines > Lmax` (`tooManyLines`).
- **Phase Q** runs for each marked plane, with a cancellation check before and after each parse.

Phase S work is linear and its allocation is a constant factor of `n`, which D10 bounds by `2 × Dmax`. Phase Q runs
only after L3 and L4 bound every directive by R and the whole text by Dmax. Implementations should not build result
maps before Phase L passes; a validate-then-materialize reader conforms. The result is Swift
`Document(version:axis:title:metadata:preamble:planes:)`, the TypeScript plain-object shape of the 2.0 bounded decoder,
or a Rust `Document` with `BTreeMap` maps.

## Writing (11.3.9)

| Step | Action | Error |
|---|---|---|
| W1 | Validate limits and check cancellation, in the port's 2.0 order | `invalidLimits` |
| W1b | `Emax < 40` | `oversizedInput` |
| W2 | Normalize as the port's 2.0 text writer does: −0 to +0; keys in raw UTF-8 byte order; TypeScript merges equivalent keys (first spelling, last value) after running the 2.0 `validateRecords` on the unmerged input and rejects lone surrogates; Rust rejects equivalent keys | as stated |
| W3 | Emit the fields into a buffer capped at `Emax − 40` payload bytes, checked before each append | `oversizedInput` |
| W4 | Self-check: run the reader's Phases S, L and Q over the emitted payload with the same routine decode uses (it may skip building values and re-validating UTF-8 the writer produced from native strings) | the reader's codes |
| W5 | Compression: LZFSE without a backend `compressionUnavailable(lzfse)`; an unknown identifier (TypeScript) `unsupportedCompression`; LZFSE output capped at `Emax − 40` | as stated |
| W6 | Write the header (version 1, kind 2, flags 0, reserved 0, lengths, CRC) and the payload; check cancellation | none |

W2 never rejects non-finite coordinates, duplicate z or unrepresentable fields; W3 emits them (±∞ as form 2, NaN as
form 3) and W4 rejects them. Accept or reject always equals the 2.1 `validate`, except that kind 2 requires the file to
fit `Emax` and never compares T with `Emax`; for an invalid document the error code follows the structured precedence
and can differ from `.text`. Determinism: exact fields and flags, minimal Vars, canonical number forms, keys in byte
order with their spelling kept, values and planes verbatim, no normalization; LZFSE bytes are outside byte identity.

## Limits, errors, cancellation and Unicode

**Limits (11.3.11).** `DocumentDecodeLimits` is unchanged:

| Limit | Text and kind 1 | Kind 2 |
|---|---|---|
| `maximumEncodedBytes` | input bytes | the input, and the uncompressed container (`40 + n ≤ Emax`); never compared with T |
| `maximumDecodedBytes` | decompressed text bytes | T (L4); also `n ≤ 2 × Dmax` at D10 |
| `maximumLines` | physical lines | Lines (L5) |
| `maximumPlanes` | planes | planeCount (S8, before L5) |
| `maximumRecordBytes` | each line, scalar, preamble and body | each scalar ≤ R, preamble ≤ R − 1, body ≤ R; frontmatter and directive lines ≤ R; R ≥ 3 |

A kind-2 file can be accepted under an `Emax` that its canonical text would exceed (80 empty planes: a small file with
`T = 1056` decodes under `Emax = 1000`); saving it as text under the same limits then fails with `oversizedInput`.

**Errors (11.3.12).** No code is added:

| Condition | Code |
|---|---|
| Truncated field; Var or Str past remaining; count framing; trailing bytes; container lengths | `lengthMismatch` |
| 4th Var byte with `0x80`; non-minimal Var; undefined flag bit; z form 0; non-canonical number form or −0; keys out of byte order or identical | `invalidContainer` |
| Ill-formed UTF-8 | `invalidUTF8` |
| A string over R or a preamble over R − 1; `R < 3`; a frontmatter or directive line over R | `oversizedRecord` |
| Kind-2 decoded length over `min(Emax − 40, 2 × Dmax)`; `T > Dmax` | `oversizedOutput` |
| `Lines > Lmax` | `tooManyLines` |
| `planeCount > Pmax` | `tooManyPlanes` |
| A file over Emax; a writer payload over `Emax − 40`; `Emax < 40` on write | `oversizedInput` |
| Non-finite coordinate, duplicate z, scalar line break, empty version, R2, R3, R9, segment rules, preamble without planes, Phase Q failure, equivalent keys, TypeScript lone surrogate | `invalidDocument(detail)` |
| Payload kind 0 or 3 to 255 | `unsupportedPayloadKind(k)` |
| Cancellation | Swift `CancellationError`, the TypeScript AbortSignal reason, Rust `Cancelled` |

**Cancellation (11.3.13).** Checked on entry, during the CRC at least every 65,536 bytes and after it, before each
plane during decoding and emission, within every hand-written byte scan and within UTF-8 validation of strings over
65,536 bytes at least every 65,536 bytes, before and after each Phase Q parse, and before returning. Long strings are
validated in chunks split at scalar boundaries, each chunk validated as a complete string; TypeScript uses one shared
fatal `TextDecoder` with non-streaming calls only. A cancelled or failed call returns no document and no bytes.

**Unicode (11.3.15).** Kind-2 bytes never depend on Unicode data: keys are in byte order and strings are verbatim.
Acceptance uses Unicode data where 2.0 text validation does (NFC equivalence, lowercase mappings, Phase Q). The ports
agree on every input whose strings hold only Unicode 13.0 assigned code points, on the pinned CI toolchains (Swift
6.3.3, Node 24, Bun 1.4.2, Rust 1.95 with `unicode-normalization` 0.1.25). The assigned set is committed as
`scripts/structured/unicode-13.0-assigned.json`. ThreeMD declares no runtime minimum; older runtimes are outside the
guarantee.

## Worked example

SPEC 11.3.17 example 1: a 144-byte canonical text with title `Week`, metadata `owner: "ops"`, a plane `z=0
label="Mon"` with body `# Standup`, and a plane `z=1.5 label="Tue" x=-2 kind="note"` with body `Ship it`. Its kind-2
file is 113 bytes with CRC-32 `0x8A5B3B70`:

```
offset  bytes                                            meaning
0       33 6d 64 62 69 6e 0d 0a 01 00 02 00 00 00 00 00  magic, version 1, kind 2, compression 0, flags 0
16      00 00 00 00 49 00 00 00 00 00 00 00              reserved 0, encoded length 73
28      49 00 00 00 00 00 00 00 70 3b 5b 8a              decoded length 73, CRC 0x8A5B3B70
40      01 03 31 2e 30 04 74 69 6d 65 04 57 65 65 6b     flags (title), "1.0", "time", "Week"
55      01 05 6f 77 6e 65 72 03 6f 70 73                 1 metadata entry: "owner" = "ops"
66      02                                               2 planes
67      41 00 03 4d 6f 6e 00 09 23 20 53 74 61 6e 64 75 70
                                                         z form 1, label; z 0; "Mon"; 0 attributes; "# Standup"
84      46 00 00 c0 3f 03 03 54 75 65 01 04 6b 69 6e 64 04 6e 6f 74 65 07 53 68 69 70 20 69 74
                                                         z form 2, x form 1, label; z 1.5; x -2; "Tue";
                                                         1 attribute "kind" = "note"; "Ship it"
```

A 2.0 reader stops at offset 10 with `unsupportedPayloadKind(2)`.

---

## Public API

### Principles

- **Additive.** No public enum gains a case and no existing signature changes. `DocumentStorageFormat`,
  `DocumentCompression`, `DocumentStorageError`, `DocumentDecodeLimits`, the composition types and their error enums
  stay exactly as they are, so exhaustive `switch` and `match` statements compiled against 2.0 keep compiling.
- **One behavior change.** `encode(_, format: .binary(compression:))` writes payload kind 2. The 2.0 kind-1 bytes
  move to `encodeTextContainer`.
- **No lazy or partial-access API.** The only inspection API reads the 40-byte header (`containerInfo`).
- **No payload kind 3.** Kind 3 is reserved (11.5). No constant names it, and every reader reports
  `unsupportedPayloadKind(3)`.
- **The usual rules hold.** Calls are synchronous, pure and bounded; they check cancellation and return no partial
  result; they do no file or network I/O. There is no new runtime dependency (Rust keeps
  `unicode-normalization = "=0.1.25"` only, and adds `#![forbid(unsafe_code)]`).
- **No new error codes** (11.3.12).

### Existing entry points in 2.1

| Entry point | 2.1 behavior |
|---|---|
| `DocumentStorageCodec.encode(doc, format: .binary(c), limits)` | Writes **payload kind 2** (11.3.9). Same parameters and error type. The accept or reject decision equals `.text` and the 2.1 `validate` (11.3.1), except that kind 2 requires the file (not the canonical text) to fit `maximumEncodedBytes`. For an invalid document the error code follows the structured precedence, which can differ from `.text`. |
| `DocumentStorageCodec.encode(doc, format: .text, limits)` | Unchanged. |
| `DocumentStorageCodec.decode(data, limits)` | Accepts text, kind 1 and **kind 2**. Kinds 0 and 3 to 255 report `unsupportedPayloadKind(k)`. |
| `DocumentStorageCodec.validate(doc, limits)` | Same signature and error type. Two bug fixes only (11.3.1): Rust spells the 92 affected powers of two correctly, so it now accepts them; Swift trims with the frozen whitespace set W instead of `CharacterSet.whitespaces`. TypeScript is unchanged. |
| `DocumentStorageCodec.isBinary(data)` | Unchanged (magic only). |
| `DocumentCompositionCodec.encode(c, limits, documentLimits)` | Unchanged: readable profile text. |
| `DocumentCompositionCodec.document(for:)` | Unchanged. Encoding its result with `.binary` now yields a kind-2 envelope. |
| `DocumentCompositionCodec.decode(data, limits, documentLimits)` | Accepts text and kind-1 and **kind-2** envelopes, through storage decode with the profile limits (12.2). Kind 3 reports `unsupportedPayloadKind(3)`. No code change is needed beyond storage decode. |
| `DocumentFileComposition.resolve(...)` | Accepts supplied children that are text or payload kind 1 or 2. A kind-3 child is refused with `unsupportedPayloadKind(3)`. No code change is needed beyond storage decode. |
| Rust `storage::canonical_number` / `swift_double` (crate-private) | Fixed to emit the shortest round-trip spelling (11.3.7); text output changes only for the 92 powers of two that did not round-trip in 2.0. |

### Swift (`Sources/ThreeMD`)

New public declarations:

```swift
// MARK: - DocumentStorage.swift

/// A payload kind in the version 1 general binary container (header byte 10).
///
/// A struct rather than an enum, so future kinds are additive and never break an exhaustive `switch`.
public struct DocumentPayloadKind: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    /// The header byte at offset 10.
    public let rawValue: UInt8

    /// Creates a kind from its header byte. Every value is representable, including reserved ones.
    /// - Parameter rawValue: The header byte.
    public init(rawValue: UInt8)

    /// Canonical UTF-8 3md text behind the binary header (ThreeMD 2.0, SPEC 11.1).
    public static let canonicalText: DocumentPayloadKind
    /// Structured document records (ThreeMD 2.1, SPEC 11.3).
    public static let structuredDocument: DocumentPayloadKind

    /// `canonicalText`, `structuredDocument`, or `reserved(N)`.
    public var description: String { get }
}

/// The raw fixed header fields of a binary container, reported without validating them, the payload or the checksum.
public struct DocumentContainerInfo: Hashable, Sendable {
    /// The independent container version; 1 for every payload kind in ThreeMD 2.1.
    public let containerVersion: UInt16
    /// The payload kind byte.
    public let payloadKind: DocumentPayloadKind
    /// The raw compression identifier; compare it with `DocumentCompression.rawValue`.
    public let compression: UInt8
    /// The raw feature flags.
    public let flags: UInt32
    /// The raw reserved field.
    public let reserved: UInt32
    /// The declared encoded payload byte count.
    public let encodedPayloadByteCount: UInt64
    /// The declared decoded (uncompressed) payload byte count.
    public let decodedPayloadByteCount: UInt64
    /// The declared CRC-32/ISO-HDLC value.
    public let checksum: UInt32
}

// MARK: - DocumentStorageCodec.swift

extension DocumentStorageCodec {
    /// The payload kinds this release decodes: `canonicalText` and `structuredDocument`.
    public static let supportedPayloadKinds: Set<DocumentPayloadKind>

    /// Reads the 40-byte header without validating it, the payload or the checksum.
    /// - Parameter data: Complete or partial input; at most the first 40 bytes are read.
    /// - Returns: `nil` when the input does not begin with the binary magic (`isBinary` is false).
    /// - Throws: `DocumentStorageError.invalidContainer` when the magic is present but fewer than 40 bytes exist.
    public static func containerInfo(_ data: Data) throws -> DocumentContainerInfo?

    /// Writes payload kind 1, canonical text behind the binary header, byte-identical to ThreeMD 2.0 `.binary`.
    ///
    /// Use this only for files that ThreeMD 2.0.x must read. `encode(_:format:limits:)` with `.binary` writes the
    /// structured payload, which is smaller and decodes several times faster.
    /// - Parameters:
    ///   - document: The document to store.
    ///   - compression: `.none`, or `.lzfse` where the Compression framework exists.
    ///   - limits: The storage policy, applied exactly as the 2.0 binary writer applied it.
    /// - Returns: The complete container.
    /// - Throws: `DocumentStorageError` exactly as the 2.0 binary writer did, or `CancellationError` where supported.
    public static func encodeTextContainer(
        _ document: Document,
        compression: DocumentCompression = .none,
        limits: DocumentDecodeLimits = .standard
    ) throws -> Data
}
```

Changed behavior and documentation:

- `encode(_:format:limits:)` with `.binary(compression:)` writes payload kind 2. Doc comment: "Produces canonical
  readable text, or the version 1 binary container with a structured document payload (payload kind 2). Use
  `encodeTextContainer(_:compression:limits:)` for files that ThreeMD 2.0 must read."
- `decode(_:limits:)` accepts payload kind 2. Doc comment adds: "Payload kinds 1 and 2 are accepted; other kinds
  throw `unsupportedPayloadKind`."
- `DocumentStorageFormat` doc comment: "Text remains the portable interchange format. `.binary` writes the structured
  document payload (SPEC 11.3)." Case `.binary(compression:)`: "The version 1 container with a structured document
  payload and the selected compression identifier."
- `DocumentStorageCodec` type comment: payload kind "1 = canonical UTF-8 3md, 2 = structured document".
- `DocumentStorageError` documentation and descriptions (text only, no new case):
  - `.invalidContainer`: comment "A recognized binary container has an invalid header or structured payload
    encoding."; description "The binary container or its structured payload encoding is invalid."
  - `.unsupportedPayloadKind(k)`: comment "The header declares a payload kind this operation does not accept.";
    description "Unsupported 3md binary payload kind \(k) for this operation."

Internal (not public):

- `DocumentStorageStructured.swift` (new): `StructuredReader` (Phases S, L and Q over `UnsafeRawBufferPointer` with
  `loadUnaligned`), `StructuredWriter`, the segment scan (`memchr` for LF), the metrics of 11.3.7.
- UTF-8 validity uses `String(decoding:as: UTF8.self)` followed by a byte comparison of the result's `utf8` with the
  input (`withUTF8` and `memcmp`), in chunks of at most 65,536 bytes for long strings (11.3.13). There is no
  hand-written validator. The writer's self-check skips UTF-8 validation of bytes it produced from Swift strings.
- Key order uses `utf8.lexicographicallyPrecedes`; key equivalence uses `Set<String>` insertion (11.3.6.1). Every
  byte-exact comparison (axis normalization, Phase Q results) compares `utf8`.
- `DocumentStorageChecksum`: slicing-by-8 tables over `UnsafeRawBufferPointer`, used by kinds 1 and 2. The 2.0
  decode copies `Data(data.dropFirst(40))` and `Data(data.prefix(36))` are removed. The internal entry
  `checksum(header:payload:)` keeps its signature for the existing tests.
- `ThreeMDWhitespace` (new, internal): the frozen set W of 11.3.6 and a scalar-wise trim. It replaces
  `trimmingCharacters(in: .whitespaces)` in `Parser.swift`, `Axis.swift`, `DocumentStorageValidation.swift` and
  `Serializer.swift`, so Swift text validation no longer depends on the platform's `CharacterSet.whitespaces` (on
  Darwin the two sets are equal; on non-Darwin Foundation builds they can differ at U+200B). `MarkdownRenderer.swift`
  is presentation and keeps its current calls.
- `DocumentStorageCompression`: the LZFSE transcoder is reused for kind 2 with the D10 bound as the decoded cap.

Concurrency: the new types are `Sendable`. Cancellation goes through the existing `DocumentStorageCancellation.check()`
(`CancellationError`; a no-op on runtimes without Swift concurrency).

### TypeScript (`js/src`)

Export surface: `js/src/index.ts` re-exports from `./storage.js`, adding two names to the existing list:

```ts
export {
  DocumentCompression, DocumentDecodeLimits, DocumentPayloadKind, DocumentStorageCodec, DocumentStorageError,
  DocumentStorageFormat, type DocumentContainerInfo, type DocumentStorageErrorCode,
} from "./storage.js";
```

Nothing else is exported. The new module `js/src/structured.ts` (reader, writer, metrics, segment rules, Phase Q) and
`js/src/checksum.ts` (slicing CRC shared by kinds 1 and 2) are internal.

New declarations (`js/src/storage.ts`):

```ts
/** Payload kinds in the version 1 general binary container. Plain constants, so new kinds are additive. */
export const DocumentPayloadKind: Readonly<{ canonicalText: 1; structuredDocument: 2 }>;
// Implemented as: /* @__PURE__ */ Object.freeze({ canonicalText: 1, structuredDocument: 2 } as const)
export type DocumentPayloadKind = number;

/** Raw header fields, reported without validation. Lengths are bigint because the header stores u64 values. */
export interface DocumentContainerInfo {
  readonly containerVersion: number;
  readonly payloadKind: number;
  readonly compression: number;
  readonly flags: number;
  readonly reserved: number;
  readonly encodedPayloadByteCount: bigint;
  readonly decodedPayloadByteCount: bigint;
  readonly checksum: number;
}

export class DocumentStorageCodec {
  // Existing members keep their signatures.
  // encode(document, DocumentStorageFormat.binary(c), limits, signal) now writes payload kind 2.
  // decode(data, limits, signal) now accepts payload kind 2.

  /** The payload kinds this release decodes, [1, 2]. Frozen. */
  public static readonly supportedPayloadKinds: readonly number[]; // /* @__PURE__ */ Object.freeze([1, 2])

  /**
   * Header-only inspection; at most the first 40 bytes are read.
   * @returns null when the input does not begin with the binary magic.
   * @throws DocumentStorageError("invalidContainer") when the magic is present but fewer than 40 bytes exist.
   */
  public static containerInfo(data: Uint8Array): DocumentContainerInfo | null;

  /**
   * Payload kind 1, byte-identical to the ThreeMD 2.0 `.binary` output, for files that ThreeMD 2.0.x must read.
   * @throws DocumentStorageError exactly as the 2.0 binary writer did, or the AbortSignal reason.
   */
  public static encodeTextContainer(
    document: Document,
    compression?: DocumentCompression,
    limits?: DocumentDecodeLimits,
    signal?: AbortSignal,
  ): Uint8Array;
}
```

The `DocumentStorageErrorCode` union and the `DocumentStorageError` class are unchanged.

Observable behavior:

- **Decoded values** (11.3.8): plain objects `{ version, axis, title, metadata, preamble, planes }` and planes
  `{ z, label, x, y, attributes, body }`, properties created in that order; `null` for absent values; metadata and
  attributes created with `Object.create(null)` and filled in stored order (raw UTF-8 byte order); nothing frozen.
  JavaScript enumerates integer-like keys first whatever the insertion order, so tests compare with `documentsEqual`
  or `toEqual`, never with key enumeration order.
- **Lone surrogates.** The writer rejects a string holding a lone surrogate with `invalidDocument("Strings must
  contain losslessly representable Unicode scalar values.")`, using the existing `utf8Length` scan (which also runs
  where `String.prototype.isWellFormed` is missing).
- **Equivalent keys.** The writer merges canonically equivalent keys (first spelling, last value), exactly as
  `canonicalStrings`. When a map actually contains equivalent keys, it first runs the existing `validateRecords` on
  the unmerged document, so lone surrogates and record limits in a dropped value still fail as in 2.0 `validate`.
  Without this, the prototype measured 4 disagreements in 400,000 fuzz cases.
- **Key order.** The writer sorts by code point (equal to UTF-8 byte order), never with `<`.
- **UTF-8.** One lazily created `TextDecoder("utf-8", { fatal: true, ignoreBOM: true })`, called only without the
  `stream` option, so it never holds pending bytes. A string longer than 65,536 bytes is split at scalar boundaries
  (step back over at most 3 continuation bytes, 11.3.13) into chunks of at most 65,536 bytes; each chunk, including
  the last, is decoded by a separate non-streaming call, with a cancellation check between chunks. The streaming
  variant that 11.3.13 also allows (all chunks but the last with `{ stream: true }`, the last with
  `{ stream: false }`) needs a new decoder for every chunked string and after every decode error; the shared-decoder
  design avoids that. Decoding the last chunk with `{ stream: true }` is a defect: a string ending in `E2 82` is then
  accepted and its pending bytes join the next string.
- **Header lengths** are read with `getBigUint64`. A caller buffer is copied or read once, so overwriting it after
  decode does not change the result.

Keeping the element bundle unaffected. `element/src/three-md.ts` imports only `parse` from `js/src/index.ts`, but
`index.ts` imports `canonicalNumber` from `storage.ts` and re-exports the storage classes, so `storage.ts` and
everything it imports are in the element's module graph. Bun removes them only when every module-level statement is
free of side effects. The 2.0 bundle (48,816 bytes) contains no storage code, and that must stay true:

1. `storage.ts`, `structured.ts` and `checksum.ts` have no top-level side effects. Every module-level initializer is a
   literal, a function or class declaration, or an expression marked `/* @__PURE__ */`. CRC tables, the
   `TextDecoder`, `TextEncoder`, `DataView` scratch buffers and typed arrays are created lazily on first use (a
   module-level `let table: Int32Array | null = null` plus an accessor) or annotated pure. No top-level IIFE, no
   top-level `new` without the annotation.
2. `canonicalNumber` moves to a new pure module `js/src/number.ts`, imported by both `index.ts` and `storage.ts` and
   re-exported from `storage.ts` for compatibility. The parser then has no import edge into `storage.ts`.
3. `scripts/check-element-bundle.mjs` gains two assertions on the freshly built bundle: it contains none of the
   markers `TextDecoder`, `Int32Array`, `Float32Array`, `DocumentStorageError`, `Scalar fields cannot contain`,
   `structured payload`, `getBigUint64`; and its size is at most 50,000 bytes. The existing drift check (fresh build
   equals `web/assets/three-md.js` and `element/dist/three-md.js`) stays.

### Rust (`rust/src`)

New public items (`storage.rs`, re-exported from `lib.rs`):

```rust
/// Payload kind 1: canonical UTF-8 text behind the binary header (ThreeMD 2.0, SPEC 11.1).
pub const PAYLOAD_KIND_CANONICAL_TEXT: u8 = 1;
/// Payload kind 2: structured document records (ThreeMD 2.1, SPEC 11.3).
pub const PAYLOAD_KIND_STRUCTURED_DOCUMENT: u8 = 2;
/// The payload kinds this release decodes.
pub const SUPPORTED_PAYLOAD_KINDS: [u8; 2] = [1, 2];

/// Raw fixed header fields of a binary container, reported without validation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub struct DocumentContainerInfo {
    /// The independent container version; 1 for every payload kind in ThreeMD 2.1.
    pub container_version: u16,
    /// The payload kind byte.
    pub payload_kind: u8,
    /// The raw compression identifier.
    pub compression: u8,
    /// The raw feature flags.
    pub flags: u32,
    /// The raw reserved field.
    pub reserved: u32,
    /// The declared encoded payload byte count.
    pub encoded_payload_byte_count: u64,
    /// The declared decoded (uncompressed) payload byte count.
    pub decoded_payload_byte_count: u64,
    /// The declared CRC-32/ISO-HDLC value.
    pub checksum: u32,
}

/// Reads the 40-byte header without validating it, the payload or the checksum.
///
/// Returns `Ok(None)` when the input does not begin with the binary magic, and `Err(InvalidContainer)` when the magic
/// is present but fewer than 40 bytes exist.
pub fn container_info(data: &[u8]) -> Result<Option<DocumentContainerInfo>, DocumentStorageError>;

/// Writes payload kind 1, byte-identical to ThreeMD 2.0 `encode(.., Binary(c), ..)`, for files that ThreeMD 2.0.x must
/// read. Errors are exactly those of the 2.0 binary writer.
pub fn encode_text_container(
    document: &Document,
    compression: DocumentCompression,
    limits: &DocumentDecodeLimits,
    options: &OperationOptions,
) -> Result<Vec<u8>, DocumentStorageError>;
```

`lib.rs` adds `DocumentContainerInfo`, `PAYLOAD_KIND_CANONICAL_TEXT`, `PAYLOAD_KIND_STRUCTURED_DOCUMENT` and
`SUPPORTED_PAYLOAD_KINDS` to its `pub use storage::{...}` list.

Changed behavior:

- `storage::encode(document, DocumentStorageFormat::Binary(c), limits, options)` writes payload kind 2.
- `storage::decode` accepts payload kind 2.
- `canonical_number` and `swift_double` take the shortest digits from `{:e}` or `{:?}` and use the explicitly rounded
  spelling with the same digit count only when it parses back to the same value (ties go to the even neighbour, as in
  Swift and JavaScript). The prototype matched TypeScript on 1,003,863 values (every signed power of two, 10^k for k
  in −30 to 30, boundaries and 1,000,000 random bit patterns); the 2.0 code mismatched on 92.

Internal:

- New private module `structured.rs`: cursor, number forms, `str::from_utf8` per string (chunked above 65,536 bytes),
  a SWAR LF scan, segment rules, byte-order key checks, equivalence through `unicode-normalization`, R2, R3 and R9,
  Phase L with the bound shortcut, Phase Q through `crate::parse`, `read_document(.., materialize)` and the writer.
- New private module `checksum.rs`: `const` slicing tables. Slicing-by-16 is recommended (measured 2.98 GB/s against
  1.89 GB/s for slicing-by-8 on the reference machine) and keeps the kind-1 decode within the 1.10 gate. No
  `std::arch` path; `#![forbid(unsafe_code)]` in `lib.rs`.
- z uniqueness: a `HashSet<u64>` of bit patterns. All cap arithmetic uses `checked_sub` or the W1b guard, so 32-bit
  targets (`i686-unknown-linux-gnu` in CI) cannot overflow.

### Error mapping

No code is added (11.3.12). Each entry point raises:

| Entry point | Error type | Kind-2 codes |
|---|---|---|
| Storage decode | Swift `DocumentStorageError`; TypeScript `DocumentStorageError`; Rust `DocumentStorageError` | every code of 11.3.12, plus cancellation |
| Storage encode `.binary` | same | `invalidLimits`, `oversizedInput` (W1b, W3, W5), the reader's codes from W4, `compressionUnavailable`, `unsupportedCompression` (TypeScript), cancellation |
| `encodeTextContainer` | same | exactly the 2.0 `.binary` codes |
| `containerInfo` | same | `invalidContainer` only |
| Composition decode | Swift and TypeScript: `DocumentCompositionError` for `profileBytesExceeded` and profile and graph codes, `DocumentStorageError` for other storage codes. Rust: `DocumentCompositionError`, storage codes wrapped as `Storage(code)` | as 2.0; `oversizedInput`, `oversizedOutput` and `oversizedRecord` from the envelope become `profileBytesExceeded`; `unsupportedPayloadKind(3)` for kind 3 |
| File resolver | as 2.0 | children of kind 1 and 2 accepted; kind 3 refused with `unsupportedPayloadKind(3)` |

Cancellation stays Swift `CancellationError`, the TypeScript `AbortSignal` reason and Rust
`DocumentStorageError::Cancelled`. Inside composition decode a binary envelope is decoded with `maximumEncodedBytes`,
`maximumDecodedBytes` and `maximumRecordBytes` equal to `maximumProfileBytes` and `maximumPlanes` equal to 1, so the
kind-2 decoded-length bound is `maximumProfileBytes − 40`.

### `containerInfo` per language

| Field | Swift | TypeScript | Rust |
|---|---|---|---|
| container version | `containerVersion: UInt16` | `containerVersion: number` | `container_version: u16` |
| payload kind | `payloadKind: DocumentPayloadKind` | `payloadKind: number` | `payload_kind: u8` |
| compression | `compression: UInt8` | `compression: number` | `compression: u8` |
| flags | `flags: UInt32` | `flags: number` | `flags: u32` |
| reserved | `reserved: UInt32` | `reserved: number` | `reserved: u32` |
| encoded length | `encodedPayloadByteCount: UInt64` | `encodedPayloadByteCount: bigint` | `encoded_payload_byte_count: u64` |
| decoded length | `decodedPayloadByteCount: UInt64` | `decodedPayloadByteCount: bigint` | `decoded_payload_byte_count: u64` |
| checksum | `checksum: UInt32` | `checksum: number` | `checksum: u32` |
| no magic | returns `nil` | returns `null` | `Ok(None)` |
| magic, fewer than 40 bytes | throws `invalidContainer` | throws `invalidContainer` | `Err(InvalidContainer)` |

### Text-container writer per language

| Language | Name |
|---|---|
| Swift | `DocumentStorageCodec.encodeTextContainer(_:compression:limits:)` |
| TypeScript | `DocumentStorageCodec.encodeTextContainer(document, compression?, limits?, signal?)` |
| Rust | `storage::encode_text_container(document, compression, limits, options)` |

`encodeTextContainer` is the 2.0 binary writer, unchanged, including its validation and error order.

### Migration snippets

```swift
// 2.0 and 2.1: same call. In 2.1 the result is payload kind 2.
let bytes = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
// For a ThreeMD 2.0.x reader, write payload kind 1 instead:
let legacy = try DocumentStorageCodec.encodeTextContainer(document)
// Which kind is this file?
if let info = try DocumentStorageCodec.containerInfo(bytes),
    !DocumentStorageCodec.supportedPayloadKinds.contains(info.payloadKind) {
    // needs a newer ThreeMD
}
// A binary composition bundle is the profile envelope stored as kind 2:
let bundle = try DocumentStorageCodec.encode(
    DocumentCompositionCodec.document(for: composition), format: .binary(compression: .none))
let reopened = try DocumentCompositionCodec.decode(bundle)
```

```ts
const bytes = DocumentStorageCodec.encode(document, DocumentStorageFormat.binary());   // payload kind 2
const legacy = DocumentStorageCodec.encodeTextContainer(document);                      // payload kind 1
const kind = DocumentStorageCodec.containerInfo(bytes)?.payloadKind;                    // 2
```

```rust
let bytes = storage::encode(&document, DocumentStorageFormat::Binary(DocumentCompression::None), &limits, &options)?;
let legacy = storage::encode_text_container(&document, DocumentCompression::None, &limits, &options)?;
let kind = storage::container_info(&bytes)?.map(|info| info.payload_kind); // Some(2)
```

To convert a 2.0 `.3mdb` (kind 1) to kind 2, decode it and encode it with `.binary`; the `Document` is identical.
Converting back with `encodeTextContainer` reproduces the 2.0 bytes exactly. A ThreeMD 2.0.x application that opens a
2.1 file sees `DocumentStorageError.unsupportedPayloadKind(2)` (Rust composition decode:
`DocumentCompositionError::Storage(UnsupportedPayloadKind(2))`) and should present it as "this file needs a newer
ThreeMD".

## CLI surface (`Sources/CLI/main.swift`, product `threemd`)

The CLI is not a library API, but its surface is part of the `ThreeMDCLI` contract:

- Every subcommand (`validate`, `info`, `html`, `links`, `check-links`) reads its input as bytes, from a path or from
  standard input (`-`). Input with the binary magic goes through `DocumentStorageCodec.decode` with standard limits;
  other input keeps the 2.0 path (UTF-8 decode and `Parser().parse`) and its output, byte for byte.
- **Storage failures.** A storage failure prints one line, `threemd: <path>: <code>: <description>`, to stderr
  (`<path>` is `-` for standard input) and exits 1. With `--json`, stdout carries the existing failure shape
  `{"ok": false, "error": {"code", "message", "line", "detail"}}` (the existing `ErrorOutput`), filled for a
  `DocumentStorageError` as follows:
  - `code`: the storage case name, the same strings as the TypeScript `DocumentStorageErrorCode` (for example
    `checksumMismatch`, `unsupportedPayloadKind`, `invalidText`). Today's `ErrorOutput` reports `"error"` for
    anything that is not a `ParseError`; 2.1 adds the storage branch.
  - `message`: the error's `localizedDescription`.
  - `detail`: the associated value as a string: the decimal number for `unsupportedVersion(v)`,
    `unsupportedPayloadKind(k)`, `unsupportedCompression(c)` and `unsupportedFlags(f)`; the decimal raw value for
    `compressionUnavailable(c)`; the detail text for `invalidDocument(detail)`; the inner `ParseError` code for
    `invalidText(error)`. Other cases have no detail.
  - `line`: the inner `ParseError` line for `invalidText`; other cases have no line.
  - Absent `detail` and `line` keep today's `ErrorOutput` encoding: the synthesized `Encodable` omits a nil optional,
    so the key is absent rather than `null`.
- `threemd convert <input> <output> [--format text|binary|text-container] [--lzfse] [--force]` decodes any supported
  input with `DocumentStorageCodec.decode` and writes `.text`, `.binary` (kind 2) or `encodeTextContainer` (kind 1),
  all with standard limits.
  - Without `--format`, an output path ending in `.3md` means text and one ending in `.3mdb` means binary. When the
    format cannot be inferred (any other extension, or an output of `-`), `convert` prints its usage line to stderr
    and exits 1 without reading the input.
  - `--lzfse` applies to `binary` and `text-container`. With text output (given or inferred), `convert` prints its
    usage line and exits 1. Where LZFSE is missing (Linux), the encode fails with `compressionUnavailable` and exits 1.
  - An existing output file is refused (exit 1, file unchanged) unless `--force`. The output is written to a temporary
    file in the same directory and renamed, so a failure leaves no output file. An output of `-` writes to stdout and
    requires `--format`.
  - A decode or encode failure is a storage failure as above (`<path>` is the input path for a decode failure and the
    output path for an encode failure). `convert` has no `--json`.
- `threemd inspect [--json] <file>` reads the header with `containerInfo`, then decodes the whole input with
  `DocumentStorageCodec.decode` (standard limits, for text input too). Exit status 0 when the decode succeeds, 1
  otherwise. A failed decode is reported inside the output on stdout, not as the storage failure line on stderr. JSON
  output (`--json`, sorted keys as today) has exactly one of three shapes:
  - Binary input of at least 40 bytes: `format` (`"binary"`), `byteCount`, `containerVersion`, `payloadKind`
    (number), `payloadKindName` (`DocumentPayloadKind.description`: `canonicalText`, `structuredDocument` or
    `reserved(N)`), `supported` (whether the kind is in `supportedPayloadKinds`), `compression`, `flags`, `reserved`,
    `encodedPayloadByteCount`, `decodedPayloadByteCount` (numbers), `checksum` (8 lowercase hexadecimal digits, as in
    the golden manifests) and `decode`.
  - Binary input shorter than 40 bytes (magic present, so `containerInfo` throws `invalidContainer`): the same keys,
    with every header field and `supported` written as JSON `null` (the output type needs a custom `encode(to:)` with
    `encodeNil`, because the synthesized one would omit them), and `decode` reporting `invalidContainer`.
  - Text input (no magic): `format` (`"text"`), `byteCount` and `decode` only.
  - `decode` is `{"ok": true, "planes": N}` or `{"ok": false, "error": {...}}` with the `ErrorOutput` fields above, so
    a CRC failure shows `"code": "checksumMismatch"`.
  - Plain output prints the same fields one per line (`payload kind: 2 (structuredDocument, supported)`, `checksum:
    0x8A5B3B70`, then `decode: ok (2 planes)` or `decode: checksumMismatch: <description>`).
- The hosted web viewer and the `<three-md>` element stay text-only in 2.1.

## Why this design

`research.md` records the alternatives and measurements. In brief: the flat record layout was the fastest of three
prototyped layouts in both measured languages and the simplest to make canonical; tagged numbers keep exact bits with
no decimal conversion (94.6% of measured coordinates are small integers); byte-order keys make the written bytes
independent of Unicode tables while still rejecting equivalent spellings; exact text metrics and Phase Q keep validity
equal to text; and a full decode of a 4 MB file already takes 6 to 10 ms, so a lazy layout costs more than it saves.
