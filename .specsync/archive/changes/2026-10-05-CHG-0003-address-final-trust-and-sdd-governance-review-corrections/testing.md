---
change: CHG-0003-address-final-trust-and-sdd-governance-review-corrections
artifact: testing
---

# Testing

- Confirm `specsync check --strict --force --require-coverage 100` passes.
- Confirm all four skill copies quote the answer placeholder.
- Confirm Trust no longer ignores governed public-documentation paths.
- Run the repository native verification lane and `fledge trust verify`.
- Require the final hosted Trust, UI, and CodeQL checks to pass.
