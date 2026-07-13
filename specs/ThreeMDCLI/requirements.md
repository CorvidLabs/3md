---
spec: ThreeMDCLI.spec.md
---

# ThreeMDCLI Requirements

These requirements describe the ThreeMDCLI Swift executable target: the command-line interface tool (`threemd`) for the 3md file format.

## User Stories

- As a developer, I want to validate my .3md files from the command line so I can verify their structural correctness quickly.
- As a developer, I want to inspect 3md document structure, properties, and links so I can debug document structures.
- As a publisher, I want to compile a 3md document to HTML via stdout so I can render it for static web preview.
- As a CI system, I want check-links to return non-zero exit codes on link failures so I can prevent broken builds.

## Acceptance Criteria

### Functional Requirements

### REQ-threemdcli-001

The executable SHALL accept the documented subcommands and return usage with exit code 1 for missing or unknown commands.

Acceptance Criteria

- The executable accepts one of the following subcommands as its first argument: `validate`, `info`, `html`, `links`, or `check-links`. Any other argument or a missing subcommand prints usage information and exits with code 1.
### REQ-threemdcli-002

`validate` SHALL parse the requested file, print `ok` on success, and report parse failures to stderr with exit code 1.

Acceptance Criteria

- Parses the specified file. Prints "ok" and exits 0 on success. On parsing failure, prints the error details to stderr and exits 1.
### REQ-threemdcli-003

`info` SHALL print document metadata and every plane's position, label, coordinates, and extra attributes.

Acceptance Criteria

- Prints metadata (version, axis, title, plane count) and each plane's properties (z, label, coordinates, extra attributes).
### REQ-threemdcli-004

`html` SHALL render the document to HTML on stdout.

Acceptance Criteria

- Renders the document to HTML and prints the output to stdout.
### REQ-threemdcli-005

`links` SHALL print every cross-plane link and the link graph representation.

Acceptance Criteria

- Extracts and prints all cross-plane links and the link graph representation.
### REQ-threemdcli-006

`check-links` SHALL fail with dangling-link details or print `ok` and exit successfully when all links resolve.

Acceptance Criteria

- Validates all cross-plane links. If there are dangling links, it prints details to stderr and exits with code 1. If all links resolve, it prints "ok" and exits 0.
### REQ-threemdcli-007

Supported inspection subcommands SHALL emit JSON on stdout when `--json` is supplied.

Acceptance Criteria

- The `validate`, `info`, `links`, and `check-links` subcommands support a `--json` flag. When provided, the command prints the output formatted as JSON to stdout instead of raw text.

### Non-Functional Requirements

### REQ-threemdcli-008

The CLI target SHALL depend only on the local `ThreeMD` target and Foundation.

Acceptance Criteria

- The CLI target depends only on the local `ThreeMD` library target and Foundation. No external package manager or CLI parsing library is used.
### REQ-threemdcli-009

The executable SHALL parse commands and start with minimal overhead.

Acceptance Criteria

- CommandLine parsing and execution are fast, with minimal startup overhead.
### REQ-threemdcli-010

The executable SHALL build cleanly under Swift 6 strict concurrency.

Acceptance Criteria

- The executable builds cleanly under Swift 6 strict concurrency settings.

## Constraints

- Operates locally on file paths.
- Does not watch files for changes or host a server.

## Out of Scope

- Formatting or editing .3md files in-place.
- Downloading remote .3md URLs (networking is not in scope for the CLI).
