---
change: keep-sculpt-and-web-cube-cameras-in-parity-with-unrestricted-orbit-and-screen-space-pan
artifact: plan
---

# Plan

1. Keep the existing bounded cube meshes and native editing semantics.
2. Add session-only native pan coordinates and finite normalized camera inputs; share those inputs across ASCII, CPU cube projection and GPU camera transforms.
3. Add volume Pan and modified mouse dragging through the existing native pointer bridge, plus native scroll and magnification. Fit resets the camera. Match browser sensitivity, zoom bounds and pose.
4. Compare shared asymmetric projection cases and pole/pan picking. Run browser and native tests, synchronize contracts and intent, and record actual evidence.
5. Complete each approved lifecycle record with current verification and truthful agent review; publish only the existing feature PR. Leif retains merge authority.
