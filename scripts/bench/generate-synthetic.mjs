#!/usr/bin/env node
// Performance-gate input synthetic-2000 (docs/design/threemd-2.1/perf-gate.md, section 2).
//
// Writes DIR/synthetic-2000.3md: a deterministic 2,000-plane mixed-Markdown document built with the ThreeMD
// TypeScript library and written by its legacy serializer. The output is checked against a pinned SHA-256 and size
// before anything is written, so the document never drifts. The document content, including the metadata value
// "ts-bench/generate-synthetic.mjs" from the design study where this generator started, is part of that hash and must
// not change.
//
// Run it under Node, the runtime the hash was recorded with. It reads only the text API (parse, serialize and the
// text form of DocumentStorageCodec), which ThreeMD 2.0 and 2.1 share.
//
// Usage: node scripts/bench/generate-synthetic.mjs --out DIR [--library PATH]
// Exit status: 0 when the file was written, 1 when the generated document differs from the pinned hash, 2 when the
// generator cannot run.

import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const EXPECTED = {
  file: "synthetic-2000.3md",
  bytes: 4_037_470,
  sha256: "b64e50d34e2d1fdf4a06d11638bdb1b3cb4cc912d5921f58317f46064de0c459",
};
const USAGE = "Usage: node scripts/bench/generate-synthetic.mjs --out DIR [--library PATH]\n\n" +
  "  --out DIR        Directory that receives synthetic-2000.3md (created when missing).\n" +
  "  --library PATH   Module exporting the ThreeMD TypeScript API (default: js/dist/index.js).";

// MARK: - Arguments

function cannotRun(message) {
  console.error(`generate-synthetic.mjs: ${message}`);
  process.exit(2);
}

const options = { out: null, library: join(ROOT, "js/dist/index.js") };
{
  const args = process.argv.slice(2);
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--out" || argument === "--library") {
      const value = args[index + 1];
      if (value === undefined) cannotRun(`${argument} needs a value.\n\n${USAGE}`);
      options[argument.slice(2)] = resolve(value);
      index += 1;
    } else if (argument === "--help" || argument === "-h") {
      console.log(USAGE);
      process.exit(0);
    } else {
      cannotRun(`unknown argument ${argument}\n\n${USAGE}`);
    }
  }
  if (options.out === null) cannotRun(`--out is required.\n\n${USAGE}`);
}

let library;
try {
  library = await import(pathToFileURL(options.library).href);
} catch (error) {
  cannotRun(`cannot load ${options.library} (${error.message}). Build the library first: (cd js && bun run build).`);
}
const { DocumentStorageCodec, DocumentStorageFormat, parse, serialize } = library;

// MARK: - Document

