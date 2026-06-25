# Getting 3md recognized by GitHub (Linguist)

GitHub detects file languages with the open-source
[github-linguist/linguist](https://github.com/github-linguist/linguist) library.
"Adding 3md as a recognized language" means landing a PR there. This folder holds
everything that PR needs.

## The catch: the adoption bar

Linguist's contributing guide requires a new language to be **in real use across
many unique repositories** before they will merge it (historically on the order
of hundreds), so the language list stays meaningful. A brand-new format is
typically deferred until usage grows. Until then, the repo-level
[`.gitattributes`](../.gitattributes) is the right fix: it tells Linguist to
treat `.3md` as Markdown (instead of guessing Roff from the leading-dot ASCII
grids) and keeps the example corpus and generated GIFs out of the language bar.

## What we already have (the hard parts)

- **A TextMate grammar** for highlighting:
  [`editor/vscode/syntaxes/3md.tmLanguage.json`](../editor/vscode/syntaxes/3md.tmLanguage.json),
  scope `source.3md` (plus a links injection grammar).
- **Samples**: the 270 documents in [`Examples/`](../Examples). Linguist wants a
  handful under `samples/3md/`; any of these work.
- A frozen [SPEC](../SPEC.md) and three conformance-tested parsers.

## The PR, when adoption justifies it

1. Add the grammar to Linguist's `grammars.yml` and `vendor/grammars` submodule
   (point at this repo's `editor/vscode/syntaxes/3md.tmLanguage.json`, scope
   `source.3md`).
2. Add the entry from [`languages.yml.entry`](languages.yml.entry) to
   `lib/linguist/languages.yml` (alphabetical), assigning an unused
   `language_id` (Linguist maintainers confirm a stable value).
3. Copy 3-5 `Examples/*.3md` into `samples/3md/`.
4. `bundle exec rake test` and `script/licensed` per Linguist's contributing docs.
5. Open the PR; expect a request to demonstrate widespread `.3md` usage.

Tracking adoption (public repos containing `.3md`) is the real work between now
and a merge; the technical package above is ready.
