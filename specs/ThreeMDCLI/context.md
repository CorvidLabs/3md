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
