# Mandatory interchange catalog

`manifest.json` uses `3md-interchange-catalog-1`. Every case and declared format
must run through the Swift, TypeScript and Rust adapters. Paths are relative to
the repository root. Unknown kinds, missing files, duplicate IDs, omitted cases
and unclassified errors fail the development gate.

The catalog has 82 source cases: 49 valid and 33 invalid. It includes all 22 valid
and 15 invalid legacy parser source fixtures. Their text files preserve the
original JSON `source` bytes; their original parser contracts remain unchanged.
Invalid source parsing is observed through storage and therefore reports the
outer `invalidText` code. The driver also discovers every top-level legacy JSON
fixture, including the six link-source files, and checks fixed document semantic
expectations where supplied. Link extraction expectations remain in the existing
conformance suites. New legacy JSON entries cannot be silently skipped.

The existing extension goldens cover Unicode text, opaque metadata, stable
plane/reference identities, repeated graph instances, exact Unicode key
spelling and canonical equivalence collisions. New native-authored examples
cover literal apostrophes, escaped quotes and backslashes, Unicode edge spaces,
custom axes, fences, preambles, empty documents and bodies, mixed coordinates,
negative zero, shared graph definitions and valid unused nodes. Invalid cases
cover namespaced identity errors, invalid unused graph nodes, strict JSON fields
and binary header, length, checksum and UTF-8 failures.

Combining-mark fixtures ensure ASCII quotes, escapes, field separators, token
spaces and fence prefixes retain their scalar delimiter meaning even when a
following Unicode mark joins the same grapheme. Original scalar bytes survive
canonical, binary and legacy reimport.

`canonicalFile` and `binaryFile` are independent checked-in byte anchors where
present. Raw legacy source seeds can omit these anchors and still must agree
with the native canonical baseline. Successful document cases declare canonical,
uncompressed binary and legacy output; composition cases declare canonical and
uncompressed binary output. Legacy output is checked by faithful reimport,
not by requiring identical presentation bytes. Invalid cases declare no output
formats and require their stable error code.

`numericVectors` references all 45 existing IEEE754 numeric goldens. The driver
also adds its fixed seeded finite-number corpus. Coordinate semantic values use
exact IEEE754 bit strings with signed zero normalized. Canonical, binary,
adopted, edited and revision fields are compared as exact UTF-8/storage bytes.

Prepare adapters with `bun install --frozen-lockfile && bun run build` inside js
and `cargo build --example interchange` inside rust. Then run
`swift run threemd-interchange` from the repository root. The complete pinned
`fledge lanes run verify` lane performs those preparations, typechecks JavaScript,
runs all suites and executes the same gate. Node and Rust must be installed.
The separate development executable requires macOS 10.15+ when running on macOS;
it does not change the library deployment baseline.

The current finite gate has 479 requests: 82 catalog sources, 43 legacy JSON
sources, 45 fixed numbers, 256 seeded finite-number samples and 53 linked-file
(`files` kind) requests that the development driver generates under
[FILE-COMPOSITION.md](../../docs/FILE-COMPOSITION.md). Valid requests produce
17,451 imported outputs, 1,939 for each of the nine pairs, including canonical,
binary, legacy where applicable, adopted and edited files and source-free imports
of produced linked-file bundles. Invalid requests require an exact failure code
from each language. The driver writes its request/response transcripts and JSON
receipt to an isolated temporary directory and fails on any omission, mismatch,
unclassified failure or timeout.

This is a finite executable contract, not an exhaustive proof for every possible
input. See [PROTOCOL.md](PROTOCOL.md) for the development-only JSONL adapter and
deterministic public identity/edit operations. It does not define a public JSON
snapshot or patch wire format, change the text grammar, or permit filesystem
reference resolution.
