---
spec: ThreeMDCLI.spec.md
---

# ThreeMDCLI Context

## Context

ThreeMDCLI is the Swift command line application for the 3md file format. While the core `ThreeMD` module provides parsing and serialization APIs, `ThreeMDCLI` exposes these features as a command line executable (`threemd`). It serves as a tool for validation, metadata inspection, link checking, and HTML generation.

## Related Modules

- [ThreeMD](file:///Users/leif/Development/_CorvidLabs/3md/specs/ThreeMD/ThreeMD.spec.md): The core Swift parser and serializer library that this CLI depends on.
- [SPEC.md](file:///Users/leif/Development/_CorvidLabs/3md/SPEC.md): The authoritative format specification that guides the validation and info output formats.

## Design Decisions

- **Minimalist Command Line Parsing.** Instead of introducing a dependency on a library like `swift-argument-parser`, the CLI manually parses arguments using basic pattern matching on `CommandLine.arguments`. This keeps the executable light, maintains a zero dependency footprint, and ensures fast compile and startup times.
- **Robust Error Mapping.** The CLI catches errors thrown by the core `Parser` and maps them directly to formatted terminal messages or structured JSON, maintaining a clean distinction between standard output and standard error.
- **Support for Tooling Integration.** Providing a `--json` flag on most subcommands allows external editors, plugins, and CI checkers to run `threemd` programmatically and parse its output reliably.
- **Binary input by content (ThreeMD 2.1).** Every subcommand reads bytes and routes input that begins with the binary magic through `DocumentStorageCodec.decode`, so `.3mdb` files of payload kind 1 or 2 work everywhere while text input keeps the 2.0 path and output byte for byte.
- **Stable storage codes.** Storage failures reuse the library's `DocumentStorageError` case names in the existing `ErrorOutput` shape instead of the generic `"error"` code, so scripts can branch on `checksumMismatch` or `unsupportedPayloadKind` exactly as TypeScript callers do.
- **Safe conversion.** `convert` infers the format only from `.3md` and `.3mdb`, refuses to overwrite without `--force`, and writes through a temporary file and a rename so a failure leaves no output. `inspect` uses the header-only `containerInfo` so it can describe files that a given release cannot decode.
