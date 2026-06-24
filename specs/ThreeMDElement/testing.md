---
spec: ThreeMDElement.spec.md
---

## Test Plan

The `<three-md>` element is covered by a Playwright suite,
`uitests/component.spec.mjs`, run in both Chromium and WebKit. It drives the
built component (`web/assets/three-md.js`) through `web/embed-example.html` and
guards the invariants that have actually broken before: the focused plane is
frontmost in true Z while scrubbing, the element works with
`requestAnimationFrame` paused, and it does not overflow horizontally at phone
widths. The suite reads into the element's open shadow root to assert on real
rendered geometry.

### How to run

The suite runs through Playwright across the two browser projects:

```
bun run test:ui
```

The canonical CI gate is the `verify` lane defined in `fledge.toml`, which runs
the format check, the build, and the tests in order:

```
fledge lanes run verify
```

Run `fledge introspect` or check `fledge.toml` if the task list changes.

### Approach

The suite follows a few consistent patterns:

- **Real geometry through the shadow root.** Tests reach into
  `host.shadowRoot`, query `.plane` nodes and the range input, and read each
  plane's true Z from its computed transform via `new DOMMatrix(...).m43`. The
  assertions are about what the browser actually paints, not internal state.
- **Frame-capped scrubbing.** The `PLANE_Z(value)` helper sets the scrubber to a
  value, dispatches an `input` event, then resolves the plane Z list after a
  bounded number of animation frames (or a 2-second hard cap) so a paused or
  missing rAF can never hang the test.
- **rAF neutralized before scripts run.** The Low Power Mode test replaces
  `requestAnimationFrame` and `cancelAnimationFrame` with no-ops through
  `addInitScript` before any page script runs, then asserts the same correctness
  as the normal case.
- **Clean console.** The smoke test collects `console` errors and `pageerror`
  events and asserts the array is empty, so a runtime error fails the build.

### Coverage inventory

Grouped by behavior, with the asserting check of each test.

#### Upgrade and render

- `upgrades, renders planes, no console errors` - the inline element upgrades and
  renders exactly three planes, the `src=` variant also loads and renders, and no
  console or page errors occur.

#### Invariant 1: focus is frontmost in true Z

- `focused plane is frontmost across the scrubber` - for scrubber values 0, 1,
  and 2, the focused plane's true Z (`m43`) is the maximum of all planes' Z, so
  the selected plane is in front regardless of source order.

#### Invariant 2: works with requestAnimationFrame paused

- `works with requestAnimationFrame paused (Low Power Mode)` - with rAF
  neutralized before any script runs, the focused plane is still frontmost in
  true Z for scrubber values 0, 1, and 2, proving `render()` is correct without
  the animation loop.

#### Invariant 3: no horizontal overflow

- `no horizontal overflow from 320px to 1440px` - at widths 320, 390, 768, 1024,
  and 1440, the document scroll width does not exceed the window inner width
  (allowing 1px for sub-pixel rounding).

#### planechange event

- `emits planechange when stepping` - clicking the next part dispatches a
  `planechange` event whose detail has `index === 1` and `z === 1`.

### Gaps and future test ideas

The suite is invariant-focused and intentionally narrow. Known gaps:

- **Mode coverage.** Only the default mode path is exercised. The other render
  modes (`play`, `layers`, `scene`, `parallax`, `present`, `elevator`) and the
  `mode` attribute override, including axis-name mapping, are untested.
- **Error paths.** The error part is not asserted: blank source, invalid 3md
  (a `parse` throw), and a failing `src` fetch all render an error message that no
  test currently checks. The load-token staleness guard is likewise unverified.
- **Pointer and touch drag.** Tests drive the scrubber and the next button, but
  not pointer drag. Vertical-drag-moves-Z, horizontal-drag-orbits, and pointer
  capture behavior across mouse, touch, and pen are not exercised.
- **Keyboard navigation.** Arrow-key stepping (Right/Up and Left/Down) is not
  tested.
- **API surface.** The `document`, `currentIndex`, and `mode` getters and the
  `goTo` and `setSource` methods are not called directly from a test.
- **Markdown subset.** The small body renderer (headings, list and task items,
  blockquotes, inline code, bold, italic, the fenced grid) and its HTML escaping
  are not asserted node by node.
- **Theming and parts.** CSS custom property overrides and `::part` targeting are
  not verified to take effect.
