# Security Policy

## Supported versions

3md is at 1.0 (a stable, frozen grammar). Security fixes target the latest
release of each implementation: the Swift `ThreeMD` library, the
`@corvidlabs/threemd` parser, the `threemd` crate, and the
`@corvidlabs/three-md-element` web component.

## Reporting a vulnerability

Please report security issues privately rather than opening a public issue. Use
GitHub's private vulnerability reporting on the repository (the Security tab,
"Report a vulnerability") at https://github.com/CorvidLabs/3md/security. We aim
to acknowledge a report within a few business days.

## Attack surface

- The parsers do no I/O. `parse` only reads a string; it never touches the
  network or the filesystem, so the core has a minimal attack surface. A
  malformed document throws a documented `ParseError`, which is correct behavior,
  not a vulnerability.
- The `<three-md>` web component renders untrusted 3md by escaping all author
  text before it is inserted into the DOM (inline formatting is applied to the
  already-escaped text), so document content cannot inject markup or script.
  Please report any case where it can.
- The `threemd` CLI reads the files you pass it and writes to standard output.

## Not a vulnerability

- A malformed document that is rejected with a documented `ParseError`.
- Rendering differences between implementations for content outside the shared
  conformance suite.
