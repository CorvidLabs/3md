---
change: keep-sculpt-and-web-cube-cameras-in-parity-with-unrestricted-orbit-and-screen-space-pan
artifact: research
---

# Research

Inspected SculptureProjection.swift, SculptureVoxelGeometry.swift, SculptureLiveVoxelView.swift and SculptureViewport.swift. Native pitch is clamped to +/-1.4 and browser pitch was clamped to +/-1.2. Native and browser yaw have opposite signs due to coordinate conventions. Native distance is three volume extents and scale is 0.68 of the smaller viewport dimension per extent. The browser retains its fit margin for small cubes. World Explore has intentional upright navigation and is excluded from this volume-camera change. The native live and scalar render paths must move together so painting and exports remain consistent.
