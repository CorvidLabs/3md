---
change: add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli
artifact: context
---

# Context

## What led here

ThreeMD 2.0.0 (released 2026-10-06, tag `v2.0.0`, commit `ca2d1e3`) stores a `Document` in the general `.3mdb`
container as payload kind 1: a 40-byte header (magic `3mdbin\r\n`, container version 1, lengths, CRC-32/ISO-HDLC)
followed by the exact canonical UTF-8 text. Decoding it checks the header, runs the CRC over the whole payload and
then calls the same bounded text decoder that plain text uses.

After the release, a coverage and binary study measured 2.0.0 from an exact archive of `ca2d1e3` in Swift, TypeScript
and Rust (release builds, Mac Studio M1 Ultra, three interleaved runs per language). It found that binary never loads
faster than text:

| Language | Bounded text decode, 4.04 MB synthetic | Kind-1 binary decode | Cost of binary | Per-file median, binary ÷ text (293 Examples) |
|---|---|---|---|---|
| Swift | 296 ms | 318 ms | +7.4% | 1.06 |
| TypeScript (Node 26.10) | 186 ms | 231 ms | +24% | 1.25 |
| Rust 1.95 | 26 ms | 60 ms | +131% | 2.07 |

No Example file decoded more than 2% faster as binary in any language. Two causes:

- Kind 1 re-parses the text. The bounded text decode is itself 1.3 to 4.5 times slower than the legacy
  `parse(text)`, because it runs extra passes (a second line split, UTF-8 length counting, record checks).
- The CRC loops run at about 90 to 200 MB/s (Rust bitwise, Swift and TypeScript one table lookup per byte), so the
  checksum adds most of the binary-only cost.

The study also found that readers never check that a kind-1 payload is canonical (a BOM and CRLF text inside a valid
header decodes in all three ports), and that LZFSE (Swift only) compresses to about 27% of the text but still loads
3.6% slower than text. Test status at `ca2d1e3`: Swift 268 tests, TypeScript 157, Rust 49, all passing; the
interchange gate passed with 479 requests and 17,451 imports; Swift line coverage 95.51%, TypeScript 99.65%, Rust not
measured.

Leif (the maintainer) then asked for "a real binary format" in 2.1. Three designs were prototyped and measured, two
agent critiques examined the combined design, and a final specification package (SPEC 1.2 text, public API, test
plan, performance gate, work plan, goldens and three-language prototypes) was produced and then checked by an agent
review pass. No human reviewed the package. `research.md` has the evidence. This change carries that package into
the repository and implements it.

## Constraints

- **Byte identity.** Swift, TypeScript and Rust write byte-identical uncompressed kind-2 files for every `Document`
  that all three accept. The two documented exceptions (maps with canonically equivalent keys, and LZFSE output) stay
  out of cross-port vectors.
- **Exactness.** A kind-2 file decodes to exactly the `Document` that the bounded text decode of its canonical text
  yields, and it is valid exactly when that document passes the 2.1 `validate` under the same limits and the file fits
  `maximumEncodedBytes`.
- **2.0 files stay readable.** Text and kind 1 decode exactly as in 2.0, including leniency and every error. Every
  committed 2.0 `.3mdb` keeps its name and bytes. `encodeTextContainer` reproduces the 2.0 kind-1 bytes.
- **2.0 readers fail cleanly.** A 2.0 reader stops at the payload kind byte with `unsupportedPayloadKind(2)` before
  it computes the CRC or reads a payload byte.
- **Additive API.** No public enum gains a case, no error code is added and no existing signature changes. The one
  behavior change is that `.binary(compression:)` writes kind 2.
- **No new dependencies** beyond what the plan names. Rust keeps `unicode-normalization = "=0.1.25"` as its only
  dependency and adds `#![forbid(unsafe_code)]`. TypeScript adds no package. The development-only harnesses
  (`scripts/bench/swift`, `scripts/compat/rust`, `scripts/compat/swift`) depend only on the repository by path.
- **Purity.** Library calls stay synchronous, pure and bounded, check cancellation, return no partial result and do
  no file or network I/O.
- **Text-only surfaces.** The hosted viewer and the `<three-md>` element stay text-only. The element bundle carries
  no storage code and stays at or under 50,000 bytes.
- **LZFSE** stays an optional Apple-only backend. TypeScript and Rust report `compressionUnavailable(lzfse)`.
- **Toolchain pins.** Fledge 1.7.2, SpecSync 6.0.0 and Trust 1.2.2, as AGENTS.md describes. `fledge trust verify`
  must pass on the exact tip before the work is called complete. No lifecycle, contract, risk or provenance gate is
  weakened.
- **CI toolchains.** Swift 6.3.3, Node 24, Bun 1.4.2 and Rust 1.95, as pinned by `.github/workflows/linux.yml`; the new
  perf workflow pins the same.

## Prior attempts and what was ruled out

`research.md` has the measurements. In short:

- Kind 1 (2.0): text behind a header. It is slower than text in every language and stays only as the 2.0-compatible
  writer `encodeTextContainer`.
