#!/usr/bin/env node
// ThreeMD 2.1 structured fixture generator (payload kind 2, SPEC 11.3).
//
// Rebuilds every committed structured fixture from the built TypeScript library, then either compares the result
// with the committed files (--check, the default) or writes it (--write). The generator is never the only source of
// truth: the Swift and Rust ports reproduce the same bytes in their own tests.
//
// Outputs (paths relative to the repository root):
//   conformance/structured/<id>.3mdb                  the interchange anchors without an extension source
//   conformance/structured/worked-*.3mdb              the three SPEC 11.3.17 worked examples
//   conformance/structured/invalid/*.3mdb             hostile and edge vectors, one file each
//   conformance/structured/limits/*.3mdb              limit-edge vectors (several share one file)
//   conformance/structured/manifest.json              schema 3md-structured-golden-1
//   conformance/structured/vectors.json               schema 3md-structured-vectors-1
//   conformance/structured/sizes.json                 G6 sizes (perf-gate section 4)
//   conformance/extensions/*.structured.3mdb          the four extension anchors
//   conformance/extensions/numeric-powers.json        schema 3md-canonical-numbers-1
//   Examples/Extensions/*.structured.3mdb             canopy and shared-grove
//   conformance/interchange/invalid-binary-kind-3.3mdb
//
// Inputs: conformance/interchange/manifest.json and the sources it names, Examples/*.3md,
// conformance/interchange/invalid-binary-kind.3mdb, scripts/structured/unicode-13.0-assigned.json, and for sizes.json
// the synthetic-2000.3md and sculpt-4096.3md inputs of the performance gate.
//
// Runs under Node or Bun with no dependency. Exit status: 0 when every file matches (or was written), 1 when a file
// differs or an expectation fails, 2 when the generator cannot run.
//
// "test-plan section N" below means docs/design/threemd-2.1/test-plan.md and "perf-gate section N" means
// docs/design/threemd-2.1/perf-gate.md.

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const USAGE = `Usage: node scripts/structured/generate.mjs [--check | --write] [--library PATH] [--inputs DIR]

  --check          Regenerate in memory and compare bytes and SHA-256 with the committed files (default).
  --write          Regenerate and write every output; remove committed structured files nobody generates.
  --library PATH   Module exporting the ThreeMD TypeScript API (default: js/dist/index.js).
  --inputs DIR     Directory holding synthetic-2000.3md and sculpt-4096.3md for sizes.json
                   (default: bench/inputs, else generated with scripts/bench/generate-*.mjs when present).

Build the library first: (cd js && bun run build).`;

// MARK: - Arguments

function cannotRun(message) {
  console.error(`generate.mjs: ${message}`);
  process.exit(2);
}

function parseArguments(args) {
  const result = { mode: null, library: join(ROOT, "js/dist/index.js"), inputs: null };
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--check" || argument === "--write") {
      const mode = argument.slice(2);
      if (result.mode !== null && result.mode !== mode) cannotRun("--check and --write cannot be combined.");
      result.mode = mode;
    } else if (argument === "--library" || argument === "--inputs") {
      const value = args[index + 1];
      if (value === undefined) cannotRun(`${argument} needs a value.\n\n${USAGE}`);
      result[argument.slice(2)] = resolve(value);
      index += 1;
    } else if (argument === "--help" || argument === "-h") {
      console.log(USAGE);
      process.exit(0);
    } else {
      cannotRun(`unknown argument ${argument}\n\n${USAGE}`);
    }
  }
  result.mode ??= "check";
  return result;
}

const options = parseArguments(process.argv.slice(2));

// MARK: - Library

/** Loads the TypeScript library and refuses to continue unless it writes payload kind 2. */
async function loadLibrary(path) {
  const shown = relative(ROOT, path).startsWith("..") ? path : relative(ROOT, path);
  if (!existsSync(path)) {
    cannotRun(`${shown} does not exist. Build the TypeScript library first: (cd js && bun run build).`);
  }
  const library = await import(pathToFileURL(path).href);
  const codec = library.DocumentStorageCodec;
  const missing = [];
  if (typeof codec?.encodeTextContainer !== "function") missing.push("DocumentStorageCodec.encodeTextContainer");
  if (typeof codec?.containerInfo !== "function") missing.push("DocumentStorageCodec.containerInfo");
  if (!Array.isArray(codec?.supportedPayloadKinds) || !codec.supportedPayloadKinds.includes(2)) {
    missing.push("DocumentStorageCodec.supportedPayloadKinds containing 2");
  }
  if (missing.length > 0) {
    cannotRun(`the TypeScript library at ${shown} has no payload kind 2 writer (ThreeMD 2.1, SPEC 11.3). Missing: ` +
      `${missing.join(", ")}. The structured fixtures can only be regenerated once the TypeScript port is built ` +
      "into js/dist: (cd js && bun run build).");
  }
  const probe = { version: "1", axis: "", title: null, metadata: Object.create(null), preamble: null, planes: [] };
  const info = codec.containerInfo(codec.encode(probe, library.DocumentStorageFormat.binary()));
  if (info?.payloadKind !== 2) {
    cannotRun(`DocumentStorageFormat.binary() in ${shown} writes payload kind ${String(info?.payloadKind)}, not 2. ` +
      "Rebuild the TypeScript library from the ThreeMD 2.1 sources: (cd js && bun run build).");
  }
  return library;
}

const library = await loadLibrary(options.library);
const {
  DocumentCompositionCodec, DocumentCompositionLimits, DocumentDecodeLimits, DocumentStorageCodec, DocumentStorageFormat,
} = library;

// MARK: - Helpers

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const problems = [];
const outputs = new Map(); // repository path -> bytes

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const hex = (bytes) => Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
const code = (operation) => {
  try {
    operation();
    return "ok";
  } catch (error) {
    return error?.code ?? `throw:${String(error)}`;
  }
};
const read = (path) => new Uint8Array(readFileSync(join(ROOT, path)));
const rec = (entries) => {
  const out = Object.create(null);
  for (const [key, value] of entries) out[key] = value;
  return out;
};
const sameBytes = (left, right) => left.byteLength === right.byteLength && left.every((byte, index) => byte === right[index]);
const u32 = (bytes, offset) => new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(offset, true);
const crcField = (bytes) => u32(bytes, 36).toString(16).padStart(8, "0");

function addOutput(path, bytes) {
  const existing = outputs.get(path);
  if (existing !== undefined && !sameBytes(existing, bytes)) problems.push(`${path}: generated twice with different bytes`);
  outputs.set(path, bytes);
}

const sameMap = (a, b) => {
  const x = Object.keys(a).sort();
  const y = Object.keys(b).sort();
  return x.length === y.length && x.every((key, index) => key === y[index] && a[key] === b[key]);
};
const samePlane = (a, b) => Object.is(a.z, b.z) && Object.is(a.x, b.x) && Object.is(a.y, b.y) &&
  a.label === b.label && a.body === b.body && sameMap(a.attributes, b.attributes);
const sameDocument = (a, b) => a.version === b.version && a.axis === b.axis && a.title === b.title &&
  a.preamble === b.preamble && sameMap(a.metadata, b.metadata) && a.planes.length === b.planes.length &&
  a.planes.every((plane, index) => samePlane(plane, b.planes[index]));

const BINARY = DocumentStorageFormat.binary();
const encodeStructured = (document, limits = DocumentDecodeLimits.standard) =>
  DocumentStorageCodec.encode(document, BINARY, limits);
const decode = (bytes, limits = DocumentDecodeLimits.standard) => DocumentStorageCodec.decode(bytes, limits);
const profileLimits = new DocumentDecodeLimits({
  maximumEncodedBytes: DocumentCompositionLimits.standard.maximumProfileBytes,
  maximumDecodedBytes: DocumentCompositionLimits.standard.maximumProfileBytes, maximumPlanes: 1,
  maximumRecordBytes: DocumentCompositionLimits.standard.maximumProfileBytes,
});

// MARK: - Container (SPEC 11.1), independent of the library, for hand-built vectors

