import { once } from "node:events";
import { stdin, stdout } from "node:process";
import {
  CompositionEditor, DocumentComposition, DocumentCompositionCodec, DocumentCompositionLimits, DocumentCompositionSnapshot,
  DocumentCompositionError, DocumentEditError, DocumentEditor, DocumentIdentity,
  DocumentFileComposition, DocumentFileCompositionError,
  DocumentDecodeLimits, DocumentSnapshot, DocumentStorageCodec, DocumentStorageError,
  DocumentStorageFormat, ParseError, parse, serialize, stableID,
} from "../dist/index.js";

const maximumLineBytes = 32 * 1024 * 1024;
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const profileBytes = DocumentCompositionLimits.standard.maximumProfileBytes;
const profileDecodeLimits = new DocumentDecodeLimits({ maximumEncodedBytes: profileBytes,
  maximumDecodedBytes: profileBytes, maximumPlanes: 1, maximumRecordBytes: profileBytes });

function hex(bytes) { return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString("hex"); }
function textHex(text) { return hex(encoder.encode(text)); }
function bits(value) {
  if (value === null) return null;
  const buffer = new ArrayBuffer(8);
  new DataView(buffer).setFloat64(0, value === 0 ? 0 : value, false);
  return hex(new Uint8Array(buffer));
}
function semanticDocument(document) {
  return {
    version: document.version, axis: document.axis, title: document.title,
    metadata: document.metadata, preamble: document.preamble,
    planes: document.planes.map((plane) => ({
      zBits: bits(plane.z), xBits: bits(plane.x), yBits: bits(plane.y),
      label: plane.label, attributes: plane.attributes, body: plane.body,
    })),
  };
}
function semanticComposition(composition) {
  return {
    rootID: composition.rootID,
    entries: [...composition.entries].sort((left, right) => left.id < right.id ? -1 : left.id > right.id ? 1 : 0)
      .map((entry) => ({ id: entry.id, document: semanticDocument(entry.document), references: entry.references })),
  };
}
function editedPlane(plane) {
  return { ...plane, body: plane.body ? `${plane.body}\ninterchange edited` : "interchange edited" };
}
function staleRejected(apply) {
  try { apply(); return false; }
  catch (error) {
    if (error?.diagnostic?.code === "staleRevision") return true;
    throw error;
  }
}
function documentResponse(bytes, document) {
  const adopted = DocumentIdentity.adopt(document);
  const snapshot = new DocumentSnapshot(adopted);
  const first = adopted.planes[0];
  let edited = snapshot;
  let rejected = true;
  if (first !== undefined) {
    const patch = { expectedRevision: snapshot.revision,
      operations: [{ kind: "replace", id: stableID(first), plane: editedPlane(first) }] };
    edited = DocumentEditor.apply(patch, snapshot);
    rejected = staleRejected(() => DocumentEditor.apply(patch, edited));
  }
  return {
    ok: true,
    canonicalHex: hex(DocumentStorageCodec.encode(document)),
    binaryHex: hex(DocumentStorageCodec.encode(document, DocumentStorageFormat.binary())),
    legacyHex: textHex(serialize(document)),
    rawCanonicalHex: DocumentStorageCodec.isBinary(bytes) ? null : hex(DocumentStorageCodec.encode(parse(decoder.decode(bytes)))),
    revisionHex: textHex(snapshot.revision.canonicalContent),
    adoptedHex: hex(DocumentStorageCodec.encode(adopted)),
    editedHex: hex(DocumentStorageCodec.encode(edited.document)),
    staleRejected: rejected,
    semantic: semanticDocument(document),
  };
}
function compositionResponse(document) {
  const composition = document instanceof DocumentComposition ? document : DocumentCompositionCodec.decode(document);
  const adopted = DocumentIdentity.adopt(composition);
  const snapshot = new DocumentCompositionSnapshot(adopted);
  const entry = adopted.rootEntry;
  const first = entry.document.planes[0];
  let edited = snapshot;
  let rejected = true;
  if (first !== undefined) {
    const replacement = { ...entry, document: { ...entry.document,
      planes: [editedPlane(first), ...entry.document.planes.slice(1)] } };
    const patch = { expectedRevision: snapshot.revision,
      operations: [{ kind: "replaceEntry", id: entry.id, entry: replacement }] };
    edited = CompositionEditor.apply(patch, snapshot);
    rejected = staleRejected(() => CompositionEditor.apply(patch, edited));
  }
  return {
    ok: true,
    canonicalHex: hex(DocumentCompositionCodec.encode(composition)),
    binaryHex: hex(DocumentStorageCodec.encode(DocumentCompositionCodec.document(composition), DocumentStorageFormat.binary(), profileDecodeLimits)),
    legacyHex: null, rawCanonicalHex: null,
    revisionHex: textHex(snapshot.revision.canonicalContent),
    adoptedHex: hex(DocumentCompositionCodec.encode(adopted)),
    editedHex: hex(DocumentCompositionCodec.encode(edited.composition)),
    staleRejected: rejected,
    semantic: semanticComposition(composition),
  };
}
// Preflight validates generic JSON before field policies, retaining strict duplicate-key semantics.
function strictJSON(source) {
  let index = 0;
  function invalid() { throw new Error("Invalid adapter JSON."); }
  function whitespace() { while (index < source.length && " \t\r\n".includes(source[index])) index += 1; }
  function string() {
    if (source[index++] !== '"') invalid();
    const start = index - 1;
    while (index < source.length) {
      const unit = source.charCodeAt(index++);
      if (unit === 34) {
        const value = JSON.parse(source.slice(start, index));
        for (let offset = 0; offset < value.length; offset += 1) {
          const character = value.charCodeAt(offset);
          if (character >= 0xd800 && character <= 0xdbff) {
            const next = value.charCodeAt(++offset);
            if (!(next >= 0xdc00 && next <= 0xdfff)) invalid();
          } else if (character >= 0xdc00 && character <= 0xdfff) invalid();
        }
        return value;
      }
      if (unit < 32) invalid();
      if (unit === 92) {
        const escape = source[index++];
        if (escape === "u") {
          if (!/^[0-9a-fA-F]{4}$/.test(source.slice(index, index + 4))) invalid();
          index += 4;
        } else if (escape === undefined || !'"\\/bfnrt'.includes(escape)) invalid();
      }
    }
    invalid();
  }
  function value(depth) {
    if (depth > 64) invalid();
    whitespace();
    if (source[index] === '"') { string(); return; }
    if (source[index] === "{") {
      index += 1; whitespace();
      if (source[index] === "}") { index += 1; return; }
      const keys = new Set();
      while (true) {
        const key = string().normalize("NFC");
        if (keys.has(key)) invalid(); keys.add(key);
        whitespace(); if (source[index++] !== ":") invalid(); value(depth + 1); whitespace();
        if (source[index] === "}") { index += 1; return; }
        if (source[index++] !== ",") invalid(); whitespace();
      }
    }
    if (source[index] === "[") {
      index += 1; whitespace();
      if (source[index] === "]") { index += 1; return; }
      while (true) {
        value(depth + 1); whitespace();
        if (source[index] === "]") { index += 1; return; }
        if (source[index++] !== ",") invalid(); whitespace();
      }
    }
    const start = index;
    while (index < source.length && !" \t\r\n,]}".includes(source[index])) index += 1;
    if (index === start) invalid();
    const literal = JSON.parse(source.slice(start, index));
    if (literal !== null && typeof literal !== "boolean" &&
      !(typeof literal === "number" && Number.isFinite(literal))) invalid();
  }
  value(0); whitespace(); if (index !== source.length) invalid();
  return JSON.parse(source);
}
function record(value, keys) {
  if (value === null || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).length !== keys.length || !keys.every((key) => Object.hasOwn(value, key))) {
    throw new Error("Invalid adapter fields.");
  }
  return value;
}
const compositionLimitNames = ["maximumDefinitions", "maximumReferences", "maximumDepth", "maximumDefinitionBytes",
  "maximumTraversalOccurrences", "maximumProfileBytes", "maximumReferenceAttributes", "maximumReferenceAttributeBytes"];
