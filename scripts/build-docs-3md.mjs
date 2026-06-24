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
note: every Markdown doc in the repo, combined into one navigable 3md file
generated: regenerate with scripts/build-docs-3md.mjs - edit the source docs, not this
---
The whole documentation set as a single 3md document: each plane is one of the
repo's docs. Scrub the Z axis to move between them. This is 3md used on itself.
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
