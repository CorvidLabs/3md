import { containerChecksum } from "./checksum.js";
import { parse, ParseError, type Document } from "./index.js";
import { canonicalNumber } from "./number.js";
import { boundedInteger, canonicalDocument, canonicalKeys, checkCancellation, documentsEqual, InvalidUnicodeError, trimFoundationWhitespace, utf8Length } from "./portable.js";
import { readStructured, writeStructuredPayload } from "./structured.js";

export { canonicalNumber } from "./number.js";

/** Identifiers in the independently versioned general-document envelope. */
export enum DocumentCompression { None = 0, Lzfse = 1 }

/**
 * The storage writer's output format. Text remains the portable interchange format. `binary` writes the version 1
 * container with the structured document payload (payload kind 2, SPEC.md 11.3) and the selected compression
 * identifier; `DocumentStorageCodec.encodeTextContainer` writes payload kind 1 for files that ThreeMD 2.0 must read.
 */
export type DocumentStorageFormat = { readonly kind: "text" } | {
  readonly kind: "binary"; readonly compression: DocumentCompression;
};
export const DocumentStorageFormat = /* @__PURE__ */ Object.freeze({
  text: /* @__PURE__ */ Object.freeze({ kind: "text" } as const),
  binary(compression: DocumentCompression = DocumentCompression.None): DocumentStorageFormat {
    return Object.freeze({ kind: "binary", compression });
  },
});

/**
 * Payload kinds of the version 1 general binary container (header byte 10). Plain constants rather than an enum, so
 * new kinds are additive: `canonicalText` (1) is canonical UTF-8 3md text behind the header (ThreeMD 2.0, SPEC.md
 * 11.1) and `structuredDocument` (2) is the structured document payload (ThreeMD 2.1, SPEC.md 11.3). Every other value
 * is reserved.
 */
export const DocumentPayloadKind = /* @__PURE__ */ Object.freeze({ canonicalText: 1, structuredDocument: 2 } as const);
/** A payload kind byte; compare it with the `DocumentPayloadKind` constants. */
export type DocumentPayloadKind = number;

/**
 * The raw fixed header fields of a binary container, reported by `DocumentStorageCodec.containerInfo` without
 * validating them, the payload or the checksum. Lengths are `bigint` because the header stores 64-bit values.
 */
export interface DocumentContainerInfo {
  /** The independent container version; 1 for every payload kind in ThreeMD 2.1. */
  readonly containerVersion: number;
  /** The payload kind byte; compare it with `DocumentPayloadKind`. */
  readonly payloadKind: number;
  /** The raw compression identifier; compare it with `DocumentCompression`. */
  readonly compression: number;
  /** The raw feature flags. */
  readonly flags: number;
  /** The raw reserved field. */
  readonly reserved: number;
  /** The declared encoded payload byte count. */
  readonly encodedPayloadByteCount: bigint;
  /** The declared decoded (uncompressed) payload byte count. */
  readonly decodedPayloadByteCount: bigint;
  /** The declared CRC-32/ISO-HDLC value, not verified by inspection. */
  readonly checksum: number;
}

export type DocumentStorageErrorCode = "invalidLimits" | "oversizedInput" | "oversizedOutput" | "tooManyLines" |
  "tooManyPlanes" | "oversizedRecord" | "invalidUTF8" | "invalidText" | "invalidDocument" | "invalidContainer" |
  "unsupportedVersion" | "unsupportedPayloadKind" | "unsupportedCompression" | "unsupportedFlags" |
  "nonzeroReserved" | "lengthMismatch" | "checksumMismatch" | "compressionUnavailable" | "compressionFailed";

/** Stable error codes mirror Swift; `detail` preserves the rejected field or parser error. */
export class DocumentStorageError extends Error {
  public readonly code: DocumentStorageErrorCode;
  public readonly detail: unknown;
  public constructor(code: DocumentStorageErrorCode, detail?: unknown) {
    super(detail instanceof Error ? detail.message : `${code}${detail === undefined ? "" : `: ${String(detail)}`}`);
    this.name = "DocumentStorageError";
    this.code = code;
    this.detail = detail;
  }
}

