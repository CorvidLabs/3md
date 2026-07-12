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

## Durable Requirements

### REQ-threemdcli-001

The implementation SHALL satisfy the following criterion: **FR-1 (Subcommands).** The executable accepts one of the following subcommands as its first argument: `validate`, `info`, `html`, `links`, or `check-links`. Any other argument or a missing subcommand prints usage information and exits with code 1.

Acceptance Criteria

- **FR-1 (Subcommands).** The executable accepts one of the following subcommands as its first argument: `validate`, `info`, `html`, `links`, or `check-links`. Any other argument or a missing subcommand prints usage information and exits with code 1.

### REQ-threemdcli-002

The implementation SHALL satisfy the following criterion: **FR-2 (validate subcommand).** Parses the specified file. Prints "ok" and exits 0 on success. On parsing failure, prints the error details to stderr and exits 1.

Acceptance Criteria

- **FR-2 (validate subcommand).** Parses the specified file. Prints "ok" and exits 0 on success. On parsing failure, prints the error details to stderr and exits 1.

### REQ-threemdcli-003

The implementation SHALL satisfy the following criterion: **FR-3 (info subcommand).** Prints metadata (version, axis, title, plane count) and each plane's properties (z, label, coordinates, extra attributes).

Acceptance Criteria

- **FR-3 (info subcommand).** Prints metadata (version, axis, title, plane count) and each plane's properties (z, label, coordinates, extra attributes).

### REQ-threemdcli-004

The implementation SHALL satisfy the following criterion: **FR-4 (html subcommand).** Renders the document to HTML and prints the output to stdout.

Acceptance Criteria

- **FR-4 (html subcommand).** Renders the document to HTML and prints the output to stdout.

### REQ-threemdcli-005

The implementation SHALL satisfy the following criterion: **FR-5 (links subcommand).** Extracts and prints all cross-plane links and the link graph representation.

Acceptance Criteria

- **FR-5 (links subcommand).** Extracts and prints all cross-plane links and the link graph representation.

### REQ-threemdcli-006

The implementation SHALL satisfy the following criterion: **FR-6 (check-links subcommand).** Validates all cross-plane links. If there are dangling links, it prints details to stderr and exits with code 1. If all links resolve, it prints "ok" and exits 0.

Acceptance Criteria

- **FR-6 (check-links subcommand).** Validates all cross-plane links. If there are dangling links, it prints details to stderr and exits with code 1. If all links resolve, it prints "ok" and exits 0.

### REQ-threemdcli-007

The implementation SHALL satisfy the following criterion: **FR-7 (JSON output option).** The `validate`, `info`, `links`, and `check-links` subcommands support a `--json` flag. When provided, the command prints the output formatted as JSON to stdout instead of raw text. ### Non-Functional Requirements

Acceptance Criteria

- **FR-7 (JSON output option).** The `validate`, `info`, `links`, and `check-links` subcommands support a `--json` flag. When provided, the command prints the output formatted as JSON to stdout instead of raw text. ### Non-Functional Requirements

### REQ-threemdcli-008

The implementation SHALL satisfy the following criterion: **NFR-1 (Zero third-party dependencies).** The CLI target depends only on the local `ThreeMD` library target and Foundation. No external package manager or CLI parsing library is used.

Acceptance Criteria

- **NFR-1 (Zero third-party dependencies).** The CLI target depends only on the local `ThreeMD` library target and Foundation. No external package manager or CLI parsing library is used.

### REQ-threemdcli-009

The implementation SHALL satisfy the following criterion: **NFR-2 (Fast execution).** CommandLine parsing and execution are fast, with minimal startup overhead.

Acceptance Criteria

- **NFR-2 (Fast execution).** CommandLine parsing and execution are fast, with minimal startup overhead.

### REQ-threemdcli-010

The implementation SHALL satisfy the following criterion: **NFR-3 (Swift 6 Executable).** The executable builds cleanly under Swift 6 strict concurrency settings.

Acceptance Criteria

- **NFR-3 (Swift 6 Executable).** The executable builds cleanly under Swift 6 strict concurrency settings.

## Acceptance Criteria

### Functional Requirements

- **FR-1 (Subcommands).** The executable accepts one of the following subcommands as its first argument: `validate`, `info`, `html`, `links`, or `check-links`. Any other argument or a missing subcommand prints usage information and exits with code 1.
- **FR-2 (validate subcommand).** Parses the specified file. Prints "ok" and exits 0 on success. On parsing failure, prints the error details to stderr and exits 1.
- **FR-3 (info subcommand).** Prints metadata (version, axis, title, plane count) and each plane's properties (z, label, coordinates, extra attributes).
- **FR-4 (html subcommand).** Renders the document to HTML and prints the output to stdout.
- **FR-5 (links subcommand).** Extracts and prints all cross-plane links and the link graph representation.
- **FR-6 (check-links subcommand).** Validates all cross-plane links. If there are dangling links, it prints details to stderr and exits with code 1. If all links resolve, it prints "ok" and exits 0.
- **FR-7 (JSON output option).** The `validate`, `info`, `links`, and `check-links` subcommands support a `--json` flag. When provided, the command prints the output formatted as JSON to stdout instead of raw text.

### Non-Functional Requirements

- **NFR-1 (Zero third-party dependencies).** The CLI target depends only on the local `ThreeMD` library target and Foundation. No external package manager or CLI parsing library is used.
- **NFR-2 (Fast execution).** CommandLine parsing and execution are fast, with minimal startup overhead.
- **NFR-3 (Swift 6 Executable).** The executable builds cleanly under Swift 6 strict concurrency settings.

## Constraints

- Operates locally on file paths.
- Does not watch files for changes or host a server.

## Out of Scope

- Formatting or editing .3md files in-place.
- Downloading remote .3md URLs (networking is not in scope for the CLI).
