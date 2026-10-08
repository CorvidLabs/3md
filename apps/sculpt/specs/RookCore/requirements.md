---
spec: RookCore.spec.md
---

# Requirements

### REQ-RookCore-001

`AppAppearance` SHALL be system, light, or dark. `init(storedValue:)` SHALL default nil, empty, and unknown text to system. The stored token SHALL be the raw value. This module SHALL NOT import AppKit or open the network.

Acceptance Criteria

- Round-trip raw values stay `system`, `light`, and `dark`. Unknown text becomes system. `title` is present for each case.

### REQ-RookCore-002

RookCore SHALL remain the appearance module. It SHALL NOT import RookApp, RookSculpture, or RookRendering, and it SHALL NOT declare sculpture, camera, or document types.

Acceptance Criteria

- The public symbols stay `AppAppearance` and its existing members. The target has no package dependency.
