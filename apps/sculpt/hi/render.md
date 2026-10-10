---
hi: 1
families: [RENDER]
---

# Render

## Intent

I want larger previews to stay out of my way while I edit, and I want an export past its mesh limit to explain the limit without changing my sculpture.

I want to orbit and zoom a large sculpture immediately, without waiting for the whole volume to be rebuilt on each movement.

## Criteria

- **RENDER-25**  Larger previews render away from the interface so I can keep using the editor, and an export that exceeds its mesh limit explains the limit without changing my sculpture.
- **RENDER-29**  Live cube camera movement reuses the sculpture's prepared surfaces and updates the GPU camera without scanning the volume or rasterizing a bitmap on each event. I can rotate through full turns, pan with a tool or modified drag, scroll or pinch to zoom, and Fit returns the sculpture to its starting view. Painting and selection still target the visible sculpture, camera controls match the web viewer, and the packaged app uses an optimized build.
