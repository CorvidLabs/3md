# @corvidlabs/three-md-element

The canonical `<three-md>` web component: a framework-agnostic interactive
renderer for the [3md format](https://github.com/CorvidLabs/3md). Parsing is
delegated to [`@corvidlabs/threemd`](../js) (the shared, conformance-tested data
layer); this element owns only the visual - a 3D stack of planes you scrub,
drag, and step through along the document's Z axis.

It is a custom element, so it works the same in plain HTML, React, Vue, Svelte,
and Angular. There is one tested renderer instead of a per-app reimplementation.

## Why a web component

The 3md parser is shared across Swift, TypeScript, and Rust and pinned by a
conformance suite. The interactive renderer used to be bespoke inline script,
copied between the demo and the marketing site, and it drifted: a Safari and
Low-Power bug where the focused plane never came to the front had to be fixed in
each copy. Shipping the renderer as one component fixes that at the root.

## Install

Published to GitHub Packages. Point the `@corvidlabs` scope at the GitHub
registry once (in a project or user `.npmrc`), then install:

```bash
echo "@corvidlabs:registry=https://npm.pkg.github.com" >> .npmrc
bun add @corvidlabs/three-md-element
```

The published package is a single self-contained module (the parser is bundled
in, no other dependency), so you can also vendor `dist/three-md.js` and load it
directly:

```html
<script type="module" src="/three-md.js"></script>
```

## Usage

### Plain HTML

```html
<script type="module" src="/three-md.js"></script>

<!-- inline source -->
<three-md>---
3md: 1.0
axis: time
title: My week
---
@plane z=0 label="Monday"
# Monday
- [ ] Standup
</three-md>

<!-- or load a file -->
<three-md src="/plan.3md"></three-md>
```

### React

The element works as a normal tag. Pass inline source as children, or set `src`.
Listen for plane changes with a ref.

```tsx
import { useEffect, useRef } from "react";
import "@corvidlabs/three-md-element";

export function Plan() {
  const ref = useRef<HTMLElement>(null);
  useEffect(() => {
    const el = ref.current;
    const onChange = (e: Event) => console.log((e as CustomEvent).detail);
    el?.addEventListener("planechange", onChange);
    return () => el?.removeEventListener("planechange", onChange);
  }, []);
  return <three-md ref={ref} src="/plan.3md" />;
}
```

### Vue

```vue
<script setup>
import "@corvidlabs/three-md-element";
function onChange(e) { console.log(e.detail); }
</script>

<template>
  <three-md src="/plan.3md" @planechange="onChange" />
</template>
```

Tell Vue to treat it as a custom element (in `vite.config`):
`vue({ template: { compilerOptions: { isCustomElement: (t) => t === "three-md" } } })`.

### Svelte

```svelte
<script>
  import "@corvidlabs/three-md-element";
</script>

<three-md src="/plan.3md" on:planechange={(e) => console.log(e.detail)} />
```

### Angular

Add `CUSTOM_ELEMENTS_SCHEMA` to the component/module, import the package once,
then use the tag:

```ts
import "@corvidlabs/three-md-element";
// @Component({ ..., schemas: [CUSTOM_ELEMENTS_SCHEMA] })
```

```html
<three-md src="/plan.3md" (planechange)="onChange($event)"></three-md>
```

## API

### Attributes

| Attribute | Description |
|-----------|-------------|
| `src` | URL of a `.3md` file to fetch and render. |
| `mode` | Override the render mode. One of `stack`, `play`, `single`, `present`, `blend`, `map`, `layers`, `elevator`. Retired aliases such as `scene`, `parallax`, and `deck` are still accepted and mapped to current modes. Defaults to a mode chosen from the document's `axis`. |
| `autoplay` | Start auto-advancing as soon as content loads. `mode="play"` also auto-runs. |

Inline text content (the `.3md` source between the tags) is used when there is
no `src`.

### Properties and methods

- `document` - the parsed `Document`, or `null` before content loads.
- `error` - the parse or load error from the most recent failed load, or `null`.
- `errorLine` - the 1-based source line for parser errors when available.
- `errorCode` - the stable parser error code when available.
- `voxelizable` - whether the current document can render cleanly in `blend` mode.
- `currentIndex` - the index of the focused plane.
- `mode` - the active render mode.
- `playing` - whether playback is running.
- `goTo(index)` - focus a plane by index.
- `toggleFullscreen()` - toggle fullscreen for the whole component.
- `setSource(text)` - replace the rendered document with new 3md source.
- `play()` / `pause()` - control auto-advancing playback.

### Events

- `planechange` - dispatched when the focused plane changes. `event.detail` is
  `{ index, z, label, plane }`.

### Interaction

- Scrub the slider, use the prev/next buttons, or the arrow keys.
- On the stage, drag vertically to move along Z and horizontally to orbit. Touch
  works the same. The stage uses `touch-action: none` so a finger drives the
  model rather than scrolling the page.

## Theming

The component uses Shadow DOM for style isolation. Theme it with CSS custom
properties:

```css
three-md {
  --three-md-accent: #0e6f66;
  --three-md-bg: #0c0f12;
  --three-md-surface: #161a1e;
  --three-md-text: #f4f3ef;
  --three-md-muted: #9aa3a8;
  --three-md-hairline: rgba(255, 255, 255, 0.12);
  --three-md-height: 460px;
  --three-md-plane-width: 320px;
}
```

Or target internals with `::part()`: `stage`, `scene`, `plane`, `plane-title`,
`plane-body`, `controls`, `scrubber`, `prev`, `next`, `readout`, `axis`, `hint`.

## Guarantees

The component is tested in CI (`uitests/`) in both Chromium and WebKit:

- the focused plane is frontmost in true Z while scrubbing (so it is correct in
  Safari, which paints by Z and ignores `z-index` inside `preserve-3d`),
- it works with `requestAnimationFrame` paused (iOS Low Power Mode),
- it does not overflow horizontally from 320px to 1440px,
- the console stays clean.

## License

MIT (c) CorvidLabs.