- Three designs were prototyped in Rust and TypeScript: "speed" (record stream plus a deduplicated string heap),
  "lazy" (container version 2, an indexed archive with block CRCs) and "simple" (flat records in document order). The
  flat layout was the fastest and the simplest to make canonical; the final design grafted onto it tagged numbers,
  exact text metrics, the Phase Q directive round trip and fast CRC loops.
- Ruled out: a lazy or partial-access API (Leif's decision), payload kind 3 in 2.1 (Leif's decision: bundles later),
  a string pool or key table, indexed and split layouts, container version 2, NFC key order in the payload, hardware
  CRC paths, compression by default, a hand-written Swift UTF-8 validator, the old G3 gate, and a separate 2.0.1
  patch release for the prerequisite fixes.

## Decisions and who made them

These decisions were made in the lead session's conversation with Leif on 2026-10-06. Leif's own words and choices
are quoted; everything else is attributed to the agent that decided it.

Leif's decisions:

| Decision | Made by |
|---|---|
| ThreeMD 2.1 gets "a real binary format", after the 2.0 study showed kind 1 loads slower than plain text | Leif |
| Structured documents now, as payload kind 2; bundles (structured compositions) later, with kind 3 reserved | Leif |
| `DocumentStorageFormat.binary` writes kind 2 by default (the 2.0 kind-1 bytes move to `encodeTextContainer`) | Leif |
| "Approve and build it" (about 21:00 MDT), an option whose description read in full: "I record the SpecSync definition under your approval, build all three ports in parallel, verify with Trust, the gate and Linux checks, open the PR, merge with your bypass, and release 2.1.0 when green." He did not pick the alternative "Approve, stop before release" | Leif |
| "The bypass" means what it meant for the 2.0.0 release: skipping main's rule that requires one approving pull request review. It never bypasses Trust, SpecSync, CI or any lifecycle, contract, risk or provenance gate | Leif (2.0.0 release choice "Merge with your bypass") |
| No lazy API | Leif |
| "ok let's move forward with this.. 2.1 is huge and is what 2.0 was ment to be" (verbatim) | Leif |

Leif did not ask to be spared further questions. After his "move forward" message the lead session told him he did
not need to do anything and that it would make the smaller calls itself; he did not object. The implementing agent
(Claude, recorded as `agent:claude`) made the following decisions on that basis. Each is open to Leif's veto:

| Decision | Made by |
|---|---|
| The fast CRC, the Rust `canonical_number` fix and the Swift frozen whitespace set ship in 2.1.0; there is no 2.0.1 | Claude, delegated |
| The Unicode guarantee is the restatement option of the specification plan: the three ports agree for strings of Unicode 13.0 code points on the pinned CI toolchains; no `platforms` minimum in `Package.swift` and no `engines` field in `js/package.json` | Claude, delegated |
| The interchange request `limits` object applies only to decoding the input; producers, adoption, edits and re-imports use standard limits | Claude, delegated |
| The plane count (S8) is checked before the line count (L5), so a kind-2 file over both limits reports `tooManyPlanes` where kind 1 reports `tooManyLines` | Claude, delegated |
| With LZFSE, the kind-2 decoded-length bound `min(Emax − 40, 2 × Dmax)` also applies, so the uncompressed container must fit `Emax` (intended) | Claude, delegated |
| WP3 to WP5 (the three ports) land together with WP6 (interchange) in one integration merge | Claude, delegated |
| CLI tests stay in `Tests/ThreeMDTests` (no new test target), so `Package.swift` is not added to the affected paths | Claude, delegated |
| WP0's human gate is satisfied by the SPEC diff being in the delivery pull request for Leif to read; the merge proceeds under his "Approve and build it" choice and does not wait for a separate SPEC review | Claude, delegated |
| The Rust G1 fallback (remaining measured techniques) applies only if calibration shows under 10% margin; the 0.25 floor is never loosened | Claude, delegated |

Approval of this definition records scope. It is not Leif's review of an implementation diff, an independent human
review, a GitHub approval or a signature, and no lifecycle record may claim one.

## For a session picking this up

- Work happens on branch `leif/structured-binary-2.1` (base `b7ac436`, which is `1ebe67d` plus one commit touching
  only `.specsync/`). The goldens and prototypes were generated from the `1ebe67d` archive; no file they read differs.
- The specification package lives in the lead session's scratch area and is not committed as a whole. Its durable
  copies are: SPEC.md sections 11.3 to 11.5 (WP0), `design.md` in this folder (the full public API), `plan.md` and
  `testing.md` here, the package's test plan and performance gate as
  `docs/design/threemd-2.1/test-plan.md` and `docs/design/threemd-2.1/perf-gate.md`, the fixtures under
  `conformance/structured/` and the input generators under `scripts/bench/` (WP1). Every reference to "test-plan"
  or "perf-gate" sections in this change means those two files.
- Directory ownership and the integration point are in `plan.md`. Lifecycle records (approve, check, review,
  finalize) belong to the lead and name the executing agent.
- Swift code follows the CorvidLabs conventions (explicit access control, no force unwraps, Swift 6 strict
  concurrency, `Sendable` types). TypeScript runs with Bun and `bun test`. Prose is plain English in sentence case.