const MAGIC = [0x33, 0x6d, 0x64, 0x62, 0x69, 0x6e, 0x0d, 0x0a];
let crcTable = null;
function crcUpdate(crc, bytes, start, end) {
  if (crcTable === null) {
    crcTable = new Uint32Array(256);
    for (let index = 0; index < 256; index += 1) {
      let value = index;
      for (let bit = 0; bit < 8; bit += 1) value = value & 1 ? (value >>> 1) ^ 0xedb88320 : value >>> 1;
      crcTable[index] = value >>> 0;
    }
  }
  for (let index = start; index < end; index += 1) crc = (crcTable[(crc ^ bytes[index]) & 0xff] ^ (crc >>> 8)) >>> 0;
  return crc;
}
/** CRC-32/ISO-HDLC over header bytes 0..<36 and the payload from byte 40. */
function checksum(bytes) {
  return (crcUpdate(crcUpdate(0xffffffff, bytes, 0, 36), bytes, 40, bytes.byteLength) ^ 0xffffffff) >>> 0;
}
/** A complete container around a payload: version 1, the given kind, compression 0, lengths and CRC sealed. */
function seal(payloadBytes, kind = 2) {
  const output = new Uint8Array(40 + payloadBytes.byteLength);
  output.set(MAGIC, 0);
  output.set(payloadBytes, 40);
  const view = new DataView(output.buffer);
  view.setUint16(8, 1, true);
  output[10] = kind;
  view.setBigUint64(20, BigInt(payloadBytes.byteLength), true);
  view.setBigUint64(28, BigInt(payloadBytes.byteLength), true);
  view.setUint32(36, checksum(output), true);
  return output;
}
const hasMagic = (bytes) => bytes.byteLength >= 8 && MAGIC.every((byte, index) => bytes[index] === byte);

/**
 * The outcome of a ThreeMD 2.0.0 reader. Its container steps (SPEC 1.1, 11.1) check the input size, the header
 * length, the version and then accept payload kind 1 only, so every vector stops at one of those steps. The 2.0.0
 * compatibility job confirms these values against the real 2.0.0 readers.
 */
function outcome20(bytes, limits, where) {
  if (bytes.byteLength > limits.maximumEncodedBytes) return "oversizedInput";
  if (!hasMagic(bytes)) {
    problems.push(`${where}: not a binary container; the 2.0.0 outcome would need the text parser`);
    return "unknown";
  }
  if (bytes.byteLength < 40) return "invalidContainer";
  if (new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint16(8, true) !== 1) {
    return "unsupportedVersion";
  }
  if (bytes[10] !== 1) return "unsupportedPayloadKind";
  problems.push(`${where}: payload kind 1; the 2.0.0 outcome cannot be derived from the header`);
  return "unknown";
}

/** containerInfo must report the raw header of a kind-2 anchor (test-plan section 1, check 4). */
function checkContainerInfo(where, bytes) {
  const info = DocumentStorageCodec.containerInfo(bytes);
  const length = BigInt(bytes.byteLength - 40);
  if (info === null || info.containerVersion !== 1 || info.payloadKind !== 2 || info.compression !== 0 ||
    info.flags !== 0 || info.reserved !== 0 || info.encodedPayloadByteCount !== length ||
    info.decodedPayloadByteCount !== length || info.checksum !== u32(bytes, 36) || info.checksum !== checksum(bytes)) {
    problems.push(`${where}: containerInfo does not describe an uncompressed kind-2 file with a valid CRC`);
  }
}

// MARK: - Unicode 13.0 assigned set (SPEC 11.3.15)

const UNICODE_FILE = "scripts/structured/unicode-13.0-assigned.json";
const assigned = (() => {
  const table = JSON.parse(decoder.decode(read(UNICODE_FILE)));
  const ranges = table.ranges;
  let count = 0;
  let previous = -2;
  let ordered = Array.isArray(ranges);
  for (const [first, last] of ordered ? ranges : []) {
    if (!(Number.isInteger(first) && Number.isInteger(last) && first > previous + 1 && last >= first && last <= 0x10ffff)) {
      ordered = false;
    }
    count += last - first + 1;
    previous = last;
  }
  if (table.schema !== "3md-unicode-assigned-1" || table.unicodeVersion !== "13.0.0" || !ordered ||
    table.rangeCount !== ranges.length || table.codePointCount !== count ||
    table.rangesSha256 !== sha256(encoder.encode(JSON.stringify(ranges)))) {
    problems.push(`${UNICODE_FILE}: schema, counts, order or rangesSha256 do not match its ranges`);
  }
  return (codePoint) => {
    let low = 0;
    let high = ordered ? ranges.length - 1 : -1;
    while (low <= high) {
      const middle = (low + high) >>> 1;
      const [first, last] = ranges[middle];
      if (codePoint < first) high = middle - 1;
      else if (codePoint > last) low = middle + 1;
      else return true;
    }
    return false;
  };
})();

function checkString(where, value) {
  for (const character of value) {
    const codePoint = character.codePointAt(0);
    if (!assigned(codePoint)) {
      const label = codePoint.toString(16).toUpperCase().padStart(4, "0");
      problems.push(`${where}: U+${label} is outside the Unicode 13.0 assigned set (${UNICODE_FILE})`);
    }
  }
}
function checkDocumentStrings(where, document) {
  const strings = [document.version, document.axis, document.title, document.preamble];
  for (const [key, value] of Object.entries(document.metadata)) strings.push(key, value);
  for (const plane of document.planes) {
    strings.push(plane.label, plane.body);
    for (const [key, value] of Object.entries(plane.attributes)) strings.push(key, value);
  }
  for (const value of strings) if (typeof value === "string") checkString(where, value);
}
function checkJSONStrings(where, value) {
  if (typeof value === "string") checkString(where, value);
  else if (Array.isArray(value)) for (const item of value) checkJSONStrings(where, item);
  else if (value !== null && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) {
      checkString(where, key);
      checkJSONStrings(where, item);
    }
  }
}

// MARK: - Valid anchors (test-plan section 1)

const files = [];
const kind2Path = (set, id) => {
  if (set === "examples") return `Examples/Extensions/${id}.structured.3mdb`;
  if (set === "interchange" && id.startsWith("extension-")) {
    return `conformance/extensions/${id.slice("extension-".length)}.structured.3mdb`;
  }
  return `conformance/structured/${id}.3mdb`;
};

function addGolden(id, set, kind, sourceFile, extra = {}) {
  const source = read(sourceFile);
  let document;
  let canonical;
  if (kind === "composition") {
    const composition = DocumentCompositionCodec.decode(source);
    document = DocumentCompositionCodec.document(composition);
    canonical = DocumentCompositionCodec.encode(composition);
  } else {
    document = DocumentStorageCodec.decode(source);
    canonical = DocumentStorageCodec.encode(document);
  }
  const expected = DocumentStorageCodec.decode(canonical);
  const bytes = encodeStructured(document, kind === "composition" ? profileLimits : DocumentDecodeLimits.standard);
  if (!sameBytes(bytes, encodeStructured(expected))) {
    problems.push(`${id}: encoding the source document and its canonical decode differ`);
  }
  const decoded = decode(bytes);
  if (!sameDocument(decoded, expected)) problems.push(`${id}: kind-2 decode differs from the bounded text decode`);
  if (!sameBytes(encodeStructured(decoded), bytes)) problems.push(`${id}: re-encoding the decoded document differs (P2)`);
  checkContainerInfo(id, bytes);
  checkDocumentStrings(id, expected);
  if (kind === "composition") {
    const viaEnvelope = DocumentCompositionCodec.decode(bytes);
    const original = DocumentCompositionCodec.decode(source);
    if (!sameBytes(DocumentCompositionCodec.encode(viaEnvelope), DocumentCompositionCodec.encode(original))) {
      problems.push(`${id}: the composition decoded from the kind-2 envelope differs`);
    }
  }
  if (extra.textContainerFile !== undefined) {
    const anchor = read(extra.textContainerFile);
    if (!sameDocument(decode(anchor), expected)) problems.push(`${id}: the kind-1 anchor decodes to another document`);
    if (!sameBytes(DocumentStorageCodec.encodeTextContainer(document), anchor)) {
      problems.push(`${id}: encodeTextContainer differs from ${extra.textContainerFile}`);
    }
  }
  const kind2File = kind2Path(set, id);
  addOutput(kind2File, bytes);
  files.push({
    id, set, kind, sourceFile, ...extra, kind2File, bytes: bytes.byteLength, payloadBytes: bytes.byteLength - 40,
    canonicalBytes: canonical.byteLength, sha256: sha256(bytes), crc32: crcField(bytes), planes: expected.planes.length,
    compositionEnvelope: kind === "composition",
  });
}