let seed = 0x3d3d2000;
function random() {
  seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (items) => items[Math.floor(random() * items.length)];
const between = (low, high) => low + Math.floor(random() * (high - low + 1));
const WORDS = ("plane axis layer depth time frame space markdown render vector anchor link node edge graph " +
  "stack slice index record schema codec binary text parse decode encode checksum header payload buffer " +
  "stream bounded limit canonical quoted scalar value field key glyph source bundle resolve village tower " +
  "tree house orbit signal noise quartz harbor lantern meadow cobalt ember willow summit raven corvid " +
  "café naïve résumé façade jalapeño 日本語 東京 データ 文書 Ωmega αβγ ünïcödé 🙂 🚀 ✨").split(" ");
const sentence = (low, high) => {
  const words = Array.from({ length: between(low, high) }, () => pick(WORDS));
  const text = words.join(" ");
  return text.charAt(0).toUpperCase() + text.slice(1) + pick([".", ".", ".", "!", "?"]);
};
const paragraph = () => Array.from({ length: between(2, 6) }, () => {
  let text = sentence(6, 18);
  const roll = random();
  if (roll < 0.15) text += ` See **${pick(WORDS)}** and _${pick(WORDS)}_.`;
  else if (roll < 0.3) text += ` Jump to [[z=${between(0, 1999)}|${pick(WORDS)}]].`;
  else if (roll < 0.4) text += ` Read [the ${pick(WORDS)} notes](https://example.com/${pick(WORDS)}).`;
  else if (roll < 0.5) text += ` Inline \`code ${pick(WORDS)}()\` here.`;
  return text;
}).join(" ");

function block(index) {
  switch (pick(["para", "para", "para", "list", "tasks", "ordered", "code", "table", "quote", "rule", "heading"])) {
    case "para": return [paragraph()];
    case "list": return Array.from({ length: between(3, 6) }, () => `- ${sentence(3, 9)}`);
    case "tasks": return Array.from({ length: between(2, 5) }, () => `- [${random() < 0.5 ? "x" : " "}] ${sentence(3, 8)}`);
    case "ordered": return Array.from({ length: between(3, 5) }, (_, item) => `${item + 1}. ${sentence(4, 10)}`);
    case "code": {
      const fence = random() < 0.8 ? "```" : "~~~";
      const lines = [`${fence}${pick(["swift", "ts", "rust", "json", "text", ""])}`];
      for (let line = 0; line < between(3, 8); line += 1) {
        lines.push(random() < 0.08 ? `@plane z=${index}.5 label="inside a fence"` :
          `  let ${pick(WORDS).replace(/[^a-z]/g, "") || "value"}${line} = "${pick(WORDS)}" // ${pick(WORDS)} \\ "quoted"`);
      }
      lines.push(fence);
      return lines;
    }
    case "table": {
      const lines = ["| key | value | note |", "| --- | ---: | :--- |"];
      for (let row = 0; row < between(2, 5); row += 1) lines.push(`| ${pick(WORDS)} | ${between(0, 99999)} | ${sentence(2, 6)} |`);
      return lines;
    }
    case "quote": return [`> ${sentence(6, 16)}`, `> ${sentence(6, 16)}`];
    case "rule": return ["---"];
    default: return [`${"#".repeat(between(2, 4))} ${sentence(2, 6)}`];
  }
}

const planes = [];
for (let index = 0; index < 2000; index += 1) {
  const lines = [`# ${sentence(2, 5).replace(/[.!?]$/, "")} ${index}`];
  const blocks = between(6, 12);
  for (let count = 0; count < blocks; count += 1) { lines.push(""); lines.push(...block(index)); }
  const attributes = Object.create(null);
  if (random() < 0.5) attributes.kind = pick(["note", "scene", "step", "frame", "slide"]);
  if (random() < 0.3) attributes.tags = `${pick(WORDS)},${pick(WORDS)}`;
  if (random() < 0.1) attributes.quote = `say "${pick(WORDS)}" \\ ok`;
  planes.push({
    z: index % 7 === 0 ? index + 0.25 : index,
    label: random() < 0.85 ? `Plane ${index}: ${sentence(1, 4).replace(/[.!?]$/, "")}${random() < 0.1 ? ' "quoted"' : ""}` : null,
    x: random() < 0.2 ? Math.round(random() * 1000) / 10 : null,
    y: random() < 0.2 ? -Math.round(random() * 1000) / 4 : null,
    attributes,
    body: lines.join("\n"),
  });
}
const document = {
  version: "1.1", axis: "depth", title: "Synthetic 2,000-plane load benchmark",
  metadata: { author: "load-benchmarks", generator: "ts-bench/generate-synthetic.mjs", seed: "0x3d3d2000" },
  preamble: "A deterministic mixed-Markdown document for comparing text and binary load times.",
  planes,
};

// MARK: - Check and write

const original = serialize(document);
const reparsed = parse(original);
if (reparsed.planes.length !== 2000) {
  console.error(`generate-synthetic.mjs: expected 2000 planes, got ${reparsed.planes.length}`);
  process.exit(1);
}
const bytes = new TextEncoder().encode(original);
const sha256 = createHash("sha256").update(bytes).digest("hex");
if (sha256 !== EXPECTED.sha256 || bytes.byteLength !== EXPECTED.bytes) {
  console.error(`generate-synthetic.mjs: the generated document differs from the pinned input: ${bytes.byteLength} B, ` +
    `SHA-256 ${sha256}; expected ${EXPECTED.bytes} B, SHA-256 ${EXPECTED.sha256}. Nothing was written.`);
  process.exit(1);
}
const canonical = DocumentStorageCodec.encode(DocumentStorageCodec.decode(bytes), DocumentStorageFormat.text);
mkdirSync(options.out, { recursive: true });
const path = join(options.out, EXPECTED.file);
writeFileSync(path, bytes);
console.log(JSON.stringify({
  path, bytes: bytes.byteLength, lines: original.split("\n").length, planes: reparsed.planes.length,
  canonicalBytes: canonical.byteLength, sha256,
}));