export class DocumentDecodeLimits {
  public readonly maximumEncodedBytes: number;
  public readonly maximumDecodedBytes: number;
  public readonly maximumLines: number;
  public readonly maximumPlanes: number;
  public readonly maximumRecordBytes: number;
  public static readonly standard = /* @__PURE__ */ new DocumentDecodeLimits();
  public constructor(options: Partial<Pick<DocumentDecodeLimits, "maximumEncodedBytes" | "maximumDecodedBytes" |
    "maximumLines" | "maximumPlanes" | "maximumRecordBytes">> = {}) {
    const maximumBytes = 64 * 1024 * 1024;
    this.maximumEncodedBytes = options.maximumEncodedBytes ?? maximumBytes;
    this.maximumDecodedBytes = options.maximumDecodedBytes ?? maximumBytes;
    this.maximumLines = options.maximumLines ?? 100_000;
    this.maximumPlanes = options.maximumPlanes ?? 65_536;
    this.maximumRecordBytes = options.maximumRecordBytes ?? 8 * 1024 * 1024;
    for (const [value, ceiling] of [[this.maximumEncodedBytes, maximumBytes], [this.maximumDecodedBytes, maximumBytes],
      [this.maximumLines, 100_000], [this.maximumPlanes, 65_536], [this.maximumRecordBytes, maximumBytes]]) {
      if (value === undefined || ceiling === undefined || !boundedInteger(value, 1, ceiling)) {
        throw new DocumentStorageError("invalidLimits");
      }
    }
    Object.freeze(this);
  }
}

/** A writer checks each append and each escape before allocating the completed result. */
export class BoundedTextWriter {
  private readonly chunks: string[] = [];
  private pending = "";
  private used = 0;
  public constructor(private readonly maximumBytes: number, private readonly signal?: AbortSignal,
    private readonly failure: () => Error = () => new DocumentStorageError("oversizedOutput")) {}
  public append(text: string): void {
    const count = utf8Length(text, this.signal);
    if (count > this.maximumBytes - this.used) throw this.failure();
    this.used += count;
    if (text.length >= 4096) {
      if (this.pending.length > 0) { this.chunks.push(this.pending); this.pending = ""; }
      this.chunks.push(text);
    } else {
      this.pending += text;
      if (this.pending.length >= 4096) { this.chunks.push(this.pending); this.pending = ""; }
    }
  }
  public line(text = ""): void { this.append(text); this.append("\n"); }
  public quoted(text: string, json = false): void {
    this.append('"');
    let start = 0;
    for (let index = 0; index < text.length; index += 1) {
      if (index % 4096 === 0) checkCancellation(this.signal);
      const unit = text.charCodeAt(index);
      let escape: string | undefined;
      if (unit === 34) escape = '\\"';
      else if (unit === 92) escape = "\\\\";
      else if (json && unit < 32) {
        escape = ({ 8: "\\b", 9: "\\t", 10: "\\n", 12: "\\f", 13: "\\r" } as Record<number, string>)[unit] ??
          `\\u${unit.toString(16).padStart(4, "0")}`;
      }
      if (escape !== undefined) { this.append(text.slice(start, index)); this.append(escape); start = index + 1; }
    }
    this.append(text.slice(start));
    this.append('"');
  }
  public finish(): string {
    checkCancellation(this.signal);
    return this.chunks.length === 0 ? this.pending : this.chunks.join("") + this.pending;
  }
}

/**
 * The 2.0 record preflight of storage validation: plane count, per-record limits, scalar line breaks and the running
 * decoded byte budget, in document order. Internal; the structured writer reuses it for its W2 pre-check.
 */