const catalog = JSON.parse(decoder.decode(read("conformance/interchange/manifest.json")));
// Catalog schema 1 names the kind-1 anchor binaryFile; schema 2 renames it textContainerFile and uses binaryFile for
// the kind-2 anchor (test-plan section 6).
const catalogVersion2 = catalog.schema !== "3md-interchange-catalog-1";
const extensionSources = {
  "extension-document-unicode": "conformance/extensions/document-unicode.3md",
  "extension-unicode-key-order": "conformance/extensions/unicode-key-order.3md",
  "extension-unicode-source-collision": "conformance/extensions/unicode-source-collision.3md",
  "extension-composition-instances": "conformance/extensions/composition-instances.3md",
};
for (const item of catalog.cases) {
  if (item.expectedError !== undefined) continue;
  const textContainerFile = catalogVersion2 ? item.textContainerFile : item.binaryFile;
  if (catalogVersion2 && item.binaryFile !== kind2Path("interchange", item.id)) {
    problems.push(`${item.id}: catalog binaryFile ${String(item.binaryFile)} is not ${kind2Path("interchange", item.id)}`);
  }
  addGolden(item.id, "interchange", item.kind, item.sourceFile, {
    ...(textContainerFile !== undefined ? { textContainerFile } : {}),
    ...(extensionSources[item.id] !== undefined ? { extensionSourceFile: extensionSources[item.id] } : {}),
  });
}
addGolden("canopy", "examples", "document", "Examples/Extensions/canopy.3md",
  { textContainerFile: "Examples/Extensions/canopy.3mdb" });
addGolden("shared-grove", "examples", "composition", "Examples/Extensions/shared-grove.3md",
  { textContainerFile: "Examples/Extensions/shared-grove.3mdb" });

// MARK: - Worked examples (SPEC 11.3.17)

const WORKED_CRC = { document: "8a5b3b70", numbers: "db5a2326", keys: "649eb26b" };
function addWorked(name, document) {
  const bytes = encodeStructured(document);
  const canonical = DocumentStorageCodec.encode(document);
  if (!sameDocument(decode(bytes), DocumentStorageCodec.decode(canonical))) problems.push(`worked ${name}: decode differs`);
  if (crcField(bytes) !== WORKED_CRC[name]) problems.push(`worked ${name}: CRC ${crcField(bytes)}, SPEC says ${WORKED_CRC[name]}`);
  checkContainerInfo(`worked ${name}`, bytes);
  checkDocumentStrings(`worked ${name}`, document);
  const kind2File = `conformance/structured/worked-${name}.3mdb`;
  addOutput(kind2File, bytes);
  files.push({
    id: `worked-${name}`, set: "worked", kind: "document", sourceFile: `(spec 11.3.17 ${name})`, kind2File,
    bytes: bytes.byteLength, payloadBytes: bytes.byteLength - 40, canonicalBytes: canonical.byteLength,
    sha256: sha256(bytes), crc32: crcField(bytes), planes: document.planes.length, compositionEnvelope: false,
  });
}
const plane = (z, body, extra = {}) => ({ z, label: null, x: null, y: null, attributes: rec([]), body, ...extra });
addWorked("document", DocumentStorageCodec.decode(encoder.encode(
  "---\n3md: \"1.0\"\naxis: \"time\"\ntitle: \"Week\"\nowner: \"ops\"\n---\n\n@plane z=0 label=\"Mon\"\n# Standup\n\n" +
  "@plane z=1.5 label=\"Tue\" x=-2 kind=\"note\"\nShip it\n")));
addWorked("numbers", {
  version: "1.0", axis: "layer", title: null, metadata: rec([]), preamble: null,
  planes: [plane(0.1, "", { x: 0.5, y: 268435456, attributes: rec([["note", "say \"hi\""]]) })],
});
addWorked("keys", {
  version: "1", axis: "", title: null, metadata: rec([["z", "1"], ["e\u0301", "2"]]), preamble: null,
  planes: [plane(-3, "", { attributes: rec([["b", "x"], ["a", "y"]]) })],
});

// MARK: - Byte builder for vectors

const V = (value) => {
  const out = [];
  while (value >= 0x80) {
    out.push((value & 0x7f) | 0x80);
    value >>>= 7;
  }
  out.push(value);
  return out;
};
const S = (value) => {
  if (typeof value === "string") {
    checkString("vector string", value);
    const bytes = encoder.encode(value);
    return [...V(bytes.byteLength), ...bytes];
  }
  if (value instanceof Uint8Array) return [...V(value.byteLength), ...value];
  return value.raw;
};
const F32 = (value) => {
  const view = new DataView(new ArrayBuffer(4));
  view.setFloat32(0, value, true);
  return [...new Uint8Array(view.buffer)];
};
const F64 = (value) => {
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, value, true);
  return [...new Uint8Array(view.buffer)];
};
const ZZ = (value) => V(((value << 1) ^ (value >> 31)) >>> 0);
/** The canonical number form of SPEC 11.3.3 (TypeScript exactness tests). */
const formOf = (value) => {
  if (Number.isInteger(value) && value >= -134_217_728 && value <= 134_217_727) return 1;
  return Math.fround(value) === value ? 2 : 3;
};
/** A number spec is a value (canonical form), [form, value] or [form, raw bytes]. */
const numberBytes = (spec) => {
  if (typeof spec === "number") {
    const form = formOf(spec);
    return { form, bytes: form === 1 ? ZZ(spec) : form === 2 ? F32(spec) : F64(spec) };
  }
  const [form, value] = spec;
  if (Array.isArray(value)) return { form, bytes: value };
  return { form, bytes: form === 1 ? ZZ(value) : form === 2 ? F32(value) : F64(value) };
};
/** A kind-2 payload from a document spec; strings are JS strings, raw Uint8Array bytes or { raw } byte arrays. */
function payload(spec) {
  const out = [];
  out.push(spec.flags ?? ((spec.title !== undefined ? 1 : 0) | (spec.preamble !== undefined ? 2 : 0)));
  out.push(...S(spec.version), ...S(spec.axis));
  if (spec.title !== undefined) out.push(...S(spec.title));
  const metadata = spec.metadata ?? [];
  out.push(...V(spec.metadataCount ?? metadata.length));
  for (const [key, value] of metadata) out.push(...S(key), ...S(value));
  if (spec.preamble !== undefined) out.push(...S(spec.preamble));
  out.push(...V(spec.planeCount ?? spec.planes.length));
  for (const p of spec.planes) {
    const z = numberBytes(p.z);
    const x = p.x === undefined ? null : numberBytes(p.x);
    const y = p.y === undefined ? null : numberBytes(p.y);
    out.push(p.flags ?? (z.form | ((x?.form ?? 0) << 2) | ((y?.form ?? 0) << 4) | (p.label !== undefined ? 0x40 : 0)));
    out.push(...z.bytes);
    if (x !== null) out.push(...x.bytes);
    if (y !== null) out.push(...y.bytes);
    if (p.label !== undefined) out.push(...S(p.label));
    const attributes = p.attributes ?? [];
    out.push(...V(p.attributeCount ?? attributes.length));
    for (const [key, value] of attributes) out.push(...S(key), ...S(value));
    out.push(...S(p.body));
  }
  out.push(...(spec.trailing ?? []));
  return new Uint8Array(out);
}
/** The Document a structurally valid spec describes, for the validate cross-check; null otherwise. */
function documentOf(spec) {
  const text = (value) => value === undefined ? null : typeof value === "string" ? value : undefined;
  const value = (number) => {
    if (number === undefined) return null;
    if (typeof number === "number") return number;
    return Array.isArray(number[1]) ? undefined : number[1];
  };
  const strings = (pairs) => {
    const out = Object.create(null);
    for (const [key, item] of pairs ?? []) {
      if (typeof key !== "string" || typeof item !== "string") return undefined;
      out[key] = item;
    }
    return out;
  };
  const version = text(spec.version);
  const axis = text(spec.axis);
  const title = text(spec.title);
  const preamble = text(spec.preamble);
  const metadata = strings(spec.metadata);
  if (version == null || axis == null || title === undefined || preamble === undefined || metadata === undefined) {
    return null;
  }
  const planes = [];
  for (const p of spec.planes) {
    const z = value(p.z);
    const x = value(p.x);
    const y = value(p.y);
    const label = text(p.label);
    const body = text(p.body);
    const attributes = strings(p.attributes);
    if (z == null || x === undefined || y === undefined || label === undefined || body == null || attributes === undefined) {
      return null;
    }
    planes.push({ z, label, x, y, attributes, body });
  }
  return { version, axis, title, metadata, preamble, planes };
}

// MARK: - Vectors (test-plan section 2)

const vectors = [];
const limitVectors = [];
const BASE = { version: "1", axis: "", planes: [{ z: 0, body: "a" }] };
const withPlane = (p, extra = {}) => ({ ...BASE, ...extra, planes: [p] });

