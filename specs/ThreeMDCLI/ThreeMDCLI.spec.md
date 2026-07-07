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

## Public API

### Subcommands

| Subcommand | Arguments | Description |
|------------|-----------|-------------|
| `validate` | `[--json] <file>` | Parses the file. Prints "ok" (or JSON) and exits 0 on success. Exits 1 with the error on failure. |
| `info` | `[--json] <file>` | Prints document metadata (version, axis, title, plane count) and details about each plane. |
| `html` | `<file>` | Renders the parsed document into standalone HTML5 and prints to stdout. |
| `links` | `[--json] <file>` | Extracts and prints all cross-plane links and link graph structure. |
| `check-links` | `[--json] <file>` | Validates all cross-plane links. Exits 1 if there are dangling links. |

## Invariants

1. If no arguments or an unknown subcommand is specified, the CLI prints usage information to stderr/stdout and exits with code 1.
2. When the `--json` flag is provided to `validate`, `info`, `links`, or `check-links`, all output is serialized as JSON to stdout.
3. On any parsing or validation failure (or check-links failure with dangling links), the tool exits with code 1.
4. Calling `threemd` with `--help`, `-h`, or `help` prints the usage summary to stdout and exits with code 0.
5. Specifying a file path of `-` redirects the tool to read the source from standard input.

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

## Error Cases

| Error | When | Behavior |
|-------|------|----------|
| `missingSubcommand` | Subcommand argument is omitted | Prints full usage to stdout and exits 1 |
| `unknownSubcommand` | Subcommand argument is not recognized | Prints error to stderr, usage to stdout, and exits 1 |
| `missingFile` | Subcommand's file argument is omitted | Prints subcommand-specific usage line to stderr and exits 1 |
| `fileNotFound` | File path does not exist on disk | Prints "threemd: file not found: '<path>'" to stderr and exits 1 |
| `invalidEncoding` | File cannot be read as UTF-8 | Prints "threemd: cannot read '<path>' (is it valid UTF-8?)" to stderr and exits 1 |
| `parseError` | File contains malformed 3md syntax | Exits 1, printing parser error details (or structured JSON if `--json` was passed) |

## Dependencies

- `ThreeMD` library
- Foundation

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1 | 2026-07-07 | Initial spec for the CLI tool. |
