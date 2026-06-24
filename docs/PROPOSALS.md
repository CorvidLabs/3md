# 3md Post-1.0 Design Proposals

Status: non-normative proposal (nothing here is implemented)
Targets: a future MINOR spec version (1.1 or later)

This document is a design proposal, not a specification. The 1.0 grammar is
frozen: the frontmatter mini-format, the `@plane` directive and its attribute
grammar, the numeric grammar for `z`/`x`/`y`, the single-plane shorthand,
cross-plane links, escaping, and the error set are stable and will not change
within the 1.x line (SPEC.md section 10). Everything below is a sketch for the
maintainer to review before any implementation work begins. None of it is shipped,
and none of it is binding. Where a proposal would touch the frozen grammar, it is
designed to be purely additive so that 1.0 documents and 1.0 parsers are
unaffected.

The guiding constraint throughout is the 1.0 stability rule: parsers are
version-lenient (they record the `3md:` value but never reject on it), and any
additive directive, attribute, or key MUST degrade gracefully so that a 1.0
parser that does not understand it still parses the document and a 1.0 renderer
that does not understand it still shows the content. Each proposal is measured
against that rule.

The four candidate features are presented in priority order, most valuable and
lowest risk first:

1. Per-plane transition and timing hints
2. Inline model and asset embeds
3. Cross-document transclusion
4. A binary or compressed container for large scenes

---

## 1. Per-plane transition and timing hints

### Motivation

The `frame` and `time` axes are sequences meant to be played back or scrubbed.
`Examples/animation.3md` is a four-frame bounce; its only timing signal is an
`fps: "12"` key in the frontmatter, which is document-wide and opaque to the
core. There is no portable way for an author to say "hold this frame longer",
"ease into the next plane", or "this day spans a different interval than the
others". Today a renderer either guesses a uniform cadence or invents its own
private metadata. A small set of standard per-plane hints lets authors express
intent once and have every conforming renderer honor it the same way.

This is the highest-priority candidate because it is the lowest-risk: it adds
optional attributes to an existing directive, it changes no parsing rules, and
it degrades to exactly today's behavior when ignored.

### Proposed syntax

Timing hints are ordinary `@plane` attributes. They reuse the existing attribute
grammar verbatim (space-separated `key=value`, values quoted when they contain
spaces, the `z`/`x`/`y` numeric grammar where a number is wanted). No new
tokenization is introduced. Three attributes are proposed:

- `hold`: how long this plane is shown before advancing, as a duration string.
- `transition`: the named transition used when entering this plane.
- `ease`: the named easing curve applied to that transition.

A duration string is a finite decimal followed by a unit, where the unit is
`ms`, `s`, or `f` (frames). It is carried as a string and validated by the
timing-aware renderer, not by the core parser (see Parsing impact).

Before (valid 1.0, unchanged):

```3md
---
3md: 1.0
axis: frame
title: Bouncing dot
fps: "12"
---
@plane z=0 label="frame-0"
```
o........
```

@plane z=1 label="frame-1"
```
..o......
```
```

After (additive hints; still valid against a 1.0 parser):

```3md
---
3md: 1.1
axis: frame
title: Bouncing dot
fps: "12"
---
@plane z=0 label="frame-0" hold="250ms" transition="cut"
```
o........
```

@plane z=1 label="frame-1" hold="2f" transition="fade" ease="ease-in-out"
```
..o......
```
```

For a `time` axis the same attributes read naturally as schedule hints:

```3md
@plane z=0 label="Monday" hold="1d" transition="slide"
# Monday
- [ ] Standup at 9
```

Here `1d` is an author-chosen duration string; the proposal reserves only the
`ms`/`s`/`f` units as standard, and a renderer MAY accept additional units (`d`,
`h`, `m`) for the `time` axis. Unknown units are a renderer concern, not a parse
error, which keeps the core grammar untouched.

### Parsing and grammar impact

None to the core grammar. `hold`, `transition`, and `ease` are already legal 1.0
attributes today: section 4.1 says "Any other attribute is preserved as a string
on the plane; values are never coerced." A 1.0 parser already accepts these
tokens and exposes them as string attributes. This proposal does not move them
out of the catch-all; it only blesses three names and their value formats so
every renderer agrees on meaning.

A timing-aware implementation adds an optional extraction step, in the same
spirit as the cross-plane link extractor (section 8): given a parsed document, it
reads the three attributes off each plane, parses the duration grammar, and
returns a per-plane timing record (`hold`, `transition`, `ease`, each nullable).
Like link extraction, this is a separate, portable step pinned by new conformance
vectors; it does not change what `parse` returns.