function emit(list, dir, name, bytes, expected, rule, description, settings = {}) {
  const file = `conformance/structured/${dir}/${settings.sharedFile ?? `${name}.3mdb`}`;
  if (settings.sharedFile === undefined) addOutput(file, bytes);
  else if (!outputs.has(file) || !sameBytes(outputs.get(file), bytes)) problems.push(`${name}: shared file ${file} differs`);
  const limits = settings.limits === undefined ? DocumentDecodeLimits.standard : new DocumentDecodeLimits(settings.limits);
  const actual = code(() => decode(bytes, limits));
  if (actual !== expected) problems.push(`${dir}/${name}: the TypeScript library gave ${actual}, expected ${expected}`);
  const vector = {
    name, file, rule, description, ...(settings.limits ? { limits: settings.limits } : {}), expected,
    expected20: outcome20(bytes, limits, name), errorType: expected === "ok" ? "none" : "DocumentStorageError",
    ...(settings.requiresNoLZFSE ? { requiresNoLZFSE: true } : {}),
  };
  if (settings.spec !== undefined) {
    const document = documentOf(settings.spec);
    if (document !== null) {
      // TypeScript validate is unchanged in 2.1, so this is the ThreeMD 2.0 text validation outcome.
      const truth = code(() => DocumentStorageCodec.validate(document, limits));
      vector.textValidate20 = truth;
      // Acceptance must agree with validate whenever the bytes are the canonical encoding of that Document.
      const canonicalBytes = code(() => encodeStructured(document, limits)) === "ok" ? encodeStructured(document, limits) : null;
      const isCanonical = canonicalBytes !== null && sameBytes(canonicalBytes, bytes);
      if (isCanonical && (truth === "ok") !== (expected === "ok")) {
        problems.push(`${name}: validate gave ${truth}, expected ${expected}`);
      }
      if (!isCanonical && expected === "ok") problems.push(`${name}: expected ok but the bytes are not the canonical encoding`);
      if (expected === "invalidDocument" && truth === "ok" && !isCanonical && settings.mergedByWriter !== true) {
        // Non-canonical bytes of an otherwise valid Document must fail with a framing code, never invalidDocument.
        problems.push(`${name}: invalidDocument expected for a Document that validate accepts`);
      }
    }
  }
  list.push(vector);
}
const bad = (name, bytes, expected, rule, description, settings = {}) =>
  emit(vectors, "invalid", name, bytes, expected, rule, description, settings);
const doc = (name, spec, expected, rule, description, limits) =>
  bad(name, seal(payload(spec)), expected, rule, description, {
    spec, ...(limits ? { limits } : {}),
    // validate merges canonically equivalent keys and accepts these Documents; the stored map must already be merged,
    // so a payload holding both spellings is invalidDocument.
    ...(rule === "S6b" || rule === "P7a" ? { mergedByWriter: true } : {}),
  });

const base = seal(payload(BASE));
const mutate = (bytes, change, reseal = false) => {
  const copy = bytes.slice();
  const view = new DataView(copy.buffer);
  change(copy, view);
  if (reseal) view.setUint32(36, checksum(copy), true);
  return copy;
};

// Container (SPEC 11.3.2, steps D4 to D13)
bad("container-truncated-header", base.subarray(0, 39), "invalidContainer", "D4", "Magic present, 39 bytes.");
bad("container-version-2", mutate(base, (c) => { c[8] = 2; }, true), "unsupportedVersion", "D5", "Container version 2.");
for (const kind of [0, 3, 4, 255]) {
  bad(`container-kind-${kind}`, mutate(base, (c) => { c[10] = kind; }, true), "unsupportedPayloadKind", "D6",
    kind === 3 ? "Payload kind 3 is reserved in 2.1." : `Reserved payload kind ${kind}.`);
}
bad("container-kind-3-bad-crc", mutate(base, (c) => { c[10] = 3; c[36] ^= 0xff; }), "unsupportedPayloadKind", "D6",
  "Kind 3 with a corrupt CRC: the kind is rejected before the CRC is computed.");
bad("container-compression-2", mutate(base, (c) => { c[11] = 2; }, true), "unsupportedCompression", "D7",
  "Compression identifier 2.");
bad("container-flags", mutate(base, (c, v) => { v.setUint32(12, 1, true); }, true), "unsupportedFlags", "D8", "Flags 1.");
bad("container-reserved", mutate(base, (c, v) => { v.setUint32(16, 1, true); }, true), "nonzeroReserved", "D9",
  "Reserved 1.");
bad("container-decoded-over-emax", mutate(base, (c, v) => { v.setBigUint64(28, BigInt(64 * 1024 * 1024 - 39), true); }, true),
  "oversizedOutput", "D10", "Kind-2 decoded length Emax - 39 under standard limits (the bound is Emax - 40).");
{
  const big = seal(payload({ ...BASE, planes: [{ z: 0, body: "x".repeat(60) }] }));
  const p = big.byteLength - 40; // 71
  const dmax = Math.floor((p - 1) / 2); // 2 * Dmax < payload
  bad("container-decoded-over-2dmax-bad-crc", mutate(big, (c) => { c[36] ^= 0xff; }), "oversizedOutput", "D10",
    `Payload ${p} bytes, maximumDecodedBytes ${dmax}: 2 * Dmax < decoded length is rejected before the CRC.`,
    { limits: { maximumDecodedBytes: dmax } });
  emit(limitVectors, "limits", "bound-2dmax-exact", big, "oversizedOutput", "L4",
    `Payload ${p} bytes with maximumDecodedBytes ${Math.ceil(p / 2)}: passes D10 (2 * Dmax >= payload) and fails L4 (T > Dmax).`,
    { limits: { maximumDecodedBytes: Math.ceil(p / 2) } });
}
bad("container-encoded-zero", mutate(base, (c, v) => { v.setBigUint64(20, 0n, true); }, true), "lengthMismatch", "D11",
  "Encoded length 0.");
bad("container-decoded-zero", mutate(base, (c, v) => { v.setBigUint64(28, 0n, true); }, true), "lengthMismatch", "D11",
  "Decoded length 0.");
bad("container-encoded-mismatch", mutate(base, (c, v) => { v.setBigUint64(20, BigInt(base.byteLength - 39), true); }, true),
  "lengthMismatch", "D11", "Encoded length one more than the bytes present.");
bad("container-uncompressed-lengths-differ",
  mutate(base, (c, v) => { v.setBigUint64(28, BigInt(base.byteLength - 41), true); }, true),
  "lengthMismatch", "D11", "Compression 0 with decoded length one less than encoded.");
{
  const trailing = new Uint8Array(base.byteLength + 1);
  trailing.set(base);
  bad("container-trailing-byte", trailing, "lengthMismatch", "D11", "One unused byte after the declared payload.");
}
bad("container-crc-field", mutate(base, (c) => { c[36] ^= 1; }), "checksumMismatch", "D12", "CRC field flipped.");
bad("container-crc-payload", mutate(base, (c) => { c[c.byteLength - 1] ^= 1; }), "checksumMismatch", "D12",
  "Payload byte flipped, CRC not resealed.");
bad("container-lzfse-portable", mutate(base, (c) => { c[11] = 1; }, true), "compressionUnavailable", "D13",
  "Compression 1 with a valid CRC: ports without LZFSE report compressionUnavailable.", { requiresNoLZFSE: true });

// Var (SPEC 11.3.3)
const raw = (bytes) => seal(new Uint8Array(bytes));
bad("var-non-minimal", raw([0x00, 0x81, 0x00, 0x31, 0x00, 0x00, 0x00]), "invalidContainer", "V3",
  "Version length 1 written as 81 00 (two bytes, last byte 00).");
bad("var-non-minimal-zero", raw([0x00, 0x80, 0x00, 0x00, 0x00, 0x00]), "invalidContainer", "V3", "Version length 80 00.");
bad("var-five-bytes", raw([0x00, 0xff, 0xff, 0xff, 0xff, 0x01, 0x00]), "invalidContainer", "V2",
  "Version length ff ff ff ff 01.");
bad("var-four-continuation-truncated", raw([0x00, 0xff, 0xff, 0xff, 0xff]), "invalidContainer", "V2",
  "Fourth Var byte has its continuation bit and no fifth byte follows: invalidContainer, not lengthMismatch.");
bad("var-truncated", raw([0x00, 0x01, 0x31, 0x00, 0x00, 0x80]), "lengthMismatch", "V1",
  "Plane count Var cut after a continuation byte.");
bad("var-max-length", raw([0x00, 0xff, 0xff, 0xff, 0x7f, 0x31]), "lengthMismatch", "Str1",
  "Version length 2^28 - 1 with one byte remaining.");

