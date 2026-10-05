---
change: CHG-0001-adopt-trust-1-and-specsync-5
artifact: design
---

# Design

The workflow retains checkout, full git history, runner selection, and
project-specific dependency setup. One Trust action then runs the existing
Fledge verify lane, SpecSync contract validation, Augur's block threshold, and
soft provenance verification.

The committed policy is authoritative. Workflow inputs do not weaken it.
AGENTS.md remains protected by the existing marker check.
