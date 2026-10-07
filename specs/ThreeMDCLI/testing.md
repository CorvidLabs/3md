---
spec: ThreeMDCLI.spec.md
---

# ThreeMDCLI Test Plan

This document outlines the testing strategy for the command-line interface tool.

## Unit Testing

Since the CLI is an executable target (`threemd`) wrapping the core library APIs, most unit tests are centralized within the `ThreeMDTests` library test suite under `Tests/ThreeMDTests/`. This covers:
- Core parsing correctness (which backs `validate`, `info`, and `html`).
- Link parsing and dangling detection (which backs `links` and `check-links`).
- HTML rendering outputs.

## Integration Testing

### Manual CLI Checks

The CLI can be manually tested by building the package and running the subcommands against the sample documents in the `Examples` folder:

```bash
swift run threemd validate Examples/art-album.3md
swift run threemd info Examples/library-floors.3md
swift run threemd links Examples/library-floors.3md
swift run threemd html Examples/art-album.3md
```

### Automation Gaps

- **Dedicated Executable Integration Tests.** There are currently no automated tests running the compiled `threemd` binary in a sandbox shell to assert on exit codes, stdout, and stderr. ThreeMD 2.1 closes this gap with the planned suite below.

### Planned CLI Tests (ThreeMD 2.1)

`Tests/ThreeMDTests/CLITests.swift` runs the built `threemd` binary, located next to the test bundle in the products directory, with `Process`, so no new test target is needed. `Process` does not exist on iOS, tvOS, watchOS or visionOS, so the whole file is wrapped in `#if os(macOS) || os(Linux)`. Each case asserts stdout, stderr and the exit status:

- `validate`, `info`, `html`, `links` and `check-links` on `conformance/structured/worked-document.3mdb` give stdout byte-equal to the same commands on its canonical text, and the same commands work on a kind-1 file (`Examples/Extensions/canopy.3mdb`).
- A kind-2 file with a corrupt CRC exits 1 with stderr exactly `threemd: <path>: checksumMismatch: <description>`; with `--json`, `error.code` is `checksumMismatch` and the keys `error.detail` and `error.line` are absent.
- A kind-3 header (`conformance/interchange/invalid-binary-kind-3.3mdb`) exits 1 with `unsupportedPayloadKind`, and with `--json` `error.detail` is `"3"`.
- A kind-1 file whose payload is not 3md text gives `error.code` `invalidText` with the inner `ParseError` code (`missingFrontmatter`) as `error.detail` and its line as `error.line`; a kind-2 file with an invalid key gives `invalidDocument` with the detail text.
- `convert` text to binary, binary to text, binary to text-container and text-container to binary give outputs byte-equal to the library encoders. Extension inference (`.3md`, `.3mdb`) and `--format` overrides work. Another extension or `-` without `--format` exits 1 with the usage line and creates nothing; `--lzfse` with text output exits 1 with the usage line; an existing output without `--force` exits 1 and stays unchanged; `--lzfse` reports `compressionUnavailable` on Linux; output `-` with `--format` writes to stdout; a failure leaves no output file.
- `inspect` on text, kind 1, kind 2, a corrupt CRC and a truncated header (the magic and fewer than 40 bytes), plain and `--json`, with JSON key snapshots for the three shapes, and exit 0 exactly when `decode.ok` is true.
- Standard input (`-`) with binary input, for `validate` and `inspect`.
- Every existing CLI behavior on text keeps its output byte for byte.

Done when these tests pass on macOS and Linux and `swift run threemd inspect conformance/structured/worked-document.3mdb` prints kind 2 and `ok`.
