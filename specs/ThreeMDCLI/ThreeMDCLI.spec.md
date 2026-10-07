---
module: ThreeMDCLI
version: 1
status: draft
files:
  - Sources/CLI/main.swift

db_tables: []
depends_on:
  - ThreeMD
---

# ThreeMDCLI

## Purpose

ThreeMDCLI is the command-line interface tool for the 3md file format. It provides subcommands to parse, validate, extract metadata and links, and render `.3md` files to HTML.

Since ThreeMD 2.1 every subcommand also reads general binary storage (`.3mdb`, payload kind 1 or 2, SPEC.md section 11), and two subcommands are added: `convert` writes text, structured binary (payload kind 2) or the ThreeMD 2.0 text container (payload kind 1), and `inspect` reports a binary header and whether the input decodes. Text input keeps the 2.0 behavior and output byte for byte.

## Public API

### Subcommands

| Subcommand | Arguments | Description |
|------------|-----------|-------------|
| `validate` | `[--json] <file>` | Parses or decodes the file. Prints "ok" (or JSON) and exits 0 on success. Exits 1 with the error on failure. |
| `info` | `[--json] <file>` | Prints document metadata (version, axis, title, plane count) and details about each plane. |
| `html` | `<file>` | Renders the parsed document into standalone HTML5 and prints to stdout. |
| `links` | `[--json] <file>` | Extracts and prints all cross-plane links and link graph structure. |
| `check-links` | `[--json] <file>` | Validates all cross-plane links. Exits 1 if there are dangling links. |
| `convert` | `<input> <output> [--format text\|binary\|text-container] [--lzfse] [--force]` | Decodes any supported input with `DocumentStorageCodec.decode` and writes `.text`, `.binary` (payload kind 2) or `encodeTextContainer` (payload kind 1), all with standard limits. Has no `--json`. |
| `inspect` | `[--json] <file>` | Reads the binary header with `containerInfo`, then decodes the whole input with `DocumentStorageCodec.decode` under standard limits, text input included. Exits 0 when the decode succeeds and 1 otherwise. |

### Input

Every subcommand reads its input as bytes, from a path or from standard input (`-`). Input that begins with the binary magic `3mdbin\r\n` goes through `DocumentStorageCodec.decode` with standard limits, which accepts payload kinds 1 and 2. Other input keeps the 2.0 path, a UTF-8 decode and `Parser().parse`, and its output, byte for byte. The hosted web viewer and the `<three-md>` element stay text-only.

### Storage failure output

A `DocumentStorageError` from `validate`, `info`, `html`, `links`, `check-links` or `convert` prints one line, `threemd: <path>: <code>: <description>`, to stderr and exits 1. `<path>` is `-` for standard input; for `convert` it is the input path for a decode failure and the output path for an encode failure. With `--json`, stdout carries the existing failure shape `{"ok": false, "error": {"code", "message", "line", "detail"}}`, whose `ErrorOutput` gains a storage branch:

- `code`: the storage case name, the same strings as the TypeScript `DocumentStorageErrorCode` (for example `checksumMismatch`, `unsupportedPayloadKind`, `invalidText`). Before 2.1 every error that was not a `ParseError` reported `"error"`.
- `message`: the error's `localizedDescription`.
- `detail`: the associated value as a string: the decimal number for `unsupportedVersion(v)`, `unsupportedPayloadKind(k)`, `unsupportedCompression(c)` and `unsupportedFlags(f)`; the decimal raw value for `compressionUnavailable(c)`; the detail text for `invalidDocument(detail)`; the inner `ParseError` code for `invalidText(error)`. Other cases have no detail.
- `line`: the inner `ParseError` line for `invalidText`; other cases have no line.
- An absent `detail` or `line` is omitted, as the synthesized `Encodable` does today, rather than written as `null`.

### convert

- Without `--format`, an output path ending in `.3md` means text and one ending in `.3mdb` means binary. When the format cannot be inferred (any other extension, or an output of `-`), `convert` prints its usage line to stderr and exits 1 without reading the input.
- `--lzfse` applies to `binary` and `text-container`. With text output, given or inferred, `convert` prints its usage line and exits 1. Where LZFSE is missing (Linux), the encode fails with `compressionUnavailable` and exits 1.
- An existing output file is refused (exit 1, file unchanged) unless `--force`. The output is written to a temporary file in the same directory and renamed, so a failure leaves no output file. An output of `-` writes to stdout and requires `--format`.

### inspect

A failed decode is reported inside the output on stdout, not as the storage failure line. JSON output (`--json`, sorted keys) has exactly one of three shapes:

- Binary input of at least 40 bytes: `format` (`"binary"`), `byteCount`, `containerVersion`, `payloadKind` (number), `payloadKindName` (`DocumentPayloadKind.description`: `canonicalText`, `structuredDocument` or `reserved(N)`), `supported` (whether the kind is in `supportedPayloadKinds`), `compression`, `flags`, `reserved`, `encodedPayloadByteCount`, `decodedPayloadByteCount` (numbers), `checksum` (8 lowercase hexadecimal digits) and `decode`.
- Binary input shorter than 40 bytes (the magic is present, so `containerInfo` throws `invalidContainer`): the same keys, with every header field and `supported` written as JSON `null`, and `decode` reporting `invalidContainer`.
- Text input (no magic): `format` (`"text"`), `byteCount` and `decode` only.

