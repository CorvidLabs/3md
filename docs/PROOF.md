# Does 3md actually work? Proof notes

This document is the evidence, not a promise. It records how 3md was verified to
work for machines and for people, with reproducible commands. Everything here was
run against the code in this repository.

## 1. The three implementations agree (the contract)

3md ships three independent parsers: a Swift library (`ThreeMD`), a TypeScript
port (`@corvidlabs/threemd`), and a Rust crate (`threemd`). They are kept honest
by one shared conformance suite in `conformance/` that all three must pass. The
suite is the contract: if the parsers ever disagree, a vector fails.

Latest run:

| Implementation | Command | Result |
|----------------|---------|--------|
| Swift `ThreeMD` | `swift test` | 122 tests, 0 failures |
| TypeScript `@corvidlabs/threemd` | `bun test` (in `js/`) | 76 pass, 0 fail |
| Rust `threemd` | `cargo test` (in `rust/`) | all pass, incl. the 43-vector conformance suite |

The CLI built from the Swift package validates and inspects documents:

```
$ threemd validate file.3md   # prints "ok" or exits non-zero with the error
$ threemd info file.3md        # prints version, axis, title, and each plane
$ threemd html file.3md        # renders the document to HTML
```

It installs cleanly through Homebrew (verified end to end: `brew install
CorvidLabs/tap/threemd` then `brew test` both exit 0).

## 2. Proof in an AI sense

The claim: a machine can both author and read 3md correctly, using only the
specification.

The test was deliberately blind. A fresh AI agent was given exactly one file,
`SPEC.md`, and forbidden from looking at any example, any parser source, or any
existing `.3md` file. It was asked to invent an original, non-trivial document.
It produced `Examples/tide-pool.3md` ("The Anatomy of a Tide Pool", axis
`depth`): four planes descending from the surface film to the dark floor, with a
quoted label containing a space, `x`/`y` placement on one plane, a custom string
attribute on another, cross-plane links in both `[[z=N]]` and `[[z=N|text]]`
forms, and real Markdown bodies (headings, lists, a table, a blockquote).

That document was then fed to all three parsers, which had no part in writing it.
They agreed exactly:

| Field | Swift | TypeScript | Rust |
|-------|-------|------------|------|
| version | 1.0 | 1.0 | 1.0 |
| axis | depth | depth | depth |
| planes | 4 | 4 | 4 |
| z=2 x / y | 0 / -12 | 0 / -12 | 0.0 / -12.0 |
| attributes (`depth_cm`, `mood`) | preserved | preserved | preserved |

What this demonstrates:

- Authoring: an AI that has only read the spec writes conformant 3md on the first
  try. The grammar is small and self-contained enough to learn from one
  document. (The agent's only noted ambiguity was a cosmetic one: whether a blank
  line is required between a `@plane` line and its body. It is not; body trimming
  handles it.)
- Comprehension: parsing yields a flat, predictable structure (version, axis,
  ordered planes, each with z, optional label, optional x/y, a string-keyed
  attribute map, and a Markdown body). That is trivial for a model to consume,
  which is the point of keeping the frontmatter a flat mini-format rather than
  arbitrary YAML.

Reproduce: validate any document across the parsers with `threemd validate`, the
`bun test` harness in `js/`, and `cargo test` in `rust/`; the shared vectors live
in `conformance/`.

## 3. Proof in a human sense

The claim: a person can read, write, and review 3md by hand, with no tools.

3md is plain UTF-8 text. A `.3md` file is ordinary Markdown with a short header
and column-0 `@plane` lines. Open `Examples/tide-pool.3md` in any editor: the
frontmatter reads as labeled lines, each `@plane` announces a clearly named
section, and everything between directives is Markdown you already know. Nothing
is encoded, compressed, or binary.

Concretely, for humans:

- Readable raw. The depth of the tide pool is legible as a top-to-bottom read of
  the file, before any renderer is involved.
- Writable by hand. The blind-author test is itself the proof that the rules fit
  in your head; a person needs even less, since Markdown is already familiar.
- Diff-friendly and reviewable. Because it is line-oriented text, edits show up
  as clean diffs and the format passes through normal code review and version
  control unchanged.
- Tangible when rendered. The interactive lab makes the Z axis visceral without
  changing the source: scrub the slider and the focused plane comes to the front.
  Live at https://corvidlabs.github.io/3md/ (demo), `/gallery.html` (100
  examples), and `/docs.html` (docs).

## 4. Regression guard

The interactive demos are covered by a cross-browser test suite (`uitests/`,
Playwright on Chromium and WebKit) that runs in CI on every change to `web/`. It
asserts that planes render, that the focused plane stays frontmost in true Z
while scrubbing (the Safari-specific failure mode), that every axis tab loads,
and that the console stays clean. This is what keeps the visual proof from
silently breaking.

## Summary

- Three independent parsers, one conformance suite, all green.
- A blind AI authored valid 3md from the spec alone; all three parsers agreed.
- The format is plain text that a person can read, write, and review unaided.
- The demos are guarded by cross-browser CI so the proof stays true.
