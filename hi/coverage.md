---
hi: 1
families: [COVERAGE]
---

# Coverage

## Intent

I want the public coverage count to include the format libraries and the Sculpt.3md sources, and I want the app's own contract to stay in the app.

## Criteria

- **COVERAGE-1**  The public spec coverage count includes the format libraries and the Sculpt.3md implementation sources, and it reads 100%. Tests, docs, examples, and package manifests stay out of that count, as they already do for the format library.
- **COVERAGE-2**  Sculpt's own specsync check, run from apps/sculpt, reports 100% of its implementation sources. The Rook specs and apps/sculpt/hi remain the app contract. The format specs remain the format library.