export function validateRecords(document: Document, limits: DocumentDecodeLimits, signal?: AbortSignal): void {
  if (document.planes.length > limits.maximumPlanes) throw new DocumentStorageError("tooManyPlanes");
  let total = 0;
  const charge = (text: string): void => {
    const count = utf8Length(text, signal);
    if (count >= limits.maximumDecodedBytes - total) throw new DocumentStorageError("oversizedOutput");
    total += count + 1;
  };
  const scalar = (text: string): void => {
    if (utf8Length(text, signal) > limits.maximumRecordBytes) throw new DocumentStorageError("oversizedRecord");
    if (text.includes("\n") || text.includes("\r")) throw new DocumentStorageError("invalidDocument", "Scalar fields cannot contain physical line breaks.");
    charge(text);
  };
  scalar(document.version); scalar(document.axis);
  if (document.title !== null) scalar(document.title);
  for (const [key, value] of Object.entries(document.metadata)) { checkCancellation(signal); scalar(key); scalar(value); }
  const body = (text: string): void => {
    if (utf8Length(text, signal) > limits.maximumRecordBytes) throw new DocumentStorageError("oversizedRecord");
    charge(text);
  };
  if (document.preamble !== null) body(document.preamble);
  for (const plane of document.planes) {
    checkCancellation(signal); body(plane.body);
    if (plane.label !== null) scalar(plane.label);
    for (const [key, value] of Object.entries(plane.attributes)) { scalar(key); scalar(value); }
  }
}

function preflightPlanes(source: string, limits: DocumentDecodeLimits, signal?: AbortSignal): void {
  const normalized = source.replace(/\r\n/g, "\n").replace(/^\uFEFF/, "");
  let started = false;
  let body = false;
  let fence: string | undefined;
  let planes = 0;
  let record = 0;
  for (const raw of normalized.split("\n")) {
    checkCancellation(signal);
    const trimmed = trimFoundationWhitespace(raw, signal);
    if (!started) { if (trimmed === "---") started = true; continue; }
    if (!body) { if (trimmed === "---") body = true; continue; }
    let directive = false;
    if (fence !== undefined) { if (trimmed.startsWith(fence.repeat(3))) fence = undefined; }
    else if (trimmed.startsWith("```")) fence = "`";
    else if (trimmed.startsWith("~~~")) fence = "~";
    else if (raw === "@plane" || raw.startsWith("@plane ") || raw.startsWith("@plane\t")) directive = true;
    if (directive) {
      planes += 1; record = 0;
      if (planes > limits.maximumPlanes) throw new DocumentStorageError("tooManyPlanes");
    } else {
      const count = utf8Length(raw, signal);
      if (count > limits.maximumRecordBytes - record) throw new DocumentStorageError("oversizedRecord");
      record += count;
      if (record < limits.maximumRecordBytes) record += 1;
    }
  }
}

function parseBounded(data: Uint8Array, limits: DocumentDecodeLimits, signal?: AbortSignal): Document {
  checkCancellation(signal);
  if (data.byteLength > limits.maximumDecodedBytes) throw new DocumentStorageError("oversizedOutput");
  let lines = 1;
  let record = 0;
  for (let index = 0; index < data.byteLength; index += 1) {
    if (index % 65_536 === 0) checkCancellation(signal);
    if (data[index] === 10) {
      lines += 1; record = 0;
      if (lines > limits.maximumLines) throw new DocumentStorageError("tooManyLines");
    } else if (++record > limits.maximumRecordBytes) throw new DocumentStorageError("oversizedRecord");
  }
  let source: string;
  try { source = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(data); }
  catch { throw new DocumentStorageError("invalidUTF8"); }
  preflightPlanes(source, limits, signal);
  let document: Document;
  try { document = parse(source); }
  catch (error) {
    checkCancellation(signal);
    if (error instanceof ParseError) throw new DocumentStorageError("invalidText", error);
    throw error;
  }
  checkCancellation(signal);
  validateRecords(document, limits, signal);
  return canonicalDocument(document, signal);
}

