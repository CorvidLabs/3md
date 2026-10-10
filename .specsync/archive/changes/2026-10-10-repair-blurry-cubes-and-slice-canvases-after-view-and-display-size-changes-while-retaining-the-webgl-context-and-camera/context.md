---
change: repair-blurry-cubes-and-slice-canvases-after-view-and-display-size-changes-while-retaining-the-webgl-context-and-camera
artifact: context
---

# Context

Leif reported the existing browser preview was blurry after the approved Slice/camera work. Actual DOM and screenshot inspection found the shared 3D canvas bitmap at 368x322 while its Cubes display was 1099x911. The bitmap was frozen after initial context creation as a Safari workaround; a phone/reference-sized initialization was later stretched across a desktop stage.

This repairs the existing approved viewer/Sculpt-quality behavior under Leif's standing request to continue improving the browser and fix the viewer PR. It adds no editing tool, storage behavior, renderer or camera convention. Preserve the single WebGL context, installed mesh, source, selection, pose, 2x density cap and 2048 pixel edge cap. Resize only the drawable when its required dimensions change; validate actual in-app WebKit behavior rather than assuming every resize loses its context.
