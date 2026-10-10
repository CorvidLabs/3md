---
change: add-matching-x-y-z-axis-rotation-gizmos-and-precise-camera-steps-to-sculpt-and-the-viewer
artifact: requirements
---

# Requirements

### REQ-ThreeMDViewer-007

The viewer and Sculpt volume view SHALL provide matched document-axis rotation constraints and numerical rotation/pan steps alongside the camera sphere.

Acceptance Criteria:

- Both volume views show a small sphere with colored X, Y and Z rotation rings and accessible axis buttons. Choosing an axis constrains dragging and step buttons to rotation around that document axis; Free restores unconstrained orbit.
- Three-axis rotation preserves an orthonormal camera orientation and supports Z rotation without changing model cells, slice, Undo, files, or installed geometry. Native and browser use the same document-axis convention, including row Y and plane Z.
- Both views offer an editable rotation step in degrees (default 15 degrees) with minus and plus nudges, and an editable pan step in cells (default 0.25) with directional nudges. Values must be finite and positive; invalid input leaves the current camera unchanged. Fit resets the default pose and pan.
- Tests compare shared asymmetric projection and picking cases including Z rotation, full X/Y/Z turns, negative nudges and exact inverse steps; native live and scalar renderers agree. Camera controls remain usable on narrow screens and have keyboard labels and focus indication.
- Synchronize viewer and Sculpt contracts and intent, record actual current tests, and complete verified lifecycle closure only under Leif’s explicit approval of this new definition. Leif retains PR merge authority. Preserve storage, rendering budgets, parser APIs, releases and trust policy.
