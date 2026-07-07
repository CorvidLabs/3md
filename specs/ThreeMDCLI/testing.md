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

- **Dedicated Executable Integration Tests.** There are currently no automated tests running the compiled `threemd` binary in a sandbox shell to assert on exit codes, stdout, and stderr. Adding a test suite that invokes the binary via `Process` would bridge this gap.
