#!/usr/bin/env node
// Performance-gate input sculpt-4096 (docs/design/threemd-2.1/perf-gate.md, section 2).
//
// Writes DIR/sculpt-4096.3md: a deterministic Sculpt-style voxel export of 4,096 layers of 32 x 20 ASCII voxels, each
// with a label and three attributes, built with the ThreeMD TypeScript library and written by its legacy serializer.
// 32 x 20 (not 32 x 32) keeps the canonical text under the 100,000-line DocumentDecodeLimits.standard ceiling. The
// output is checked against a pinned SHA-256 and size before anything is written. The document content, including
// the metadata value "proto-speed/tools/generate-sculpt.mjs" from the design study where this generator started, is
// part of that hash and must not change.
//
// Run it under Node: the voxel radius uses Math.sin, which ECMAScript does not specify bit for bit across engines,
// and the hash was recorded with Node. It reads only the text API (serialize and the text form of
// DocumentStorageCodec), which ThreeMD 2.0 and 2.1 share.
//
// Usage: node scripts/bench/generate-sculpt.mjs --out DIR [--library PATH]
// Exit status: 0 when the file was written, 1 when the generated document differs from the pinned hash, 2 when the
// generator cannot run.

import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const EXPECTED = {
  file: "sculpt-4096.3md",
  bytes: 3_031_335,
  sha256: "dae524d9ea9bab4a027b9213082c19eb2621ff788890a6f25eb20bddd4ea667d",
};
const USAGE = "Usage: node scripts/bench/generate-sculpt.mjs --out DIR [--library PATH]\n\n" +
  "  --out DIR        Directory that receives sculpt-4096.3md (created when missing).\n" +
  "  --library PATH   Module exporting the ThreeMD TypeScript API (default: js/dist/index.js).";

// MARK: - Arguments

function cannotRun(message) {
  console.error(`generate-sculpt.mjs: ${message}`);
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
const { DocumentStorageCodec, DocumentStorageFormat, serialize } = library;

// MARK: - Document

let seed = 0x5c0197;
function random() {
  seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const WIDTH = 32, HEIGHT = 20, LAYERS = 4096;
const MATERIALS = ["stone", "dirt", "glass", "wood", "metal", "air"];
const planes = [];
for (let layer = 0; layer < LAYERS; layer += 1) {
  const phase = layer / LAYERS;
  const radius = 4 + 9 * Math.abs(Math.sin(phase * Math.PI * 6));
  const rows = [];
  for (let row = 0; row < HEIGHT; row += 1) {
    let line = "";
    for (let column = 0; column < WIDTH; column += 1) {
      const dx = column - WIDTH / 2 + 0.5, dy = (row - HEIGHT / 2 + 0.5) * 1.6;
      const distance = Math.sqrt(dx * dx + dy * dy);
      const noise = random();
      line += distance < radius - 1 ? (noise < 0.08 ? "o" : "#") : distance < radius ? (noise < 0.5 ? "+" : "*") : noise < 0.02 ? "," : ".";
    }
    rows.push(line);
  }
  const attributes = Object.create(null);
  attributes.material = MATERIALS[Math.floor(random() * MATERIALS.length)];
  attributes.opacity = String(Math.round(random() * 100) / 100);
  attributes.visible = random() < 0.9 ? "true" : "false";
  planes.push({ z: layer, label: `Layer ${String(layer).padStart(4, "0")}`, x: null, y: null, attributes, body: rows.join("\n") });
}
const document = {
  version: "1.0", axis: "layer", title: "Sculpt voxel export (4,096 layers)",
  metadata: { generator: "proto-speed/tools/generate-sculpt.mjs", grid: `${WIDTH}x${HEIGHT}x${LAYERS}`, palette: ".,+*#o" },
  preamble: null, planes,
};

// MARK: - Check and write

const text = serialize(document);
const bytes = new TextEncoder().encode(text);
const sha256 = createHash("sha256").update(bytes).digest("hex");
if (sha256 !== EXPECTED.sha256 || bytes.byteLength !== EXPECTED.bytes) {
  console.error(`generate-sculpt.mjs: the generated document differs from the pinned input: ${bytes.byteLength} B, ` +
    `SHA-256 ${sha256}; expected ${EXPECTED.bytes} B, SHA-256 ${EXPECTED.sha256}. Nothing was written.`);
  process.exit(1);
}
const canonical = DocumentStorageCodec.encode(DocumentStorageCodec.decode(bytes), DocumentStorageFormat.text);
mkdirSync(options.out, { recursive: true });
const path = join(options.out, EXPECTED.file);
writeFileSync(path, bytes);
console.log(JSON.stringify({
  path, bytes: bytes.byteLength, lines: text.split("\n").length, planes: planes.length,
  canonicalBytes: canonical.byteLength, sha256,
}));