Proposed standard vocabularies (renderer-facing, not grammar):

- `transition`: `cut`, `fade`, `slide`, `dissolve`. Default `cut`.
- `ease`: `linear`, `ease-in`, `ease-out`, `ease-in-out`. Default `linear`.

Values outside these sets are preserved verbatim (they are already just strings);
a renderer SHOULD fall back to the default for a name it does not recognize.

### Backward-compatibility analysis

Fully additive, and the safest of the four.

- 1.0 documents are unaffected: they carry none of these attributes, so behavior
  is identical.
- 1.0 parsers are unaffected: the attributes already parse today as generic
  string attributes per section 4.1, so a 1.0 parser reads an `after` document
  without error and exposes the values as plain attributes.
- 1.0 renderers degrade gracefully: a renderer that does not implement timing
  ignores unknown attributes and uses its existing cadence (for example the
  document `fps`), exactly as it does today.
- The error set in section 6 does not grow. A malformed duration string is NOT a
  parse error; it is a renderer-level concern, because making it a parse error
  would change `parse` results and thus break the conformance contract.

### Renderer impact

A timing-aware renderer reads the per-plane timing record and uses it to drive
playback or scrubbing: `hold` sets dwell time, `transition` and `ease` set the
animation between planes. Renderers that do not animate (for example `threemd
html` static output) ignore the hints with no loss of content. Because the hints
are advisory, two renderers may differ in exactly how a `fade` looks; the
conformance suite pins extraction (what the hints are), not pixels (how they
render).

### Open questions

- Should `hold` on a `time` axis accept calendar units (`d`, `h`, `m`) as
  standard, or stay limited to `ms`/`s`/`f` with calendar units left to
  renderers?
- Should a document-level default live in frontmatter (for example
  `transition: fade` as a free metadata key) so authors avoid repeating it on
  every plane? This is already expressible as free metadata; the question is only
  whether to standardize the key name.