function canonicalText(document: Document, limits: DocumentDecodeLimits, signal?: AbortSignal): Uint8Array {
  checkCancellation(signal);
  try {
    validateRecords(document, limits, signal);
    document = canonicalDocument(document, signal);
    if (document.version.length === 0) throw new DocumentStorageError("invalidDocument", "The version must be nonempty.");
    const seen = new Set<number>();
    for (const plane of document.planes) {
      checkCancellation(signal);
      if (![plane.z, plane.x ?? 0, plane.y ?? 0].every(Number.isFinite)) throw new DocumentStorageError("invalidDocument", "Plane coordinates must be finite.");
      if (seen.has(plane.z)) throw new DocumentStorageError("invalidDocument", "Plane positions must be unique.");
      seen.add(plane.z);
    }
    const writer = new BoundedTextWriter(limits.maximumDecodedBytes, signal);
    writer.line("---"); writer.append("3md: "); writer.quoted(document.version); writer.line();
    writer.append("axis: "); writer.quoted(document.axis); writer.line();
    if (document.title !== null) { writer.append("title: "); writer.quoted(document.title); writer.line(); }
    for (const key of canonicalKeys(document.metadata)) {
      if (["3md", "axis", "title"].includes(key.toLowerCase()) || key.includes(":") || key.replace(/^[ \t]+/, "").startsWith("#")) {
        throw new DocumentStorageError("invalidDocument", "Metadata keys cannot shadow reserved fields or comments.");
      }
      writer.append(key); writer.append(": "); writer.quoted(document.metadata[key] ?? ""); writer.line();
    }
    writer.line("---");
    if (document.preamble !== null) { writer.line(); writer.line(document.preamble); }
    for (const plane of document.planes) {
      writer.line(); writer.append(`@plane z=${canonicalNumber(plane.z)}`);
      if (plane.label !== null) { writer.append(" label="); writer.quoted(plane.label); }
      if (plane.x !== null) writer.append(` x=${canonicalNumber(plane.x)}`);
      if (plane.y !== null) writer.append(` y=${canonicalNumber(plane.y)}`);
      for (const key of canonicalKeys(plane.attributes)) {
        if (["z", "x", "y", "label"].includes(key.toLowerCase()) || key !== key.toLowerCase() || key.includes("=")) {
          throw new DocumentStorageError("invalidDocument", "Attribute keys must be lowercase and cannot shadow coordinates or labels.");
        }
        writer.append(` ${key}=`); writer.quoted(plane.attributes[key] ?? "");
      }
      writer.line();
      if (plane.body.length > 0) writer.line(plane.body);
    }
    const data = new TextEncoder().encode(writer.finish());
    let restored: Document;
    try { restored = parseBounded(data, limits, signal); }
    catch (error) {
      if (error instanceof DocumentStorageError && error.code === "invalidText") throw new DocumentStorageError("invalidDocument", error.detail);
      throw error;
    }
    if (!documentsEqual(restored, document)) throw new DocumentStorageError("invalidDocument", "Text serialization would change metadata, whitespace, fences or planes.");
    checkCancellation(signal);
    return data;
  } catch (error) {
    checkCancellation(signal);
    if (error instanceof InvalidUnicodeError) throw new DocumentStorageError("invalidDocument", error.message);
    throw error;
  }
}

const MAGIC = /* @__PURE__ */ new Uint8Array([0x33, 0x6d, 0x64, 0x62, 0x69, 0x6e, 0x0d, 0x0a]);
const HEADER_BYTES = 40;

/** Writes the version 1 header (flags 0, reserved 0, equal lengths, compression 0) and the checksum. */
function writeHeader(container: Uint8Array, kind: number, signal?: AbortSignal): void {
  const payloadLength = container.byteLength - HEADER_BYTES;
  container.set(MAGIC);
  const view = new DataView(container.buffer, container.byteOffset, container.byteLength);
  view.setUint16(8, 1, true); view.setUint8(10, kind);
  view.setBigUint64(20, BigInt(payloadLength), true); view.setBigUint64(28, BigInt(payloadLength), true);
  view.setUint32(36, containerChecksum(container, signal), true);
}

/** The 2.0 binary writer after text validation: payload kind 1, byte-identical to ThreeMD 2.0 `.binary`. */
function textContainer(source: Uint8Array, compression: DocumentCompression, limits: DocumentDecodeLimits,
  signal?: AbortSignal): Uint8Array {
  if (limits.maximumEncodedBytes < HEADER_BYTES) throw new DocumentStorageError("oversizedInput");
  if (compression === DocumentCompression.Lzfse) throw new DocumentStorageError("compressionUnavailable", compression);
  if (compression !== DocumentCompression.None) throw new DocumentStorageError("unsupportedCompression", compression);
  if (source.byteLength > limits.maximumEncodedBytes - HEADER_BYTES) throw new DocumentStorageError("oversizedInput");
  const result = new Uint8Array(HEADER_BYTES + source.byteLength);
  result.set(source, HEADER_BYTES);
  writeHeader(result, DocumentPayloadKind.canonicalText, signal);
  checkCancellation(signal);
  return result;
}

