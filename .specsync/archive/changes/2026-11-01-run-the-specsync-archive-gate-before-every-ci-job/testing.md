---
change: run-the-specsync-archive-gate-before-every-ci-job
artifact: testing
---

# Testing

- Each edited workflow parses with Ruby Psych `safe_load`, and the printed job
  graph shows `archive-gate` with no needs and every other job needing it.
- `bash .github/scripts/archive-readiness.sh .` from CorvidLabs/spec-sync at the
  pinned commit lists the open changes and fails while any is open, and passes
  once all are archived.
- `specsync change audit --strict` no longer reports the workflow paths as
  uncovered.
- On the pull request, the Archive job runs first in each workflow and the
  other jobs are skipped while changes are open.
