---
spec: ThreeMDElement.spec.md
---

## Context

ThreeMDElement is the `<three-md>` custom element: the canonical, framework-
agnostic interactive renderer for the 3md format. 3md is Markdown extended along
one free third axis (the Z axis): an ordinary Markdown document flows left to
right and top to bottom, and 3md adds depth by stacking **planes**, where each
plane is itself ordinary Markdown. The author declares what that Z axis means
(time, depth, layer, frame, space, or any custom label).

This element's job is narrow and well bounded: take 3md source, render it as a 3D
stack of planes, and let a reader scrub, drag, and step through that stack along
the Z axis. It does the visual only. It does NOT parse 3md text. Parsing is
delegated to `@corvidlabs/threemd`, the shared, conformance-tested data layer,
whose `parse` returns a typed `Document` of `Plane` values. The element reads
that document and renders it; the grammar lives in `SPEC.md` and the shared
parser.

The element is published as `@corvidlabs/three-md-element` at package version
1.0.0. It renders format version 1.0. The package version is a package release
number, not the format version; the format is defined and frozen separately in
`SPEC.md`.

### Module purpose and boundaries

- In scope: rendering a parsed `Document` as a 3D plane stack, the seven render
  modes, pointer/scrub/keyboard interaction, the `planechange` event, the read
  accessors, theming through CSS custom properties and `::part`, and graceful
  error display.
- Out of scope (non-goals): parsing, serializing, or validating 3md; full
  CommonMark rendering; editing or persisting documents; resolving cross-plane
  links; any 3D engine beyond CSS 3D transforms.

### Why a web component

The 3md parser is shared across Swift, TypeScript, and Rust and pinned by a
conformance suite. The interactive renderer used to be bespoke inline script,
copied between the demo and the marketing site, and it drifted: a Safari and
Low-Power bug where the focused plane never came to the front had to be fixed in
each copy. Shipping the renderer as one custom element fixes that at the root,
and the same element works the same in plain HTML, React, Vue, Svelte, and
Angular.

### File and type layout

Source lives in `element/src/three-md.ts`, a single module:

- `ThreeMDElement` - the exported `HTMLElement` subclass. It owns an open shadow
  root, builds the DOM once, loads source (from `src` or inline text), builds one
  plane node per plane, and renders state synchronously. It exposes the `document`,
  `currentIndex`, and `mode` getters and the `goTo`, `setSource`, and `render`
  methods, and dispatches `planechange`.
- `Mode` - the render-mode union (`stack`, `play`, `layers`, `scene`, `parallax`,
  `present`, `elevator`).
- `AXIS_MODE` - the map from axis names (and bare mode names) to a `Mode`, used to
  pick a default mode from `document.axis` or to interpret the `mode` attribute.
- Small pure helpers - `esc` (HTML escape), `inline` and `fmt` (inline Markdown
  on escaped text), and `renderMarkdown` (the small block subset).
- `STYLES` - the shadow-root stylesheet, including the themeable custom
  properties and the `::part` targets.
- The bottom of the file registers the `three-md` tag with `customElements.define`
  when it is not already defined, and augments `HTMLElementTagNameMap`.

### Related modules

- `@corvidlabs/threemd` is the shared parser that this element depends on; it
  provides `parse`, `Document`, and `Plane`. All grammar conformance is owned
  there and by the shared vectors, not here.
- `SPEC.md` is the prose format specification. This element renders documents that
  conform to it but does not implement its grammar.
- `uitests/component.spec.mjs` is the cross-browser test suite that guards the
  element's invariants in Chromium and WebKit.

## Design Decisions

- **Render, do not parse.** The single most important boundary: the element calls
  `parse` from `@corvidlabs/threemd` and renders the result. Parsing conformance
  is centralized in the shared data layer and its vectors, so the viewer cannot
  drift from the spec. This element only owns pixels.

- **Focus-relative positioning.** Each plane's depth is computed from its distance
  to the focus (`d = idx - focus`), so the focused plane is always frontmost in
  true Z. A naive fixed layout (`z = -idx * 150`) leaves plane 0 in front
  regardless of selection, which Safari exposes because it paints by true Z and
  ignores `z-index` inside `preserve-3d`. This is invariant 1 and is pinned by a
  cross-browser test that reads each plane's `matrix3d` m43.

- **Synchronous render, optional rAF.** `render()` is synchronous and is the
  single source of truth for the stage. It runs on every interaction and never
  waits on `requestAnimationFrame`. The rAF loop adds only cosmetic idle drift;
  the element stays correct and usable when rAF is throttled or paused, as iOS
  Low Power Mode does. This is invariant 2, also pinned by a test that neutralizes
  rAF before any script runs.

- **Touch drives the model, never the page.** The stage sets `touch-action: none`
  and handles pointer events through one unified path for mouse, touch, and pen.
  A vertical drag moves along Z, a horizontal drag orbits. The element is width-
  constrained so it never overflows horizontally from 320px to 1440px. This is
  invariant 3, pinned by a multi-width overflow test.

- **Shadow DOM with a themeable surface.** Styles live in an open shadow root for
  isolation, and the surface is themed through CSS custom properties while
  internals are reachable through `::part`. This gives style isolation without
  forcing a fork to restyle.

- **Graceful failure through an error part.** Blank source, invalid 3md, and fetch
  failures render a visible error part rather than throwing. A load token guards
  asynchronous `src` loads so a stale response never overwrites a newer one.

- **Mode chosen from the axis, overridable by attribute.** With no `mode`
  attribute, the element derives a mode from `document.axis` through `AXIS_MODE`,
  defaulting to `stack`. The `mode` attribute can force any mode, and an axis name
  given there is mapped the same way, so authors can override the visual without
  changing the document.

## Rendering pipeline

The element runs a small fixed flow:

1. **Build.** On first connect (or first `setSource`), attach the shadow root if
   needed, inject `STYLES`, and build the wrap, axis label, stage (arrow, scene,
   hint), and controls (prev, scrubber, next, readout). Wire the scrubber, the
   prev/next buttons, the keyboard handler, and the unified pointer handlers. Make
   the host focusable.

2. **Load.** Resolve source: fetch `src` (token-guarded) or use inline text.
   Trim; on blank or parse failure, show the error part. On success, store the
   document and planes, apply the mode, reset focus and target to 0, and build the
   plane nodes.

3. **Build planes.** Clear the scene, set the axis label, and create one plane
   node per plane with its tag line and rendered Markdown body, each clickable to
   focus it. Set the scrubber max to the last index and update the readout.

4. **Render.** For each plane compute its transform from `d = idx - focus` under
   the active mode, set its `transform`, `opacity`, `z-index`, and hot/dim
   classes, then set the scene transform (orbit and drift). Update the readout and,
   if the rounded focus index changed, emit `planechange`. This step is
   synchronous and is the only place the stage is mutated.

5. **Interact.** Scrub, drag, prev/next, arrow keys, and `goTo` all set the
   target, snap the focus to it, update the scrubber value, and call `render()`.
   The optional rAF loop calls `render()` for idle drift while not dragging.
