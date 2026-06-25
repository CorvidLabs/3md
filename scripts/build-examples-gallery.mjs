// Build web/examples-gallery.3md: one plane per example, each showing the
// example's animated GIF (web/gifs/<slug>.gif) via 3md's image support. View it
// in the viewer (viewer.html?src=examples-gallery.3md) to flip through animated
// previews of every curated animated example. Run after the GIFs exist:
//   bun scripts/build-examples-gallery.mjs
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const data = JSON.parse(readFileSync("web/gallery-data.json", "utf8"));
let out = `---
3md: 1.0
axis: example
title: 3md Curated Examples Gallery (animated)
view: single
note: each plane shows one curated example as an animated GIF; scrub to flip through them
---
Curated examples, captured in motion. Use the slider or arrows to step through;
the "single card" view shows one at a time. Each frame is a real render of that
example in the <three-md> component or a matching motion card.
`;
let z = 0;
let skipped = 0;
for (const ex of data) {
  if (!existsSync(`web/gifs/${ex.slug}.gif`)) { skipped++; continue; }
  out += `\n@plane z=${z} label=${JSON.stringify(ex.title)} slug=${JSON.stringify(ex.slug)} axis=${JSON.stringify(ex.axis)}\n`;
  out += `## ${ex.title}\n`;
  out += `${ex.axis} - ${ex.slug}\n\n`;
  out += `![${ex.title}](./gifs/${ex.slug}.gif)\n`;
  z++;
}
writeFileSync("web/examples-gallery.3md", out + "\n");
console.log(`examples-gallery.3md: ${z} planes (${skipped} without a gif, skipped)`);