// Counts and remaining (SPEC 11.3.3)
bad("count-metadata", raw([0x00, 0x01, 0x31, 0x00, 0x02, 0x00, 0x00, 0x00]), "lengthMismatch", "C",
  "metadataCount 2 with 3 bytes remaining (floor(3 / 2) = 1).");
bad("count-planes", raw([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x80, 0x00, 0x00]), "lengthMismatch", "C",
  "planeCount 1 with 3 bytes remaining after the Var. A reader that measured remaining before the Var would read plane flags 80 and report invalidContainer.");
bad("count-attributes", raw([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x01, 0x00, 0x00]), "lengthMismatch", "C",
  "attributeCount 1 with 2 bytes remaining (floor(2 / 3) = 0).");
bad("count-planes-edge-ok", raw([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00]), "ok", "C",
  "planeCount 1 with exactly 4 bytes remaining is valid (empty body).");
bad("count-planes-over-pmax-and-remaining", raw([0x00, 0x01, 0x31, 0x00, 0x00, 0x02, 0x01, 0x00, 0x00, 0x00]),
  "lengthMismatch", "C",
  "planeCount 2 with 4 bytes remaining after the Var and maximumPlanes 1: Count framing (floor(4 / 4) = 1 < 2) precedes the Pmax check, so the result is lengthMismatch, not tooManyPlanes.",
  { limits: { maximumPlanes: 1 } });
bad("str-remaining-plus-one", raw([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x02, 0x61]), "lengthMismatch",
  "Str1", "Body length 2 with 1 byte remaining.");
bad("str-remaining-before-limit", raw([0x00, 0x03, 0x31, 0x32]), "lengthMismatch", "Str1",
  "Version length 3 with 2 bytes remaining and maximumRecordBytes 2: the remaining check precedes the record limit.",
  { limits: { maximumRecordBytes: 2 } });
{
  const body = "b".repeat(200);
  const p = payload({ ...BASE, planes: [{ z: 0, body }] });
  bad("str-two-byte-var-exact-ok", seal(p), "ok", "Str1", "Body of 200 bytes (two-byte Var), length equal to remaining.");
  const short = p.slice(0, p.byteLength - 1);
  bad("str-two-byte-var-plus-one", seal(short), "lengthMismatch", "Str1", "Body Var says 200 with 199 bytes remaining.");
}

// Strings (SPEC 11.3.3)
doc("str-over-record", withPlane({ z: 0, body: "abcdef" }), "oversizedRecord", "Str2", "Body of 6 bytes with maximumRecordBytes 5.",
  { maximumRecordBytes: 5 });
doc("str-preamble-over-r-minus-1", { ...BASE, preamble: "abcde" }, "oversizedRecord", "S7",
  "Preamble of 5 bytes with maximumRecordBytes 5 (the preamble limit is R - 1).", { maximumRecordBytes: 5 });
for (const [name, bytes] of [["overlong", [0xc0, 0x80]], ["surrogate", [0xed, 0xa0, 0x80]],
  ["above-max", [0xf4, 0x90, 0x80, 0x80]], ["truncated", [0xe2, 0x82]], ["lone-continuation", [0x80]], ["ff", [0xff]]]) {
  bad(`utf8-scalar-${name}`, seal(payload({ ...BASE, title: new Uint8Array(bytes) })), "invalidUTF8", "Str3",
    `Title bytes ${hex(new Uint8Array(bytes))}.`);
}
bad("utf8-body-split",
  seal(payload({ ...BASE, planes: [{ z: 0, label: new Uint8Array([0x61, 0xe2, 0x82]), body: new Uint8Array([0xac, 0x62]) }] })),
  "invalidUTF8", "Str3", "U+20AC split across a label and the following field: each Str is validated on its own.");
bad("utf8-before-line-break", seal(payload({ ...BASE, title: new Uint8Array([0x0a, 0xff]) })), "invalidUTF8", "Str3",
  "Ill-formed UTF-8 is reported before the scalar line-break rule.");
doc("scalar-lf", { ...BASE, title: "a\nb" }, "invalidDocument", "Str4", "Title containing LF.");
doc("scalar-cr", withPlane({ z: 0, label: "a\rb", body: "a" }), "invalidDocument", "Str4", "Label containing CR.");

// Flags (SPEC 11.3.5)
doc("flags-document-bit2", { ...BASE, flags: 0x04 }, "invalidContainer", "S1", "documentFlags bit 2.");
doc("flags-document-bit7", { ...BASE, flags: 0x80 }, "invalidContainer", "S1", "documentFlags bit 7.");
bad("flags-plane-bit7", seal(payload(withPlane({ flags: 0x81, z: [1, 0], body: "a" }))), "invalidContainer", "P1",
  "planeFlags bit 7.");
bad("flags-plane-z-form-0", seal(payload(withPlane({ flags: 0x00, z: [1, []], body: "a" }))), "invalidContainer", "P1",
  "z form 0.");

// Numbers (SPEC 11.3.3)
const num = (name, form, bytes, expected, description) =>
  bad(`number-${name}`, seal(payload(withPlane({ z: [form, bytes], body: "a" }))), expected, "N", description);
num("f32-integer", 2, F32(3), "invalidContainer", "Form 2 holding 3.0 (form 1 value).");
num("f32-negative-zero", 2, F32(-0), "invalidContainer", "Form 2 holding -0.");
num("f32-nan", 2, [0x00, 0x00, 0xc0, 0x7f], "invalidDocument", "Form 2 holding NaN.");
num("f32-infinity", 2, F32(Infinity), "invalidDocument", "Form 2 holding +infinity.");
bad("number-f32-truncated", raw([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00, 0x00]), "lengthMismatch", "N",
  "planeCount 1 passes Count(4) with 4 bytes left; the form-2 z then needs 4 bytes with 3 remaining.");