`decode` is `{"ok": true, "planes": N}` or `{"ok": false, "error": {...}}` with the `ErrorOutput` fields above, so a CRC failure shows `"code": "checksumMismatch"`. Plain output prints the same fields one per line, for example `payload kind: 2 (structuredDocument, supported)`, `checksum: 0x8A5B3B70`, then `decode: ok (2 planes)` or `decode: checksumMismatch: <description>`.

## Invariants

1. If no arguments or an unknown subcommand is specified, the CLI prints usage information to stderr/stdout and exits with code 1.
2. When the `--json` flag is provided to `validate`, `info`, `links`, `check-links`, or `inspect`, all output is serialized as JSON to stdout.
3. On any parsing or validation failure (or check-links failure with dangling links), the tool exits with code 1.
4. Calling `threemd` with `--help`, `-h`, or `help` prints the usage summary to stdout and exits with code 0.
5. Specifying a file path of `-` redirects the tool to read the source from standard input.
6. Input is classified by its content, never by its extension: input that begins with the binary magic is decoded by `DocumentStorageCodec.decode` with standard limits, and all other input takes the 2.0 text path, whose behavior and output are unchanged byte for byte.
7. A storage failure prints one stderr line, `threemd: <path>: <code>: <description>`, and exits 1. With `--json`, stdout carries the existing `ErrorOutput` failure shape with the storage case name as `code`.
8. `convert` never leaves a partial or replaced output on failure: it refuses an existing output without `--force`, writes through a temporary file in the output directory and renames it, and exits 1 on a usage error before reading the input.
9. `inspect` reads the header with `containerInfo` and then decodes the whole input, reports a failed decode inside its output on stdout, and exits 0 exactly when the decode succeeds.

## Behavioral Examples

```
Given a valid .3md file
When "threemd validate <file>" is called
Then stdout prints "ok" and the command exits with 0
```

```
Given a .3md file with dangling links
When "threemd check-links <file>" is called
Then the command prints details of the dangling links to stderr and exits with 1
```

```
Given a request for help using "--help", "-h", or "help"
When "threemd --help" is called
Then stdout prints the usage text and the command exits with 0
```

```
Given conformance/structured/worked-document.3mdb (payload kind 2)
When "threemd validate", "info", "html", "links" or "check-links" is called on it
Then stdout is byte-equal to the same command on its canonical text
```

```
Given a kind-2 file with a corrupt CRC
When "threemd validate --json <file>" is called
Then the command exits 1 and error.code is "checksumMismatch", with no detail or line key;
without --json, stderr is exactly "threemd: <file>: checksumMismatch: <description>"
```

```
Given a file whose header declares payload kind 3
When "threemd validate --json <file>" is called
Then the command exits 1, error.code is "unsupportedPayloadKind" and error.detail is "3"
```

```
Given a text document doc.3md
When "threemd convert doc.3md doc.3mdb" is called
Then doc.3mdb holds payload kind 2, byte-equal to DocumentStorageCodec.encode with .binary
```

```
Given a 113-byte kind-2 file
When "threemd inspect <file>" is called
Then stdout shows "payload kind: 2 (structuredDocument, supported)", "checksum: 0x8A5B3B70" and "decode: ok (2 planes)",
and the command exits 0
```

## Error Cases

| Error | When | Behavior |
|-------|------|----------|
| `missingSubcommand` | Subcommand argument is omitted | Prints full usage to stdout and exits 1 |
| `unknownSubcommand` | Subcommand argument is not recognized | Prints error to stderr, usage to stdout, and exits 1 |
| `missingFile` | Subcommand's file argument is omitted | Prints subcommand-specific usage line to stderr and exits 1 |
| `fileNotFound` | File path does not exist on disk | Prints "threemd: file not found: '<path>'" to stderr and exits 1 |
| `invalidEncoding` | Input without the binary magic cannot be read as UTF-8 | Prints "threemd: cannot read '<path>' (is it valid UTF-8?)" to stderr and exits 1 |
| `parseError` | Text input contains malformed 3md syntax | Exits 1, printing parser error details (or structured JSON if `--json` was passed) |
| `storageError` | Binary input fails `DocumentStorageCodec.decode`, or `convert` fails to encode: any `DocumentStorageError` case, for example `checksumMismatch`, `unsupportedPayloadKind`, `lengthMismatch`, `invalidContainer`, `invalidUTF8`, `invalidText`, `invalidDocument`, `oversizedInput` or `compressionUnavailable` | Prints "threemd: <path>: <code>: <description>" to stderr and exits 1; with `--json`, prints the `ErrorOutput` failure with the storage `code`, `message`, and `detail` and `line` where the case has them |
| `convertUsage` | `convert` cannot infer the output format (another extension, or `-`, without `--format`), or `--lzfse` is combined with text output | Prints the `convert` usage line to stderr and exits 1 without reading the input or creating an output |
| `outputExists` | `convert` output path exists and `--force` is absent | Exits 1 and leaves the existing file unchanged |
| `inspectDecodeFailure` | `inspect` input fails to decode | Reports the failure in its `decode` field on stdout (plain or JSON) and exits 1 |

## Dependencies

- `ThreeMD` library, including `DocumentStorageCodec` (`decode`, `encode`, `encodeTextContainer`, `containerInfo`, `supportedPayloadKinds`) and `DocumentPayloadKind`
- Foundation

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1 | 2026-07-07 | Initial spec for the CLI tool. |