/** SPEC.md 11.3.9: payload kind 2, after W1 (limits and cancellation). */
function structuredContainer(document: Document, compression: DocumentCompression, limits: DocumentDecodeLimits,
  signal?: AbortSignal): Uint8Array {
  if (limits.maximumEncodedBytes < HEADER_BYTES) throw new DocumentStorageError("oversizedInput"); // W1b
  const container = writeStructuredPayload(document, limits, signal); // W2 to W4
  if (compression === DocumentCompression.Lzfse) throw new DocumentStorageError("compressionUnavailable", compression); // W5
  if (compression !== DocumentCompression.None) throw new DocumentStorageError("unsupportedCompression", compression);
  writeHeader(container, DocumentPayloadKind.structuredDocument, signal); // W6
  checkCancellation(signal);
  return container;
}

/**
 * Pure bounded storage of a general 3md `Document` as canonical text or in the version 1 binary container, whose
 * payload kind is 1 (canonical UTF-8 3md) or 2 (structured document). This portable implementation deliberately has
 * no LZFSE backend.
 */
export class DocumentStorageCodec {
  public static readonly containerVersion = 1;
  public static readonly headerByteCount = 40;
  /** The payload kinds this release decodes: canonical text (1) and structured documents (2). Frozen. */
  public static readonly supportedPayloadKinds: readonly number[] = /* @__PURE__ */ Object.freeze([1, 2]);
  public static isBinary(data: Uint8Array): boolean {
    return data.byteLength >= MAGIC.byteLength && MAGIC.every((byte, index) => byte === data[index]);
  }
  public static validate(document: Document, limits = DocumentDecodeLimits.standard, signal?: AbortSignal): void {
    checkCancellation(signal);
    limits = new DocumentDecodeLimits(limits);
    canonicalText(document, limits, signal);
  }
  /**
   * Produces canonical readable text, or the version 1 binary container with a structured document payload (payload
   * kind 2). Use `encodeTextContainer` for files that ThreeMD 2.0 must read.
   */
  public static encode(document: Document, format: DocumentStorageFormat = DocumentStorageFormat.text,
    limits = DocumentDecodeLimits.standard, signal?: AbortSignal): Uint8Array {
    checkCancellation(signal);
    limits = new DocumentDecodeLimits(limits);
    if (format.kind === "text") {
      const source = canonicalText(document, limits, signal);
      if (source.byteLength > limits.maximumEncodedBytes) throw new DocumentStorageError("oversizedInput");
      return source;
    }
    return structuredContainer(document, format.compression, limits, signal);
  }
  /**
   * Writes payload kind 1, canonical text behind the binary header, byte-identical to the ThreeMD 2.0 `.binary`
   * output and with the 2.0 binary writer's validation and error order. Use it only for files that ThreeMD 2.0.x must
   * read: `encode` with `DocumentStorageFormat.binary()` writes the structured payload, which is smaller and decodes
   * several times faster.
   * @throws DocumentStorageError exactly as the 2.0 binary writer did, or the AbortSignal reason.
   */
  public static encodeTextContainer(document: Document, compression: DocumentCompression = DocumentCompression.None,
    limits = DocumentDecodeLimits.standard, signal?: AbortSignal): Uint8Array {
    checkCancellation(signal);
    limits = new DocumentDecodeLimits(limits);
    return textContainer(canonicalText(document, limits, signal), compression, limits, signal);
  }
  /**
   * Header-only inspection: reads at most the first 40 bytes and validates neither the fields, the payload nor the
   * checksum.
   * @returns null when the input does not begin with the binary magic.
   * @throws DocumentStorageError("invalidContainer") when the magic is present and fewer than 40 bytes exist.
   */
  public static containerInfo(data: Uint8Array): DocumentContainerInfo | null {
    if (!DocumentStorageCodec.isBinary(data)) return null;
    if (data.byteLength < HEADER_BYTES) throw new DocumentStorageError("invalidContainer");
    const view = new DataView(data.buffer, data.byteOffset, HEADER_BYTES);
    return Object.freeze({
      containerVersion: view.getUint16(8, true), payloadKind: view.getUint8(10), compression: view.getUint8(11),
      flags: view.getUint32(12, true), reserved: view.getUint32(16, true),
      encodedPayloadByteCount: view.getBigUint64(20, true), decodedPayloadByteCount: view.getBigUint64(28, true),
      checksum: view.getUint32(36, true),
    });
  }
  /** Decodes text, or a binary container of payload kind 1 or 2; other kinds throw `unsupportedPayloadKind`. */
  public static decode(data: Uint8Array, limits = DocumentDecodeLimits.standard, signal?: AbortSignal): Document {
    checkCancellation(signal);
    limits = new DocumentDecodeLimits(limits);
    if (data.byteLength > limits.maximumEncodedBytes) throw new DocumentStorageError("oversizedInput");
    if (!this.isBinary(data)) return parseBounded(data, limits, signal);
    if (data.byteLength < HEADER_BYTES) throw new DocumentStorageError("invalidContainer");
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    const version = view.getUint16(8, true);
    if (version !== 1) throw new DocumentStorageError("unsupportedVersion", version);
    const kind = view.getUint8(10);
    if (kind !== DocumentPayloadKind.canonicalText && kind !== DocumentPayloadKind.structuredDocument) {
      throw new DocumentStorageError("unsupportedPayloadKind", kind);
    }
    const compression = view.getUint8(11);
    if (compression !== 0 && compression !== 1) throw new DocumentStorageError("unsupportedCompression", compression);
    const flags = view.getUint32(12, true);
    if (flags !== 0) throw new DocumentStorageError("unsupportedFlags", flags);
    if (view.getUint32(16, true) !== 0) throw new DocumentStorageError("nonzeroReserved");
    const encoded = view.getBigUint64(20, true);
    const decoded = view.getBigUint64(28, true);
    // D10: kind 2 is bounded by the uncompressed container (Emax - 40) and twice the canonical text bound (2 * Dmax),
    // checked before the CRC and before any payload byte is read.
    const bound = kind === DocumentPayloadKind.canonicalText ? limits.maximumDecodedBytes
      : Math.min(limits.maximumEncodedBytes - HEADER_BYTES, 2 * limits.maximumDecodedBytes);
    if (decoded > BigInt(bound)) throw new DocumentStorageError("oversizedOutput");
    if (encoded === 0n || decoded === 0n || encoded !== BigInt(data.byteLength - HEADER_BYTES) ||
      (compression === 0 && encoded !== decoded)) {
      throw new DocumentStorageError("lengthMismatch");
    }
    const checksum = view.getUint32(36, true);
    if (kind === DocumentPayloadKind.canonicalText) {
      // Kind 1 reads the payload once more after the CRC, into one string that it then validates.
      if (containerChecksum(data, signal) !== checksum) throw new DocumentStorageError("checksumMismatch");
      if (compression === 1) throw new DocumentStorageError("compressionUnavailable", DocumentCompression.Lzfse);
      return parseBounded(data.subarray(HEADER_BYTES), limits, signal);
    }
    // Kind 2 validates byte ranges in Phase S and reads them again for Phase Q and the result, so the CRC copies the
    // container into a private buffer as it goes and everything after it reads only that copy (SPEC.md 11.3.16): a
    // caller that changes its buffer during the call, from another thread through a SharedArrayBuffer or from a
    // signal hook, can never make the result hold bytes that were not validated.
    const container = new Uint8Array(data.byteLength);
    if (containerChecksum(data, signal, container) !== checksum) throw new DocumentStorageError("checksumMismatch");
    if (compression === 1) throw new DocumentStorageError("compressionUnavailable", DocumentCompression.Lzfse);
    return readStructured(container, HEADER_BYTES, container.byteLength, limits, true, signal) as Document;
  }
}
