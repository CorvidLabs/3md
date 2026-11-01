---
change: run-the-specsync-archive-gate-before-every-ci-job
artifact: tasks
---

# Tasks

- [x] Add the Archive job to linux.yml, pages.yml, sculpt.yml, trust.yml and ui.yml.
- [x] Make every other job in those workflows need `archive-gate`.
- [x] Parse each edited workflow and confirm the job graph.
Lifecycle (tracked by SpecSync itself, not a task): Record approval and review, then archive this change before merge.
