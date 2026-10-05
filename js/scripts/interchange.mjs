import { once } from "node:events";
import { stdin, stdout } from "node:process";
import {
  CompositionEditor, DocumentCompositionCodec, DocumentCompositionSnapshot,
  DocumentCompositionError, DocumentEditError, DocumentEditor, DocumentIdentity,
  DocumentSnapshot, DocumentStorageCodec, DocumentStorageError,
  DocumentStorageFormat, ParseError, parse, serialize, stableID,
} from "../dist/index.js";

const maximumLineBytes = 32 * 1024 * 1024;
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

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
  const composition = DocumentCompositionCodec.decode(document);
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
    binaryHex: hex(DocumentStorageCodec.encode(DocumentCompositionCodec.document(composition), DocumentStorageFormat.binary())),
    legacyHex: null, rawCanonicalHex: null,
    revisionHex: textHex(snapshot.revision.canonicalContent),
    adoptedHex: hex(DocumentCompositionCodec.encode(adopted)),
    editedHex: hex(DocumentCompositionCodec.encode(edited.composition)),
    staleRejected: rejected,
    semantic: semanticComposition(composition),
  };
}
function requestResponse(line) {
  try {
    const request = JSON.parse(decoder.decode(line));
    if (request?.schema !== "3md-interchange-1" || !["document", "composition"].includes(request.kind) ||
      typeof request.bytesHex !== "string" || request.bytesHex.length % 2 !== 0) throw new Error("Invalid adapter request.");
    for (let index = 0; index < request.bytesHex.length; index += 1) {
      const unit = request.bytesHex.charCodeAt(index);
      if (!((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102))) throw new Error("Invalid request hexadecimal.");
    }
    const bytes = Buffer.from(request.bytesHex, "hex");
    const document = DocumentStorageCodec.decode(bytes);
    return request.kind === "document" ? documentResponse(bytes, document) : compositionResponse(document);
  } catch (error) {
    const code = error instanceof DocumentEditError ? error.diagnostic.code :
      error instanceof DocumentStorageError || error instanceof DocumentCompositionError || error instanceof ParseError ?
        error.code : "adapterFailure";
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
