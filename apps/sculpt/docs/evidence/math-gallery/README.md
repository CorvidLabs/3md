# Math gallery and size ladder verification

Change: `show-every-example-in-one-gallery-and-add-a-math-generated-size-ladder-from-16-to-10-240-cells` (SCULPTURE-41). PR46 merged as `064c9aa`. Its product tree equals the tested head `bd12991`. The only files that differ between that head and `064c9aa` are the lifecycle files landed by PR45. ThreeMD stays pinned `exact: "2.0.0"`.

## Automated verification

GitHub Trust passed on `bd12991` ([run 37578415771](https://github.com/CorvidLabs/sculpt-3md/actions/runs/37578415771)), recorded in [trust-bd12991.log](trust-bd12991.log):

- The complete pinned lane passed: 7 steps in 11 minutes 15 seconds, 36 harness tests, and 637 tests in 53 suites.
- `hi check` reported 48 criteria and 53 retired.
- Strict SpecSync reported 5 specs, 0 warnings, 92/92 files and 25,533/25,533 lines.
- Augur returned proceed at risk 30, below the block threshold of 65.

The suites that cover the three requirements are `SculptureMathExamplesTests`, `SculptureGalleryCatalogTests`, `SculptureGalleryBrowserTests` and `Math ladder artifacts`. Each of those suites passed in that run.

## Native check

No completed native gallery check of the fixed build is recorded. The in-process gallery tests cover listing, opening a model, a composition and a world, and cancellation.

## Not claimed

No on-screen performance, exhaustive correctness, human review or signature is claimed.