const documentLimitNames = ["maximumEncodedBytes", "maximumDecodedBytes", "maximumLines", "maximumPlanes",
  "maximumRecordBytes"];
// An absent object keeps standard limits. Present objects carry known names with integral numbers within
// +/-(2^53 - 1); the library limit types validate ranges when resolution begins.
function requestedLimits(payload, key, names) {
  if (!Object.hasOwn(payload, key)) return undefined;
  const value = payload[key];
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid limits object.");
  for (const [name, number] of Object.entries(value)) {
    if (!names.includes(name) || typeof number !== "number" || !Number.isSafeInteger(number)) {
      throw new Error("Invalid limits field.");
    }
  }
  return value;
}
function filesPayload(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value) ||
    !Object.keys(value).every((key) => ["rootPath", "files", "limits", "documentLimits"].includes(key)) ||
    !Object.hasOwn(value, "rootPath") || !Object.hasOwn(value, "files")) {
    throw new Error("Invalid files request.");
  }
  return value;
}
function bytesFromHex(value) {
  if (typeof value !== "string" || value.length % 2 !== 0) throw new Error("Invalid request hexadecimal.");
  for (let index = 0; index < value.length; index += 1) {
    const unit = value.charCodeAt(index);
    if (!((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102))) throw new Error("Invalid request hexadecimal.");
  }
  return Buffer.from(value, "hex");
}
function requestResponse(line) {
  try {
    const request = record(strictJSON(decoder.decode(line)), ["schema", "kind", "bytesHex"]);
    if (request.schema !== "3md-interchange-1" || !["document", "composition", "files"].includes(request.kind)) {
      throw new Error("Invalid adapter request.");
    }
    const bytes = bytesFromHex(request.bytesHex);
    if (request.kind === "files") {
      // Order: strict protocol JSON, envelope and limit-object shapes, the standard source-count ceiling,
      // per-file fields and hex, then library resolution, which validates limit values first.
      const payload = filesPayload(strictJSON(decoder.decode(bytes)));
      if (typeof payload.rootPath !== "string" || !Array.isArray(payload.files)) throw new Error("Invalid files request.");
      const limits = requestedLimits(payload, "limits", compositionLimitNames);
      const documentLimits = requestedLimits(payload, "documentLimits", documentLimitNames);
      if (payload.files.length > DocumentCompositionLimits.standard.maximumDefinitions) {
        throw new DocumentFileCompositionError("inputLimit");
      }
      const sources = payload.files.map((file) => {
        const source = record(file, ["path", "bytesHex"]);
        if (typeof source.path !== "string") throw new Error("Invalid file path field.");
        return { path: source.path, data: bytesFromHex(source.bytesHex) };
      });
      return compositionResponse(DocumentFileComposition.resolve(payload.rootPath, sources, limits, documentLimits)
        .composition);
    }
    if (request.kind === "composition") return compositionResponse(DocumentCompositionCodec.decode(bytes));
    const document = DocumentStorageCodec.decode(bytes);
    return documentResponse(bytes, document);
  } catch (error) {
    const fileCode = error instanceof DocumentFileCompositionError ?
      ({ invalidPath: "filePath", duplicatePath: "filePath", invalidLedger: "fileLedger", invalidGlyph: "fileLedger",
        missingFile: "missingFile", inputLimit: "fileLimit" })[error.code] : undefined;
    const code = fileCode ?? (error instanceof DocumentEditError ? error.diagnostic.code :
      error instanceof DocumentStorageError || error instanceof DocumentCompositionError || error instanceof ParseError ?
        error.code : "adapterFailure");
    return { ok: false, error: code };
  }
}
async function respond(line) {
  const response = JSON.stringify(line === null ? { ok: false, error: "adapterFailure" } : requestResponse(line));
  const bounded = Buffer.byteLength(response) <= maximumLineBytes ? response : '{"ok":false,"error":"adapterFailure"}';
  if (!stdout.write(`${bounded}\n`)) await once(stdout, "drain");
}

let parts = [];
let byteCount = 0;
let oversized = false;
for await (const chunk of stdin) {
  let start = 0;
  while (start < chunk.length) {
    const newline = chunk.indexOf(10, start);
    const end = newline < 0 ? chunk.length : newline;
    const count = end - start;
    if (!oversized) {
      byteCount += count;
      if (byteCount > maximumLineBytes) { oversized = true; parts = []; }
      else if (count > 0) parts.push(chunk.subarray(start, end));
    }
    if (newline < 0) break;
    await respond(oversized ? null : Buffer.concat(parts, byteCount));
    parts = []; byteCount = 0; oversized = false;
    start = newline + 1;
  }
}
if (byteCount > 0 || oversized) await respond(oversized ? null : Buffer.concat(parts, byteCount));
