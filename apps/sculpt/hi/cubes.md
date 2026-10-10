---
hi: 1
families: [CUBES]
---

# Cubes

## Intent

I want to sculpt translucent cubes as well as ASCII, paint on a visible face, and open a volume up to 256 cells along each axis in the existing schema.

## Criteria

- **CUBES-21**  I can switch the same sculpture between ASCII and translucent cubes, with visible cube edges and a highlighted selected slice.
- **CUBES-22**  I can add cubes on a visible face or an empty selected slice, erase cubes, and undo a painting stroke without accidentally orbiting the camera.
- **CUBES-23**  I can open and edit a sculpture up to 64 cells along each axis in the existing 3md schema, while oversized or malformed files are refused.
- **CUBES-27**  I can create, paint, save and reopen a 256 by 256 by 256 volume, reach every cell with zoom and scrolling, and receive a clear explanation if its surface detail exceeds a preview or mesh export limit.

- **CUBES-28**  I can choose X, Y or Z on a rotation sphere, drag around only that axis, enter an exact degree step, and pan by a number of cells. Free gives me ordinary orbit again. The same camera movement works in the browser, and it does not change my sculpture or undo history.