bad("number-f64-truncated", raw([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
  "lengthMismatch", "N", "Form-3 z needs 8 bytes with 7 remaining.");
num("f64-integer", 3, F64(3), "invalidContainer", "Form 3 holding 3.0.");
num("f64-binary32", 3, F64(0.5), "invalidContainer", "Form 3 holding 0.5 (binary32-exact).");
num("f64-negative-zero", 3, F64(-0), "invalidContainer", "Form 3 holding -0.");
num("f64-nan", 3, F64(NaN), "invalidDocument", "Form 3 holding NaN.");
num("f64-negative-infinity", 3, F64(-Infinity), "invalidDocument", "Form 3 holding -infinity.");
num("f64-int-boundary", 3, F64(134217727), "invalidContainer", "Form 3 holding 2^27 - 1.");
num("f32-two-pow-27-ok", 2, F32(134217728), "ok", "2^27 is outside the integer form and binary32-exact: form 2 is canonical.");
num("f64-two-pow-53-plus-2-ok", 3, F64(9007199254740994), "ok", "2^53 + 2 is not binary32-exact: form 3 is canonical.");
num("f32-for-f64-value", 2, F32(0.1), "ok", "binary32(0.1) is itself a binary32 value, valid as form 2 (it is not 0.1).");

// Key order and equivalence (SPEC 11.3.6.1)
doc("order-metadata-decreasing", { ...BASE, metadata: [["b", "1"], ["a", "2"]] }, "invalidContainer", "S6", "Metadata keys b, a.");
doc("order-metadata-identical", { ...BASE, metadata: [["a", "1"], ["a", "2"]] }, "invalidContainer", "S6", "Metadata keys a, a.");
doc("order-nfc-instead-of-bytes", { ...BASE, metadata: [["z", "1"], ["e\u0301", "2"]] }, "invalidContainer", "S6",
  "Keys in NFC order (z before e+U+0301); byte order requires 65 CC 81 before 7A.");
doc("order-utf16-instead-of-bytes", { ...BASE, metadata: [["\u{1f600}", "1"], ["\uff61", "2"]] }, "invalidContainer", "S6",
  "Keys in UTF-16 order (U+1F600 before U+FF61); bytes F0.. sort after EF...");
doc("order-equivalent-keys", { ...BASE, metadata: [["e\u0301", "1"], ["\u00e9", "2"]] }, "invalidDocument", "S6b",
  "Keys e+U+0301 and U+00E9 in byte order: canonically equivalent.");
doc("order-equivalent-kelvin", { ...BASE, metadata: [["K", "1"], ["\u212a", "2"]] }, "invalidDocument", "S6b",
  "Key K and KELVIN SIGN U+212A (NFC is K).");
doc("order-attributes-decreasing", withPlane({ z: 0, attributes: [["b", "1"], ["a", "2"]], body: "a" }), "invalidContainer",
  "P7", "Attribute keys b, a.");
doc("order-attributes-equivalent", withPlane({ z: 0, attributes: [["e\u0301", "1"], ["\u00e9", "2"]], body: "a" }),
  "invalidDocument", "P7a", "Attribute keys e+U+0301 and U+00E9.");
doc("order-keys-ok",
  { ...BASE, metadata: [["B", "1"], ["a", "2"], ["e\u0301", "3"], ["z", "4"], ["\uff61", "5"], ["\u{1f600}", "6"]] }, "ok", "S6",
  "Valid byte order: B, a, e+U+0301, z, U+FF61, U+1F600.");

// Field rules (SPEC 11.3.6.2)
doc("field-empty-version", { ...BASE, version: "" }, "invalidDocument", "S2", "Empty version.");
for (const [name, axis] of [["uppercase", "Time"], ["leading-space", " time"], ["trailing-tab", "time\t"],
  ["trailing-nbsp", "time\u00a0"], ["non-ascii-uppercase", "\u00dcnits"]]) {
  doc(`axis-${name}`, { ...BASE, axis }, "invalidDocument", "R2", `Axis ${JSON.stringify(axis)}.`);
}
doc("axis-unicode-ok", { ...BASE, axis: "\u00fcnits \u03c3" }, "ok", "R2", "Lowercase non-ASCII axis.");
for (const [name, key] of [["colon", "a:b"], ["hash", "#x"], ["leading-space", " x"], ["trailing-ideographic-space", "x\u3000"],
  ["axis", "AXIS"], ["title", "Title"], ["version", "3MD"]]) {
  doc(`metadata-key-${name}`, { ...BASE, metadata: [[key, "v"]] }, "invalidDocument", "R3", `Metadata key ${JSON.stringify(key)}.`);
}
doc("metadata-key-empty-ok", { ...BASE, metadata: [["", "v"]] }, "ok", "R3", "The empty metadata key is valid.");
for (const [name, key] of [["empty", ""], ["uppercase", "Kind"], ["label", "label"], ["z", "z"], ["equals", "a=b"],
  ["space", "a b"], ["tab", "a\tb"], ["leading-nbsp", "\u00a0x"], ["sigma", "k\u03a3"]]) {
  doc(`attribute-key-${name}`, withPlane({ z: 0, attributes: [[key, "v"]], body: "a" }), "invalidDocument", "R9",
    `Attribute key ${JSON.stringify(key)}.`);
}
doc("duplicate-z", { ...BASE, planes: [{ z: 1, body: "a" }, { z: 1, body: "b" }] }, "invalidDocument", "L0", "Two planes at z=1.");
doc("preamble-without-planes", { ...BASE, preamble: "p", planes: [] }, "invalidDocument", "S8", "Preamble present, planeCount 0.");
doc("too-many-planes", { ...BASE, planes: [{ z: 0, body: "a" }, { z: 1, body: "b" }] }, "tooManyPlanes", "S8",
  "Two planes with maximumPlanes 1.", { maximumPlanes: 1 });

// Segment rules (SPEC 11.3.6.4)
const seg = (name, body, expected, rule, description, final = true) =>
  doc(`segment-${name}`, { ...BASE, planes: final ? [{ z: 0, body }] : [{ z: 0, body }, { z: 1, body: "end" }] },
    expected, rule, description);
doc("segment-empty-preamble", { ...BASE, preamble: "" }, "invalidDocument", "G1", "Empty preamble.");
seg("trailing-cr", "a\r", "invalidDocument", "G2", "Body ending in CR.");
seg("inner-cr-ok", "a\rb", "ok", "G2", "A lone inner CR is ordinary content.");
seg("crlf", "a\r\nb", "invalidDocument", "G3", "Body containing CRLF.");
seg("leading-blank", "\nbody", "invalidDocument", "G4", "First line empty.");
seg("trailing-blank", "body\n", "invalidDocument", "G4", "Last line empty.");
seg("leading-nbsp-line", "\u00a0\nbody", "invalidDocument", "G4", "First line is only NBSP.");
seg("trailing-ideographic-line", "body\n\u3000", "invalidDocument", "G4", "Last line is only U+3000.");
seg("plane-line", "a\n@plane", "invalidDocument", "G5", "A line equal to @plane.");
seg("plane-directive", "a\n@plane z=2", "invalidDocument", "G5", "A line @plane z=2.");
seg("plane-tab", "a\n@plane\tz=2", "invalidDocument", "G5", "A line @plane<TAB>z=2.");
seg("indented-plane-ok", "a\n @plane z=2", "ok", "G5", "An indented @plane line is ordinary text.");
seg("planet-ok", "a\n@planet", "ok", "G5", "@planet is not a directive.");
seg("fence-backtick-tilde-ok", "```\n~~~\n@plane z=1", "ok", "G5",
  "Inside a backtick fence, ~~~ does not close it, so @plane stays fenced (last plane may end inside a fence).");
seg("fence-tilde-closed", "~~~\n```\n~~~\n@plane z=1", "invalidDocument", "G5",
  "A tilde fence closed by ~~~ (the backticks inside do not matter); the following @plane is outside the fence.");
seg("fence-nbsp-indented-ok", "\u00a0```\n@plane z=1\n```", "ok", "G5", "An NBSP-indented fence opens a fence.");
seg("fence-open-not-final", "```\ncode", "invalidDocument", "G6", "Open fence in a body that is not the last.", false);
seg("fence-open-final-ok", "```\ncode", "ok", "G6", "Open fence in the last body.");
doc("segment-fence-open-preamble", { ...BASE, preamble: "```\ncode" }, "invalidDocument", "G6", "Open fence in the preamble.");
seg("bom-nul-ok", "\ufeffa\u0000b", "ok", "Str3", "U+FEFF and U+0000 are ordinary content.");

// Phase Q (SPEC 11.3.6.6)
const qp = (name, attributes, expected, description) =>
  doc(`phase-q-${name}`, withPlane({ z: 0, attributes, body: "a" }), expected, "Q", description);
qp("apostrophe", [["a'b", "v"]], "invalidDocument", "Key a'b: the open quote swallows the value.");
qp("double-quote", [["a\"b", "v"]], "invalidDocument", "Key a\"b with value v.");
qp("paired-ok", [["a''b", "v"]], "ok", "Key a''b round-trips.");
qp("spaced-pair-ok", [["a'b c'd", "v"]], "ok", "Key a'b c'd round-trips.");
qp("quoted-space-ok", [["\"x y\"", "v"]], "ok", "Key \"x y\" round-trips.");
qp("swallow-next", [["a'", "1"], ["b'", "2"]], "invalidDocument", "Keys a' and b': one token spans both.");
qp("inject-z", [["q' z='", "1"]], "invalidDocument", "A quoted key that would inject z.");
qp("inject-label", [["q' label='", "x"]], "invalidDocument", "A quoted key that would inject label.");
qp("uppercase-quoted", [["A'x'", "1"]], "invalidDocument", "A quoted key that lowercases to a different key.");

// Phase L and precedence (SPEC 11.3.8)
doc("limit-record-below-3", BASE, "oversizedRecord", "L1", "maximumRecordBytes 2.", { maximumRecordBytes: 2 });
doc("limit-frontmatter-line", BASE, "oversizedRecord", "L2", "Version line 3md: \"1\" is 8 bytes; maximumRecordBytes 7.",
  { maximumRecordBytes: 7 });
doc("limit-directive-line", withPlane({ z: 0, label: "abc", body: "a" }), "oversizedRecord", "L3",
  "Directive @plane z=0 label=\"abc\" is 22 bytes; maximumRecordBytes 21.", { maximumRecordBytes: 21 });
doc("limit-text-length", BASE, "oversizedOutput", "L4", "T = 40; maximumDecodedBytes 39.", { maximumDecodedBytes: 39 });
doc("limit-lines", BASE, "tooManyLines", "L5", "Lines = 8; maximumLines 7.", { maximumLines: 7 });
doc("precedence-l0-over-l3", { ...BASE, planes: [{ z: 1, label: "abcdefghij", body: "a" }, { z: 1, body: "b" }] },
  "invalidDocument", "L0", "Duplicate z and an oversized directive: L0 wins.", { maximumRecordBytes: 20 });
doc("precedence-l3-over-l4", withPlane({ z: 0, label: "abcdefghij", body: "a" }), "oversizedRecord", "L3",
  "Oversized directive and T over Dmax: L3 wins.", { maximumRecordBytes: 25, maximumDecodedBytes: 50 });
doc("precedence-l4-over-l5", BASE, "oversizedOutput", "L4", "T over Dmax and too many lines: L4 wins.",
  { maximumDecodedBytes: 39, maximumLines: 7 });
bad("precedence-s-order", seal(new Uint8Array([...payload({
  ...BASE, planeCount: 3, planes: [{ z: 0, body: "a" }, { z: 1, attributes: [["Bad", "v"]], body: "b" }],
})])), "invalidDocument", "S9",
"Plane 1 has an invalid key and plane 2 is missing: the first failure in field order (R9 in plane 1) wins.");
doc("precedence-utf8-before-limits", withPlane({ z: 0, body: "a" }, { title: new Uint8Array([0xff]) }), "invalidUTF8", "S4",
  "Phase S errors precede Phase L errors.", { maximumDecodedBytes: 10 });
doc("end-trailing-byte", { ...BASE, trailing: [0x00] }, "lengthMismatch", "S10", "One byte after the last plane (lengths resealed).");
{
  // T may exceed maximumEncodedBytes; kind 2 does not require T <= Emax.
  const planes = Array.from({ length: 80 }, (_, z) => ({ z, body: "" }));
  const bytes = seal(payload({ version: "1", axis: "", planes }));
  emit(limitVectors, "limits", "eighty-planes-emax-1000", bytes, "ok", "L4",
    `80 empty planes: file ${bytes.byteLength} bytes, T = 1056 > maximumEncodedBytes 1000; kind 2 decodes. Text encode under the same limits fails.`,
    { limits: { maximumEncodedBytes: 1000 } });
}

// Limit edges: the smallest accepted value and the value one below for each limit, cross-checked with validate.
{
  const document = {
    version: "1.0", axis: "layer", title: "Edges \"q\"", metadata: rec([["owner", "ops \\ team"], ["a", "b"]]),
    preamble: "Intro\n\nmore",
    planes: [plane(0, "First\nsecond"), plane(2.5, "", { label: "two", x: 0.1, attributes: rec([["k", "v"]]) }),
      plane(-7, "```\ncode")],
  };
  checkDocumentStrings("limits/edges", document);
  const bytes = encodeStructured(document);
  addOutput("conformance/structured/limits/edges.3mdb", bytes);
  const T = DocumentStorageCodec.encode(document).byteLength;
  const minimal = (key, start) => {
    let value = start;
    while (value > 1 && code(() => decode(bytes, new DocumentDecodeLimits({ [key]: value - 1 }))) === "ok") value -= 1;
    return value;
  };
  // rule: the step that rejects the value one below the edge (and that the edge value passes).
  for (const [key, fail, start, rule] of [["maximumDecodedBytes", "oversizedOutput", T + 5, "L4"],
    ["maximumLines", "tooManyLines", 40, "L5"], ["maximumPlanes", "tooManyPlanes", 5, "S8"],
    ["maximumRecordBytes", "oversizedRecord", 200, "L3"],
    ["maximumEncodedBytes", "oversizedInput", bytes.byteLength + 5, "D2"]]) {
    const edge = minimal(key, start);
    for (const [value, expected] of [[edge, "ok"], [edge - 1, fail]]) {
      const limits = { [key]: value };
      const truth = key === "maximumEncodedBytes" ? "n/a"
        : code(() => DocumentStorageCodec.validate(document, new DocumentDecodeLimits(limits)));
      if (truth !== "n/a" && (truth === "ok") !== (expected === "ok")) problems.push(`edge ${key}=${value}: validate ${truth}`);
      emit(limitVectors, "limits", `edges-${key}-${value === edge ? "at" : "below"}`, bytes, expected, rule,
        `${key} = ${value} (${value === edge ? "smallest accepted value" : "one below"}).`, { limits, sharedFile: "edges.3mdb" });
    }
    if (key === "maximumDecodedBytes" && edge !== T) problems.push(`edge Dmax ${edge} != T ${T}`);
  }
}
{
  // The preamble is the longest record: accepted at R = len + 1, rejected at R = len.
  const document = { version: "1", axis: "", title: null, metadata: rec([]), preamble: "p".repeat(30), planes: [plane(0, "a")] };
  const bytes = encodeStructured(document);
  addOutput("conformance/structured/limits/preamble-record.3mdb", bytes);
  for (const [r, expected] of [[31, "ok"], [30, "oversizedRecord"]]) {
    const truth = code(() => DocumentStorageCodec.validate(document, new DocumentDecodeLimits({ maximumRecordBytes: r })));
    if ((truth === "ok") !== (expected === "ok")) problems.push(`preamble R=${r}: validate ${truth}`);
    emit(limitVectors, "limits", `preamble-record-${r}`, bytes, expected, "Str2",
      `Preamble of 30 bytes, maximumRecordBytes ${r} (Str(segment, R - 1) at S7).`,
      { limits: { maximumRecordBytes: r }, sharedFile: "preamble-record.3mdb" });
  }
}

// MARK: - Interchange catalog fixture (test-plan section 6)

// The committed 2.0 fixture invalid-binary-kind.3mdb declares payload kind 2 over a kind-1 text payload with a stale
// CRC: a 2.1 reader passes D6 to D11 and stops at D12. It keeps its bytes; invalid-binary-kind-3.3mdb (byte 10 = 3,
// CRC not resealed) takes over the unsupportedPayloadKind expectation, because D6 precedes D12.
{
  const path = "conformance/interchange/invalid-binary-kind.3mdb";
  const original = read(path);
  if (sha256(original) !== "3ebc8f0256cbcd5b874a9806a08005fb648a9d6b4432faf654a738fa84e8ae26") {
    problems.push(`${path}: changed; the 2.0 fixture must stay byte-unchanged`);
  }
  if (original[10] !== 2 || checksum(original) === u32(original, 36)) {
    problems.push(`${path}: no longer declares payload kind 2 with a stale CRC`);
  }
  const kind3 = original.slice();
  kind3[10] = 3;
  for (const [file, bytes, expected] of [[path, original, "checksumMismatch"],
    ["conformance/interchange/invalid-binary-kind-3.3mdb", kind3, "unsupportedPayloadKind"]]) {
    const actual = code(() => decode(bytes));
    if (actual !== expected) problems.push(`${file}: the TypeScript library gave ${actual}, expected ${expected}`);
  }
  addOutput("conformance/interchange/invalid-binary-kind-3.3mdb", kind3);
}

// MARK: - Canonical number spellings (conformance/extensions/numeric-powers.json)

{
  // Spelled by the TypeScript text writer, which formats every coordinate with canonicalNumber.
  const view = new DataView(new ArrayBuffer(8));
  const bits = (value) => {
    view.setFloat64(0, value);
    return view.getBigUint64(0).toString(16).padStart(16, "0");
  };
  const spell = (value) => {
    const text = decoder.decode(DocumentStorageCodec.encode({
      version: "1", axis: "", title: null, metadata: rec([]), preamble: null, planes: [plane(value, "")],
    }));
    const match = /^@plane z=(\S+)$/m.exec(text);
    if (match === null) {
      problems.push(`numeric-powers: no plane directive for ${bits(value)}`);
      return "";
    }
    return match[1];
  };
  const numberVectors = [];
  const add = (name, value) => numberVectors.push({ bitPattern: bits(value), formatted: spell(value), name });
  for (let exponent = -1074; exponent <= 1023; exponent += 1) {
    add(`power-of-two-${exponent}`, 2 ** exponent);
    add(`negative-power-of-two-${exponent}`, -(2 ** exponent));
  }
  for (let exponent = -30; exponent <= 30; exponent += 1) {
    add(`power-of-ten-${exponent}`, Number(`1e${exponent}`));
    add(`negative-power-of-ten-${exponent}`, -Number(`1e${exponent}`));
  }
  const numbers = {
    schema: "3md-canonical-numbers-1",
    note: "Signed powers of two 2^-1074..2^1023 (4,196 entries) and signed powers of ten 1e-30..1e30 (122 entries), spelled by the TypeScript canonicalNumber. 4,318 entries hold 4,316 distinct values: +1 and -1 appear both as 2^0 and as 10^0 (bit patterns 3ff0000000000000 and bff0000000000000).",
    vectors: numberVectors,
  };
  addOutput("conformance/extensions/numeric-powers.json", encoder.encode(JSON.stringify(numbers, null, 1) + "\n"));
}

// MARK: - Sizes (perf-gate section 4, gate G6)

function largeInputs() {
  const names = { "synthetic-2000": "synthetic-2000.3md", "sculpt-4096-32x20": "sculpt-4096.3md" };
  const complete = (dir) => Object.values(names).every((name) => existsSync(join(dir, name)));
  let dir = options.inputs ?? join(ROOT, "bench/inputs");
  let temporary = null;
  if (!complete(dir)) {
    const scripts = ["scripts/bench/generate-synthetic.mjs", "scripts/bench/generate-sculpt.mjs"];
    if (options.inputs !== null || !scripts.every((script) => existsSync(join(ROOT, script)))) {
      cannotRun(`sizes.json needs ${Object.values(names).join(" and ")} ` +
        `(docs/design/threemd-2.1/perf-gate.md, section 2) in ` +
        `${relative(ROOT, dir) || dir}. Pass --inputs DIR, or generate them with node scripts/bench/generate-synthetic.mjs ` +
        "--out bench/inputs and node scripts/bench/generate-sculpt.mjs --out bench/inputs.");
    }
    // The performance-gate generators run under Node (Math.sin is not bit-exact across engines) and assert the
    // SHA-256 of what they write.
    temporary = mkdtempSync(join(tmpdir(), "3md-structured-inputs-"));
    for (const script of scripts) {
      const result = spawnSync("node", [join(ROOT, script), "--out", temporary], { stdio: "inherit" });
      if (result.status !== 0) cannotRun(`${script} failed (${result.error?.message ?? `status ${result.status}`}).`);
    }
    dir = temporary;
  }
  try {
    return Object.entries(names).map(([key, name]) => [key, new Uint8Array(readFileSync(join(dir, name)))]);
  } finally {
    if (temporary !== null) rmSync(temporary, { recursive: true, force: true });
  }
}

{
  const examples = join(ROOT, "Examples");
  let canonical = 0;
  let kind2 = 0;
  let smaller = 0;
  let maxRatio = 0;
  let minRatio = 9;
  const rows = [];
  const names = readdirSync(examples).filter((name) => name.endsWith(".3md")).sort();
  for (const name of names) {
    const document = DocumentStorageCodec.decode(new Uint8Array(readFileSync(join(examples, name))));
    const c = DocumentStorageCodec.encode(document).byteLength;
    const b = encodeStructured(document).byteLength;
    canonical += c;
    kind2 += b;
    if (b < c) smaller += 1;
    maxRatio = Math.max(maxRatio, b / c);
    minRatio = Math.min(minRatio, b / c);
    rows.push({ file: `Examples/${name}`, canonical: c, kind2: b });
  }
  const large = {};
  for (const [key, source] of largeInputs()) {
    const document = DocumentStorageCodec.decode(source);
    large[key] = { canonical: DocumentStorageCodec.encode(document).byteLength, kind2: encodeStructured(document).byteLength };
  }
  const sizes = {
    examples: { files: names.length, canonical, kind2, ratio: kind2 / canonical, smaller, minRatio, maxRatio },
    large, perFile: rows,
  };
  addOutput("conformance/structured/sizes.json", encoder.encode(JSON.stringify(sizes, null, 1) + "\n"));
}

// MARK: - Manifests

const LIMITS_NOTE = "limits are DocumentDecodeLimits fields; absent fields are standard. The limits decide the outcome, so every consumer must pass them to storage decode: the unit tests directly, the interchange driver in the 3md-interchange-2 request's limits object, and the 2.0.0 compatibility job through its per-language library harness (the 2.0.0 adapters cannot take limits). expected20 is the 2.0.0 reader's outcome under the same limits. errorType is none for ok vectors. rule is the deciding SPEC 11.3 step.";
const manifest = {
  schema: "3md-structured-golden-1",
  note: "Payload kind 2 anchors: one for every valid interchange case (the composition cases as their profile envelopes), the two Examples/Extensions files and the three SPEC 11.3.17 worked examples. Paths are relative to the repository root. First generated by the spec21 TypeScript prototype and reproduced byte for byte by the Rust and Swift prototypes; scripts/structured/generate.mjs regenerates them from the built TypeScript library.",
  source: "CorvidLabs/3md main 1ebe67d",
  counts: {
    interchange: files.filter((f) => f.set === "interchange").length,
    examples: files.filter((f) => f.set === "examples").length,
    worked: files.filter((f) => f.set === "worked").length,
  },
  totals: {
    kind2Bytes: files.filter((f) => f.set === "interchange").reduce((total, f) => total + f.bytes, 0),
    canonicalBytes: files.filter((f) => f.set === "interchange").reduce((total, f) => total + f.canonicalBytes, 0),
  },
  files,
};
addOutput("conformance/structured/manifest.json", encoder.encode(JSON.stringify(manifest, null, 2) + "\n"));
const vectorsFile = {
  schema: "3md-structured-vectors-1",
  entryPoint: "DocumentStorageCodec.decode",
  note: `Hostile, edge and limit vectors for payload kind 2: the ${vectors.length} vectors of conformance/structured/invalid (one file each), then the ${limitVectors.length} of conformance/structured/limits (several share one file and differ only in limits). file is relative to the repository root. Every file is a complete .3mdb with lengths and CRC resealed unless the vector says otherwise. ${LIMITS_NOTE} textValidate20 is the TypeScript validate outcome (unchanged in 2.1) for vectors that describe a Document.`,
  vectors: [...vectors, ...limitVectors],
};
checkJSONStrings("vectors.json", vectorsFile);
addOutput("conformance/structured/vectors.json", encoder.encode(JSON.stringify(vectorsFile, null, 2) + "\n"));

// MARK: - Compare or write

/** Committed structured files, so that a file nobody generates any more is reported. */
function committedStructuredFiles() {
  const found = [];
  const scan = (dir, accept) => {
    const absolute = join(ROOT, dir);
    if (!existsSync(absolute)) return;
    for (const name of readdirSync(absolute)) if (accept(name)) found.push(`${dir}/${name}`);
  };
  scan("conformance/structured", (name) => name.endsWith(".3mdb") || name.endsWith(".json"));
  scan("conformance/structured/invalid", (name) => name.endsWith(".3mdb"));
  scan("conformance/structured/limits", (name) => name.endsWith(".3mdb"));
  scan("conformance/extensions", (name) => name.endsWith(".structured.3mdb"));
  scan("Examples/Extensions", (name) => name.endsWith(".structured.3mdb"));
  return found.filter((path) => !outputs.has(path)).sort();
}

const summary = `${outputs.size} files: ${manifest.files.length} anchors, ${vectors.length + limitVectors.length} vectors ` +
  `(${vectors.length} invalid, ${limitVectors.length} limits) in ` +
  `${[...outputs.keys()].filter((path) => /\/(invalid|limits)\//.test(path)).length} files, the catalog fixture and 4 JSON files`;
if (problems.length > 0) {
  console.error(`generate.mjs: ${problems.length} expectation(s) failed${options.mode === "write" ? "; nothing was written" : ""}:`);
  for (const problem of problems) console.error(`  ${problem}`);
  process.exit(1);
}
const orphans = committedStructuredFiles();
if (options.mode === "write") {
  for (const [path, bytes] of outputs) {
    mkdirSync(dirname(join(ROOT, path)), { recursive: true });
    writeFileSync(join(ROOT, path), bytes);
  }
  for (const path of orphans) rmSync(join(ROOT, path));
  console.log(`generate.mjs: wrote ${summary}${orphans.length > 0 ? `; removed ${orphans.join(", ")}` : ""}.`);
} else {
  const differences = [];
  for (const [path, bytes] of [...outputs].sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))) {
    const absolute = join(ROOT, path);
    if (!existsSync(absolute)) {
      differences.push(`${path}: missing (generated ${bytes.byteLength} bytes, SHA-256 ${sha256(bytes)})`);
      continue;
    }
    const committed = new Uint8Array(readFileSync(absolute));
    if (!sameBytes(committed, bytes)) {
      let offset = 0;
      while (offset < committed.byteLength && offset < bytes.byteLength && committed[offset] === bytes[offset]) offset += 1;
      differences.push(`${path}: differs at byte ${offset} (committed ${committed.byteLength} bytes, SHA-256 ` +
        `${sha256(committed)}; generated ${bytes.byteLength} bytes, SHA-256 ${sha256(bytes)})`);
    }
  }
  for (const entry of manifest.files) {
    const absolute = join(ROOT, entry.kind2File);
    if (existsSync(absolute) && sha256(new Uint8Array(readFileSync(absolute))) !== entry.sha256) {
      differences.push(`${entry.kind2File}: committed SHA-256 differs from the regenerated manifest (${entry.sha256})`);
    }
  }
  for (const path of orphans) differences.push(`${path}: committed but not generated`);
  if (differences.length > 0) {
    console.error(`generate.mjs: ${differences.length} difference(s) from the committed files. ` +
      "Review, then regenerate with --write:");
    for (const difference of differences) console.error(`  ${difference}`);
    process.exit(1);
  }
  console.log(`generate.mjs: ${summary} match the committed bytes and SHA-256.`);
}
