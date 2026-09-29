---
change: CHG-0001-adopt-trust-1-and-specsync-5
artifact: testing
---

# Testing

- `specsync agents status` reports all four integrations installed.
- `fledge trust doctor` reports a healthy repository.
- `specsync check --strict --force` passes with the active change.
- `fledge trust verify` runs the existing verification lane and component gates.
- The pull-request `trust` job passes on the repository's established runner.