- Should `f` (frames) be defined relative to the document `fps`, and what does
  `f` mean on a non-`frame` axis (proposed: undefined, renderer's choice)?

### Recommendation

Adopt for the next minor version. It is the clearest win: real author demand
(the `frame` and `time` axes exist precisely to be played), zero grammar change,
and graceful degradation by construction. Confidence: 88.

---

## 2. Inline model and asset embeds

### Motivation

The `space` axis (`Examples/dungeon.3md`) lays planes out on an imagined map with
`x`/`y`. The natural next step for scene authoring is to attach real assets to a
plane: a 3D model, an image, an audio cue. Markdown already embeds images with
`![alt](src)`, but there is no portable way to attach a richer asset (a `.glb`
model, a point cloud) to a plane, and stuffing it into image syntax loses the
alt-text fallback and the asset's type. A dedicated, `@plane`-consistent embed
directive gives spatial and frame viewers something to place while keeping plain
Markdown renderers fully functional.

### Proposed syntax

A new line-prefix directive, `@asset`, modeled exactly on `@plane`: first
whitespace-delimited token is `@asset`, followed by space-separated `key=value`
attributes using the identical attribute grammar (quoting, escaping, the
`z`/`x`/`y` numeric grammar). The open question in SPEC.md section 11 names it
`@model`; this proposal generalizes to `@asset` with a `kind` attribute so one
directive covers models, images, audio, and future types, rather than minting a
new directive per asset class.

An `@asset` line lives inside a plane body. Unlike `@plane`, it does NOT start a
new plane: it is a leaf directive that belongs to the plane it sits in. The lines
immediately following it, up to the next blank line, the next `@asset`, the next
`@plane`, or end of file, are its fallback Markdown (rendered when the asset is
not supported).

Proposed attributes:

- `src` (REQUIRED): the asset location, a relative path or URL, quoted.
- `kind` (OPTIONAL): `model`, `image`, `audio`, defaulting to a guess from the
  `src` extension.
- `x`, `y`, `z` (OPTIONAL): an in-plane placement offset, same numeric grammar.
- `alt` (OPTIONAL): a text description, quoted.

```3md
---
3md: 1.1
axis: space
title: The Sunken Vault
---
@plane z=3 label="vault" x=1 y=-1
# The Sunken Vault
The water pools around a stone chest ringed with old wards.

@asset src="vault.glb" kind="model" alt="A stone chest ringed with wards"
![A stone chest ringed with wards](vault.png)

A guardian of silt and bone rises as you approach.
```

The fallback line directly under the `@asset` (here a standard Markdown image) is
what a renderer without model support shows. The directive carries the rich asset;
the body carries the graceful fallback.

### Parsing and grammar impact

This one DOES touch the frozen grammar and must be handled with care. Section 4
defines `@plane` as the directive that starts a plane and says "Every line after
the directive ... is that plane's Markdown body." A 1.0 parser therefore treats a
`@asset` line as ordinary body text, which is the desired degradation (see
below). Adding `@asset` as a recognized directive is an additive 1.1 grammar
change: it introduces a new directive that a 1.1 parser lifts out of the body into
a structured per-plane `assets` list, while a 1.0 parser leaves it inline.

Because the line-prefix rules from section 4 are reused exactly (column 0,
outside fenced code blocks, attribute tokens MUST contain `=`), the recognition
logic is the same machinery `@plane` already uses. No new tokenizer, no new
numeric grammar, no new escaping. The 1.0 error names are reused where they map
(an `@asset` with an unterminated quote or an `=`-less token is the same shape of
error as `invalidPlaneDirective`); a missing `src` is a new 1.1-only condition and
SHOULD be a renderer-level warning rather than a hard parse error, to avoid
enlarging the section 6 error set in a way that could change 1.0 conformance
results.

### Backward-compatibility analysis

Additive, with a deliberate degradation path.

- 1.0 documents are unaffected: they contain no `@asset` lines.
- 1.0 parsers are unaffected in the sense that they never reject an `@asset`
  document: an unknown directive at column 0 is just body text to them (it is not
  `@plane`, so it does not start a plane, and section 4 sweeps it into the current
  plane body). The line is preserved verbatim and round-trips.
- 1.0 renderers degrade gracefully: because the `@asset` line and its fallback
  Markdown both sit in the plane body, a 1.0 renderer shows the fallback (the
  `![alt](src)` image, or the text) and shows the literal `@asset ...` line as a
  stray line of text. To keep that stray line from being noise, a renderer MAY be
  told via convention to drop lines beginning with `@`; but the safe assumption is
  that the fallback below it is the real content.
- The round-trip guarantee (section 7) holds: a 1.0 parser keeps the `@asset`
  line as body text and re-serializes it unchanged.

The one wart is that, under a 1.0 parser, the `@asset` line is visible as raw
text. That is the price of a directive that a frozen parser cannot be taught to
hide. The fallback-Markdown-immediately-below convention is what makes this
acceptable: the meaningful content is always present in plain Markdown form.

### Renderer impact

An asset-aware renderer reads the per-plane `assets` list and places each asset
in the plane (a `model` in a 3D viewport, an `image` inline, an `audio` cue tied
to the plane's `hold` from proposal 1). A renderer that cannot show a given
`kind` falls back to the Markdown immediately under the directive. The static
`threemd html` path renders the fallback and SHOULD suppress the raw `@asset`
line once it recognizes the 1.1 directive.

### Open questions

- Should `@asset` be allowed in the preamble (before the first `@plane`) to
  attach a document-level asset, or is it strictly per-plane?
- Where does the fallback boundary end: the proposal says "until the next blank
  line". Should it instead be a single following line, to be unambiguous?
- Should multiple assets per plane be ordered, and is that order significant to
  renderers?
- Do we need an explicit `@asset`-less inline form, or is the dedicated directive
  enough?

### Recommendation

Adopt, but after proposal 1 and only once the fallback convention is pinned by
conformance vectors. It is more invasive than timing hints because it adds a
recognized directive, and its degradation under a 1.0 parser leaves a visible raw
line. The design is sound and clearly motivated by the `space` axis. Confidence:
70.

---

## 3. Cross-document transclusion

### Motivation

Large scenes, shared component libraries, and multi-author timelines all want to
pull planes from another `.3md` file rather than copy them. A dungeon could keep
each region in its own file; a planner could include a shared "recurring tasks"
plane. Today the only option is to paste content, which drifts out of sync.
Transclusion lets one document reference planes defined elsewhere.

This is the most powerful candidate and by far the riskiest, because it crosses a
file boundary and so drags in cycles, path resolution, axis mismatches, and
security. It is ranked third for exactly that reason.

### Proposed syntax

A new line-prefix directive, `@include`, again modeled on `@plane`: column 0,
outside code fences, `key=value` attributes with the 1.0 attribute grammar.
Extending the `[[...]]` cross-plane link form was considered and rejected (see
Open questions); a directive keeps included planes as first-class structure
rather than inline link text.

Proposed attributes:

- `src` (REQUIRED): a relative path to another `.3md` file, quoted.
- `select` (OPTIONAL): which planes to pull, as a `z` value or a `z` range using
  the 1.0 numeric grammar (for example `select="2"` or `select="0..3"`). Absent
  means all planes.
- `at` (OPTIONAL): the `z` offset at which the included planes are placed in the
  host document, same numeric grammar. Included `z` values are added to `at` so
  they do not collide with host planes.

```3md
---
3md: 1.1
axis: space
title: The Full Crypt
---
@plane z=0 label="entrance" x=0 y=0
# The Entrance
A cold stair descends north into the dark.

@include src="vault-wing.3md" select="0..3" at="10"
```

The included file's planes at `z=0..3` appear in the host at `z=10..13`. The host
remains a valid 3md document on its own; `@include` is resolved by a separate
linking step, not by the core parser.

### Parsing and grammar impact

The core parser does NOT resolve includes. As with `@asset`, a 1.1 parser
recognizes the `@include` directive and records it as a structured request
(`src`, `select`, `at`) attached to the document; a 1.0 parser treats the line as
ordinary body text. Resolution (reading the referenced file, parsing it, applying
`select` and `at`, and merging planes) is a distinct, opt-in step layered above
`parse`, comparable to link extraction in section 8 but with file I/O. Keeping
resolution out of the core means the pure, no-I/O `parse` contract that the
conformance suite pins is unchanged.

Merge rules the resolution step must enforce:

- After applying `at`, the merged document MUST still satisfy section 4.2: no two
  planes share the same `z`. A collision is a resolution error, not a parse
  error.
- Plane source order is preserved with the `@include` expanded in place.

### Hard questions this feature must answer

- Cycles. A includes B includes A. The resolver MUST detect cycles (track the set
  of resolved absolute paths on the current chain) and fail with a dedicated
  resolution error rather than recursing forever. A depth limit is a secondary
  guard.
- Axis mismatches. The host declares `axis: space`; the included file declares
  `axis: time`. Proposed rule: the host's axis wins, the included axis is
  ignored, and the resolver SHOULD warn. Silently merging time planes into a
  spatial scene is a footgun; a warning surfaces it without blocking.
- Relative paths. `src` is resolved relative to the including file's directory,
  never the process working directory, so a document tree is portable. Absolute
  paths and parent-directory escapes (`../`) are where security bites (below).
- Security. Transclusion reads arbitrary files and, with URLs, would fetch over
  the network. The resolver MUST be sandboxable: a default policy that forbids
  absolute paths, forbids `../` escapes outside a configured root, and forbids
  non-`file` URLs unless explicitly enabled. Network includes SHOULD be opt-in
  per call, never on by default. The core parser, which does no I/O, has no
  exposure here; all risk is in the resolution step, which is exactly why it is
  kept separate and opt-in.
- Frontmatter of the included file. Proposed rule: only its planes are pulled;
  its frontmatter (title, free metadata) is dropped, except the axis check above.

### Backward-compatibility analysis

Additive, same shape as `@asset`.

- 1.0 documents are unaffected: no `@include` lines.
- 1.0 parsers are unaffected: `@include` is an unknown column-0 line, swept into
  the plane body as text, preserved and round-tripped.
- 1.0 renderers degrade gracefully but incompletely: without the resolution step,
  the included planes simply do not appear, and the host document renders as if
  the `@include` were absent (the raw line shows as text, same wart as `@asset`).
  This is acceptable for a feature that is inherently about composition: the host
  still renders its own planes correctly.
- `parse` results and the conformance contract are unchanged, because resolution
  is a separate layer.

### Renderer impact

A resolution-aware tool runs the resolver before rendering, producing a single
merged document that any renderer then displays normally. Renderers themselves
need no transclusion knowledge; they render the merged result. Tools that skip
resolution show only the host's own planes.

### Open questions

- Directive vs link form. Extending `[[z=N]]` to `[[src.3md#z=N]]` was
  considered. It is rejected because the 1.0 link grammar and its pinned regex
  (section 8) are frozen, and because a link is inline reference text whereas
  transclusion produces structural planes; conflating them muddies both.
- Should `select` support label-based selection (`select="vault"`) in addition to
  `z`, given labels are not unique?
- How do cross-plane links inside an included file rebase under `at`? A
  `[[z=3]]` in the included file should presumably become `[[z=13]]` after an
  `at="10"` shift; this rewrite is non-trivial and must be specified.
- Do we cap include depth, and at what number?

### Recommendation

Defer past the next minor version. The feature is genuinely useful but carries
the most semantic weight (link rebasing, axis policy, cycle detection) and the
only real security surface in the four proposals. Ship proposals 1 and 2 first,
let the `@asset`/`@include` directive-recognition machinery settle, then return
to transclusion as its own focused minor version. Confidence: 52.

---

## 4. Binary or compressed container for large scenes

### Motivation

A `space` or `frame` document that embeds many assets (proposal 2) or transcludes
a tree of files (proposal 3) can grow large. Plain `.3md` text is ideal for
authoring and diffing but is not ideal for shipping a megabyte-scale scene with
bundled binaries. A container format would let a finished scene travel as one
compressed file with its assets inside.

This is ranked last and is a sketch only: it is a packaging concern layered
entirely above the text format, it interacts with features (assets,
transclusion) that are themselves not yet shipped, and it has the weakest
near-term demand.

### Sketch of options

The text format does not change at all. A container is a wrapper that holds one
or more `.3md` documents plus their referenced assets, with a manifest. The
sketch is intentionally shallow; the point is to record the tradeoffs, not to
choose now.

Option A: a zip-based bundle (a `.3mdz` file).

```
scene.3mdz                (a zip archive)
  manifest.3md            (frontmatter + an @include or @asset graph)
  planes/region-a.3md
  assets/vault.glb
  assets/vault.png
```

- Pros: zip is universal, every language has it, assets are stored verbatim,
  inspectable by unzipping, and `manifest.3md` is itself a plain 3md document so
  the existing parser reads it unchanged.
- Cons: no streaming, whole-archive compression is coarse, and it is a real
  container spec to define (path rules, the manifest contract).

Option B: a single self-describing text-plus-blob file (frontmatter declares a
binary payload appended after the planes).

- Pros: stays "one file of mostly text", greppable header.
- Cons: mixing text and binary in one stream fights the plain-text ethos and the
  round-trip guarantee, and tooling support is bespoke.

Option C: gzip the whole `.3md` (a transport encoding, `scene.3md.gz`).

- Pros: trivial, no new format, handles the text-size case immediately.
- Cons: does not bundle assets, so it solves only the smallest part of the
  problem.

Recommended direction if pursued: Option A (`.3mdz` zip bundle with a
`manifest.3md`), because it reuses the unchanged text parser for the manifest,
stores assets without re-encoding, and leans on a universally supported archive
format. Option C is a zero-cost stopgap for pure-text size that can ship anytime
since it touches nothing.

### Parsing and grammar impact

None on the text grammar. A container is a separate format with its own reader;
the `.3md` parser is unchanged and is reused to read the manifest and any
contained documents.

### Backward-compatibility analysis

Trivially compatible: `.3md` text and 1.0 parsers are entirely untouched. A
container is a new, optional sibling format. A tool that does not understand
`.3mdz` simply does not open it; nothing about existing `.3md` files or parsers
changes.

### Renderer impact

A container-aware tool unpacks the bundle, resolves the manifest (which leans on
proposals 2 and 3), and hands a merged document to an ordinary renderer.
Renderers need no container knowledge.

### Open questions

- Is the demand real before assets and transclusion ship and prove out scene
  sizes? Likely not.
- Should the container be the same `.3md` text format zipped (Option A) or a
  purpose-built layout?
- Do we need streaming or random access into large scenes, or is whole-bundle
  decompression enough?

### Recommendation

Later, and only after proposals 2 and 3 exist. It is a packaging layer for
features not yet built, with no grammar impact and the least immediate need. If
text size alone becomes a pain point sooner, ship Option C (`.3md.gz`) as a
zero-spec transport stopgap. Confidence: 35.

---

## Summary

| Feature | Confidence | Recommended for next minor version |
|---------|------------|------------------------------------|
| 1. Per-plane transition and timing hints | 88 | yes |
| 2. Inline model and asset embeds | 70 | yes (after 1) |
| 3. Cross-document transclusion | 52 | later |
| 4. Binary or compressed container | 35 | later |

Across all four, the design discipline is the same: keep the frozen 1.0 grammar
untouched where possible, add only optional attributes or recognized directives
that a 1.0 parser sweeps into the body as text, keep all I/O and resolution in
separate opt-in steps so the pure `parse` contract and its conformance vectors
never move, and make every feature degrade to today's behavior when a tool does
not understand it.
