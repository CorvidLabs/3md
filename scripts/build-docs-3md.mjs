// Combine every Markdown doc in the repo into one navigable 3md file (docs.3md,
// mirrored to web/docs.3md for the hosted viewer). Each doc becomes a plane on
// the "doc" axis. Run from the repo root: `node scripts/build-docs-3md.mjs`.
//
// The source of truth stays the individual .md files (GitHub renders those);
// docs.3md is generated so the docs can be opened in the 3md viewer, since
// GitHub has no native .3md preview.
import { readFileSync, writeFileSync } from "node:fs";

const docs = [
  ["README.md", "README"],
  ["SPEC.md", "SPEC"],
  ["CHANGELOG.md", "CHANGELOG"],
  ["ROADMAP.md", "ROADMAP"],
  ["CONTRIBUTING.md", "CONTRIBUTING"],
  ["SECURITY.md", "SECURITY"],
  ["AGENTS.md", "AGENTS"],
  ["docs/PROOF.md", "PROOF"],
  ["docs/PROPOSALS.md", "PROPOSALS"],
  ["LICENSE", "LICENSE"],
];

let out = `---
3md: 1.0
axis: doc
title: 3md Project Documentation
view: single
note: GENERATED. Open in the 3md viewer, do not read raw. Source = the .md files.
generated: regenerate with scripts/build-docs-3md.mjs - edit the source docs, not this
---
GENERATED FILE - do not read this raw, and do not edit it.

This bundles every prose doc in the repo into one 3md file, one doc per plane,
so they can be scrubbed in the 3md viewer (GitHub cannot preview .3md natively):

    https://corvidlabs.github.io/3md/viewer.html?src=docs.3md

As plain text this is just every doc concatenated end to end, which is hard to
read on purpose. The source of truth is the individual .md files; edit those and
regenerate with \`node scripts/build-docs-3md.mjs\`.
`;

let z = 0;
for (const [path, label] of docs) {
  let body;
  try { body = readFileSync(path, "utf8").replace(/\s+$/, ""); }
  catch { console.warn(`skip (missing): ${path}`); continue; }
  out += `\n@plane z=${z} label=${JSON.stringify(label)} file=${JSON.stringify(path)}\n${body}\n`;
  z++;
}

writeFileSync("docs.3md", out + "\n");
writeFileSync("web/docs.3md", out + "\n");
console.log(`docs.3md + web/docs.3md: ${z} planes`);
