// Payload kind 2, the structured document payload of ThreeMD 2.1 (SPEC.md 11.3), in the TypeScript port.
//
// Sections follow docs/design/threemd-2.1/test-plan.md: goldens (section 1), the 156 vectors (section 2), the unit
// checklist (section 3), the differential properties P1 to P6 at CI volume (section 4) and limits, cancellation and
// buffer ownership (section 5). P4 and P7 compare ports and run in the interchange step.

import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import * as threemd from "../src/index.ts";
import {
  DocumentCompositionCodec, DocumentCompositionLimits, DocumentCompression, DocumentDecodeLimits, DocumentPayloadKind,
  DocumentStorageCodec, DocumentStorageError, DocumentStorageFormat,
  type Document, type DocumentStorageErrorCode, type Plane,
} from "../src/index.ts";
import { containerChecksum, crc32, crc32Update, crc32UpdateBytes } from "../src/checksum.ts";
import { canonicalNumber } from "../src/number.ts";
import { canonicalKeys } from "../src/portable.ts";
import {
  compareCodePoints, decodeUTF8, numberForm, readStructured, structuredProbe, type StructuredMetrics,
} from "../src/structured.ts";

// MARK: - Helpers

const repository = new URL("../../", import.meta.url);
const textDecoder = new TextDecoder();
const encoder = new TextEncoder();
const binary = DocumentStorageFormat.binary();
const standard = DocumentDecodeLimits.standard;

function read(path: string): Uint8Array { return new Uint8Array(readFileSync(fileURLToPath(new URL(path, repository)))); }
function json<Value>(path: string): Value { return JSON.parse(textDecoder.decode(read(path))) as Value; }
function sha256(bytes: Uint8Array): string { return createHash("sha256").update(bytes).digest("hex"); }
function hex(bytes: Uint8Array): string { return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(""); }
function limits(fields: Partial<Record<string, number>> = {}): DocumentDecodeLimits {
  return new DocumentDecodeLimits(fields as ConstructorParameters<typeof DocumentDecodeLimits>[0]);
}

/** The error code of an operation, or "ok". Any exception other than a DocumentStorageError fails the test. */
function codeOf(operation: () => unknown): string {
  try { operation(); return "ok"; } catch (error) {
    if (error instanceof DocumentStorageError) return error.code;
    throw error;
  }
}
function rejects(code: DocumentStorageErrorCode, operation: () => unknown): void {
  let caught: unknown;
  try { operation(); } catch (error) { caught = error; }
  expect(caught).toBeInstanceOf(DocumentStorageError);
  expect((caught as DocumentStorageError).code).toBe(code);
}

/** Exact equality: string keys byte for byte (never NFC), numbers by `Object.is`. */
function sameStrings(left: Readonly<Record<string, string>>, right: Readonly<Record<string, string>>): boolean {
  const a = Object.keys(left).sort();
  const b = Object.keys(right).sort();
  return a.length === b.length && a.every((key, index) => key === b[index] && left[key] === right[key]);
}
function samePlane(left: Plane, right: Plane): boolean {
  return Object.is(left.z, right.z) && Object.is(left.x, right.x) && Object.is(left.y, right.y) &&
    left.label === right.label && left.body === right.body && sameStrings(left.attributes, right.attributes);
}
function sameDocument(left: Document, right: Document): boolean {
  return left.version === right.version && left.axis === right.axis && left.title === right.title &&
    left.preamble === right.preamble && sameStrings(left.metadata, right.metadata) &&
    left.planes.length === right.planes.length && left.planes.every((plane, index) => samePlane(plane, right.planes[index]!));
}
function sameBytes(left: Uint8Array, right: Uint8Array): boolean {
  return left.byteLength === right.byteLength && left.every((byte, index) => byte === right[index]);
}

/** A bytewise, table-free CRC-32/ISO-HDLC, independent of src/checksum.ts. */
function referenceCRC(bytes: Uint8Array, start = 0, end = bytes.byteLength, initial = 0xffffffff): number {
  let value = initial;
  for (let index = start; index < end; index += 1) {
    value ^= bytes[index]!;
    for (let bit = 0; bit < 8; bit += 1) value = (value >>> 1) ^ ((value & 1) === 0 ? 0 : 0xedb88320);
  }
  return value >>> 0;
}

/** Wraps a payload in a complete version 1 container (lengths and CRC sealed), built without the library. */
function seal(payload: readonly number[] | Uint8Array, kind = 2): Uint8Array {
  const output = new Uint8Array(40 + payload.length);
  output.set([0x33, 0x6d, 0x64, 0x62, 0x69, 0x6e, 0x0d, 0x0a], 0);
  output.set(payload, 40);
  const view = new DataView(output.buffer);
  view.setUint16(8, 1, true);
  output[10] = kind;
  view.setBigUint64(20, BigInt(payload.length), true);
  view.setBigUint64(28, BigInt(payload.length), true);
  view.setUint32(36, containerCRC(output), true);
  return output;
}
/** The reference CRC of a container: header bytes 0 ..< 36, then the payload from byte 40. */
function containerCRC(container: Uint8Array): number {
  return (referenceCRC(container, 40, container.byteLength, referenceCRC(container, 0, 36)) ^ 0xffffffff) >>> 0;
}
function resealed(container: Uint8Array): Uint8Array {
  const copy = container.slice();
  new DataView(copy.buffer).setUint32(36, containerCRC(copy), true);
  return copy;
}
function varBytes(value: number): number[] {
  const out: number[] = [];
  while (value >= 0x80) { out.push((value & 0x7f) | 0x80); value >>>= 7; }
  out.push(value);
  return out;
}
function str(value: string | readonly number[]): number[] {
  const bytes = typeof value === "string" ? [...encoder.encode(value)] : [...value];
  return [...varBytes(bytes.length), ...bytes];
}
function record(entries: readonly (readonly [string, string])[]): Record<string, string> {
  const out: Record<string, string> = Object.create(null);
  for (const [key, value] of entries) out[key] = value;
  return out;
}
function plane(z: number, body: string, extra: Partial<Plane> = {}): Plane {
  return { z, label: null, x: null, y: null, attributes: record([]), body, ...extra };
}
function documentOf(planes: readonly Plane[], extra: Partial<Document> = {}): Document {
  return { version: "1", axis: "", title: null, metadata: record([]), preamble: null, planes, ...extra };
}
const encodeStructured = (document: Document, policy = standard): Uint8Array => DocumentStorageCodec.encode(document, binary, policy);
const decode = (bytes: Uint8Array, policy = standard): Document => DocumentStorageCodec.decode(bytes, policy);
const payloadHex = (container: Uint8Array): string => hex(container.subarray(40));

/** mulberry32, the generator of the specification package's fuzzers. */
function generator(seed: number): () => number {
  let state = seed | 0;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Short and long strings with one-, two-, three- and four-byte scalars in every field. */
function mixed20(): Document {
  const text = "a\u00e9\u20ac\u{1F600}";
  return documentOf([plane(0, `${text}\n${"x\u00df".repeat(40)}`, { label: text, attributes: record([[`k${text.toLowerCase()}`, text]]) }),
    plane(1, text.repeat(30))], { title: text, metadata: record([[text, text.repeat(20)]]), preamble: text, axis: "\u00e9" });
}

// MARK: - Fixtures

interface GoldenEntry {
  readonly id: string; readonly set: string; readonly kind: string; readonly sourceFile: string;
  readonly textContainerFile?: string; readonly kind2File: string; readonly bytes: number; readonly payloadBytes: number;
  readonly canonicalBytes: number; readonly sha256: string; readonly crc32: string; readonly planes: number;
  readonly compositionEnvelope: boolean;
}
interface Vector {
  readonly name: string; readonly file: string; readonly rule: string; readonly limits?: Record<string, number>;
  readonly expected: string; readonly expected20: string; readonly errorType: string; readonly requiresNoLZFSE?: boolean;
}
const manifest = json<{ schema: string; counts: Record<string, number>; files: GoldenEntry[] }>("conformance/structured/manifest.json");
const vectors = json<{ schema: string; vectors: Vector[] }>("conformance/structured/vectors.json");
const profileLimits = new DocumentDecodeLimits({
  maximumEncodedBytes: DocumentCompositionLimits.standard.maximumProfileBytes,
  maximumDecodedBytes: DocumentCompositionLimits.standard.maximumProfileBytes, maximumPlanes: 1,
  maximumRecordBytes: DocumentCompositionLimits.standard.maximumProfileBytes,
});

/** The three SPEC.md 11.3.17 worked examples. */
const worked: Record<string, () => Document> = {
  document: () => decode(encoder.encode("---\n3md: \"1.0\"\naxis: \"time\"\ntitle: \"Week\"\nowner: \"ops\"\n---\n\n" +
    "@plane z=0 label=\"Mon\"\n# Standup\n\n@plane z=1.5 label=\"Tue\" x=-2 kind=\"note\"\nShip it\n")),
  numbers: () => documentOf([plane(0.1, "", { x: 0.5, y: 268435456, attributes: record([["note", "say \"hi\""]]) })],
    { version: "1.0", axis: "layer" }),
  keys: () => documentOf([plane(-3, "", { attributes: record([["b", "x"], ["a", "y"]]) })],
    { metadata: record([["z", "1"], ["e\u0301", "2"]]) }),
};

interface Golden { readonly entry: GoldenEntry; readonly file: Uint8Array; readonly expected: Document;
  readonly writerInput: Document; readonly policy: DocumentDecodeLimits; readonly canonical: Uint8Array }
function golden(entry: GoldenEntry): Golden {
  const file = read(entry.kind2File);
  if (entry.set === "worked") {
    const name = entry.id.slice("worked-".length);
    const document = worked[name]!();
    const canonical = DocumentStorageCodec.encode(document);
    return { entry, file, expected: decode(canonical), writerInput: document, policy: standard, canonical };
  }
  const source = read(entry.sourceFile);
  if (entry.kind === "composition") {
    const envelope = DocumentCompositionCodec.document(DocumentCompositionCodec.decode(source));
    const canonical = DocumentCompositionCodec.encode(DocumentCompositionCodec.decode(source));
    return { entry, file, expected: envelope, writerInput: envelope, policy: profileLimits, canonical };
  }
  const canonical = DocumentStorageCodec.encode(decode(source));
  return { entry, file, expected: decode(canonical), writerInput: decode(source), policy: standard, canonical };
}

// MARK: - Section 1: goldens

describe("structured goldens (test-plan section 1)", () => {
  test("the manifest lists 49 interchange anchors, 2 examples and 3 worked examples", () => {
    expect(manifest.schema).toBe("3md-structured-golden-1");
    expect(manifest.files).toHaveLength(54);
    expect(manifest.counts).toEqual({ interchange: 49, examples: 2, worked: 3 });
    expect(manifest.files.filter((entry) => entry.textContainerFile !== undefined)).toHaveLength(24);
  });

  for (const entry of manifest.files) {
    test(`${entry.id}: writer bytes, decode, re-encode, header, kind-1 sibling, SHA-256`, () => {
      const { file, expected, writerInput, policy, canonical } = golden(entry);
      expect(sha256(file)).toBe(entry.sha256); // 7
      expect(file.byteLength).toBe(entry.bytes);
      expect(entry.payloadBytes).toBe(entry.bytes - 40);
      expect(canonical.byteLength).toBe(entry.canonicalBytes);
      expect(hex(encodeStructured(writerInput, policy))).toBe(hex(file)); // 1
      expect(hex(encodeStructured(expected, policy))).toBe(hex(file));
      const decoded = decode(file);
      expect(sameDocument(decoded, expected)).toBe(true); // 2
      expect(decoded.planes).toHaveLength(entry.planes);
      expect(hex(encodeStructured(decoded))).toBe(hex(file)); // 3
      const length = BigInt(entry.bytes - 40); // 4
      expect(DocumentStorageCodec.containerInfo(file)).toEqual({ containerVersion: 1, payloadKind: 2, compression: 0,
        flags: 0, reserved: 0, encodedPayloadByteCount: length, decodedPayloadByteCount: length,
        checksum: Number.parseInt(entry.crc32, 16) });
      expect(containerCRC(file)).toBe(Number.parseInt(entry.crc32, 16));
      if (entry.textContainerFile !== undefined) { // 5
        const textContainer = read(entry.textContainerFile);
        expect(sameDocument(decode(textContainer), expected)).toBe(true);
        expect(hex(DocumentStorageCodec.encodeTextContainer(writerInput))).toBe(hex(textContainer));
        expect(DocumentStorageCodec.containerInfo(textContainer)?.payloadKind).toBe(DocumentPayloadKind.canonicalText);
      }
      if (entry.compositionEnvelope) { // 6
        const fromSource = DocumentCompositionCodec.decode(read(entry.sourceFile));
        const fromEnvelope = DocumentCompositionCodec.decode(file);
        expect(fromEnvelope).toEqual(fromSource);
        expect(hex(DocumentCompositionCodec.encode(fromEnvelope))).toBe(hex(canonical));
      }
    });
  }

  test("the worked document has the metrics of SPEC.md 11.3.17 and the annotated bytes", () => {
    const file = read("conformance/structured/worked-document.3mdb");
    // SPEC.md 11.3.17, example 1, field by field.
    expect(hex(file)).toBe(["33 6d 64 62 69 6e 0d 0a", "01 00", "02", "00", "00 00 00 00", "00 00 00 00",
      "49 00 00 00 00 00 00 00", "49 00 00 00 00 00 00 00", "70 3b 5b 8a", "01", "03 31 2e 30", "04 74 69 6d 65",
      "04 57 65 65 6b", "01", "05 6f 77 6e 65 72", "03 6f 70 73", "02", "41", "00", "03 4d 6f 6e", "00",
      "09 23 20 53 74 61 6e 64 75 70", "46", "00 00 c0 3f", "03", "03 54 75 65", "01", "04 6b 69 6e 64", "04 6e 6f 74 65",
      "07 53 68 69 70 20 69 74"].join("").replaceAll(" ", ""));
    const metrics: StructuredMetrics = { textLength: 0, lines: 0, longestFrontmatterLine: 0, directiveLengths: [] };
    readStructured(file, 40, file.byteLength, standard, true, undefined, metrics);
    expect(metrics.textLength).toBe(144);
    expect(metrics.lines).toBe(13);
    expect(metrics.directiveLengths).toEqual([22, 41]);
    expect(hex(read("conformance/structured/worked-numbers.3mdb").subarray(40))).toBe(
      "0003312e30056c61796572" + "00012b9a9999999999b93f0000003f0000804d01046e6f7465087361792022686922" + "00");
    expect(hex(read("conformance/structured/worked-keys.3mdb").subarray(40))).toBe(
      "000131000203" + "65cc810132017a013101010502016101790162017800");
    rejects("invalidContainer", () => decode(seal([0x00, ...str("1"), 0x00, 0x02, ...str("z"), ...str("1"),
      ...str("e\u0301"), ...str("2"), 0x01, 0x01, 0x05, 0x02, ...str("a"), ...str("y"), ...str("b"), ...str("x"), 0x00])));
  });
});

// MARK: - Section 2: vectors

describe("structured vectors (test-plan section 2)", () => {
  test("the manifest holds 156 vectors: 29 with limits, 25 ok, 131 typed errors", () => {
    expect(vectors.schema).toBe("3md-structured-vectors-1");
    expect(vectors.vectors).toHaveLength(156);
    expect(vectors.vectors.filter((vector) => vector.limits !== undefined)).toHaveLength(29);
    expect(vectors.vectors.filter((vector) => vector.expected === "ok")).toHaveLength(25);
    expect(vectors.vectors.filter((vector) => vector.errorType === "DocumentStorageError")).toHaveLength(131);
  });

  for (const vector of vectors.vectors) {
    test(`${vector.name} (${vector.rule}) gives ${vector.expected}`, () => {
      const bytes = read(vector.file);
      const policy = limits(vector.limits);
      // No LZFSE backend exists in TypeScript, so the requiresNoLZFSE vector applies here too.
      expect(codeOf(() => decode(bytes, policy))).toBe(vector.expected);
      if (vector.expected === "ok") {
        // Canonical encoding: decode(x, L) succeeds, so encode(decode(x, L), L) is x.
        expect(hex(encodeStructured(decode(bytes, policy), policy))).toBe(hex(bytes));
      }
    });
  }
});

// MARK: - Section 3: unit checklist

describe("structured unit checklist (test-plan section 3)", () => {
  test("Var encodes and decodes minimally at every byte-count boundary", () => {
    const cases: [number, string][] = [[0, "00"], [127, "7f"], [128, "8001"], [16_383, "ff7f"], [16_384, "808001"],
      [2_097_151, "ffff7f"], [2_097_152, "80808001"], [268_435_455, "ffffff7f"]];
    for (const [zigzag, bytes] of cases) {
      // A form-1 z whose zigzag value is the boundary (every 28-bit value is a zigzag of an integer-form value).
      const z = zigzag % 2 === 0 ? zigzag / 2 : -(zigzag + 1) / 2;
      const container = encodeStructured(documentOf([plane(z, "")]));
      expect(payloadHex(container)).toBe(`00013100000101${bytes}0000`);
      expect(decode(container).planes[0]?.z).toBe(z);
    }
    for (const length of [0, 127, 128, 16_383, 16_384, 2_097_151, 2_097_152]) {
      const body = "b".repeat(length);
      const container = encodeStructured(documentOf([plane(0, body)]));
      expect(hex(container.subarray(49, 49 + varBytes(length).length))).toBe(hex(new Uint8Array(varBytes(length))));
      expect(decode(container).planes[0]?.body).toBe(body);
    }
  });

  test("Var rejections V1 to V3", () => {
    const withZ = (bytes: number[]): Uint8Array => seal([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, ...bytes, 0x00, 0x00]);
    rejects("invalidContainer", () => decode(withZ([0x81, 0x00]))); // V3
    rejects("invalidContainer", () => decode(withZ([0x80, 0x00]))); // V3
    rejects("invalidContainer", () => decode(withZ([0xff, 0xff, 0xff, 0xff, 0x01]))); // V2
    rejects("invalidContainer", () => decode(seal([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0xff, 0xff, 0xff, 0x80]))); // V2
    rejects("lengthMismatch", () => decode(seal([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x80]))); // V1
    rejects("lengthMismatch", () => decode(seal([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0xff, 0xff]))); // V1
  });

  test("number forms follow SPEC.md 11.3.3 and every encoding decodes bit for bit", () => {
    const table: [number, number][] = [[0, 1], [-0, 1], [1, 1], [-1, 1], [2 ** 27 - 1, 1], [-(2 ** 27), 1],
      [2 ** 27, 2], [-(2 ** 27) - 1, 3], [2 ** 24 + 1, 1], [0.5, 2], [0.1, 3], [1.5, 2], [2 ** 53, 2], [2 ** 53 + 2, 3],
      [5e-324, 3], [1.401298464324817e-45, 2], [3.4028234663852886e38, 2], [1.7976931348623157e308, 3], [2 ** -140, 2],
      [1e15, 3], [1e16, 3], [1e-7, 3], [Infinity, 2], [-Infinity, 2], [NaN, 3]];
    for (const [value, form] of table) expect(numberForm(value), String(value)).toBe(form);
    expect(numberForm(-(2 ** 27) - 16)).toBe(2);
    expect(numberForm(-(2 ** 27) - 2)).toBe(3);
    let z = 0;
    for (const [value] of table) {
      if (!Number.isFinite(value)) continue;
      const normal = value === 0 ? 0 : value;
      const document = documentOf([plane(z += 1, "", { x: value, y: -normal })]);
      const decoded = decode(encodeStructured(document)).planes[0];
      expect(Object.is(decoded?.x, normal)).toBe(true);
      expect(Object.is(decoded?.y, normal === 0 ? 0 : -normal)).toBe(true);
    }
    // Zigzag at the edges of the integer range.
    for (const value of [-(2 ** 27), -(2 ** 27) + 1, -1, 0, 1, 2 ** 27 - 2, 2 ** 27 - 1]) {
      expect(decode(encodeStructured(documentOf([plane(value, "")]))).planes[0]?.z).toBe(value);
    }
    // -0 is written as +0 (zigzag 00).
    const negativeZero = encodeStructured(documentOf([plane(-0, "a")]));
    expect(payloadHex(negativeZero)).toBe("0001310000010100000161");
    expect(Object.is(decode(negativeZero).planes[0]?.z, 0)).toBe(true);
  });

  test("CRC check value, slicing against a bytewise reference, and container checksums", () => {
    expect(crc32(encoder.encode("123456789"))).toBe(0xcbf43926);
    expect(crc32(new Uint8Array(0))).toBe(0);
    const random = generator(0xc3c32021);
    const backing = new Uint8Array(316);
    for (let round = 0; round < 10_000; round += 1) {
      const length = Math.floor(random() * 301);
      const alignment = round % 16;
      for (let index = 0; index < length + alignment; index += 1) backing[index] = Math.floor(random() * 256);
      const view = backing.subarray(alignment, alignment + length);
      const expected = referenceCRC(view) ^ 0xffffffff;
      expect(crc32(view)).toBe(expected >>> 0);
      expect((crc32UpdateBytes(-1, view, 0, length) ^ -1) >>> 0).toBe(expected >>> 0); // the big-endian path
      const split = Math.floor(random() * (length + 1));
      expect((crc32Update(crc32Update(-1, view, 0, split), view, split, length) ^ -1) >>> 0).toBe(expected >>> 0);
    }
    const container = new Uint8Array(40 + 200_000);
    for (let index = 0; index < container.byteLength; index += 1) container[index] = (index * 131 + 7) & 0xff;
    expect(containerChecksum(container)).toBe(containerCRC(container));
  });

  test("chunked UTF-8 validation agrees with whole-string validation at every chunk boundary", () => {
    const fatal = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
    const whole = (bytes: Uint8Array): string | null => { try { return fatal.decode(bytes); } catch { return null; } };
    const chunked = (bytes: Uint8Array): string | null => {
      try { return decodeUTF8(bytes, 0, bytes.byteLength); } catch (error) {
        expect((error as DocumentStorageError).code).toBe("invalidUTF8");
        return null;
      }
    };
    const scalar = [0xf0, 0x9f, 0x98, 0x80]; // U+1F600
    let compared = 0;
    for (const length of [65_535, 65_536, 65_537, 200_000]) {
      const boundaries = [...new Set([65_536, 131_072, length])].filter((boundary) => boundary <= length);
      for (const boundary of boundaries) {
        for (let shift = 0; shift <= 4; shift += 1) {
          const at = boundary - shift;
          if (at < 0 || at + 4 > length) continue;
          const bytes = new Uint8Array(length).fill(0x61);
          bytes.set(scalar, at);
          expect(chunked(bytes)).toBe(whole(bytes));
          expect(whole(bytes)).not.toBeNull();
          for (const cut of [1, 2, 3]) { // the scalar truncated: ill-formed in both
            const broken = bytes.slice();
            broken[at + cut] = 0x61;
            expect(chunked(broken)).toBeNull();
            expect(whole(broken)).toBeNull();
          }
          const extra = bytes.slice(); // a fifth continuation byte
          if (at + 4 < length) { extra[at + 4] = 0x80; expect(chunked(extra)).toBe(whole(extra)); }
          compared += 1;
        }
      }
      const tail = new Uint8Array(length).fill(0x62);
      tail.set([0xe2, 0x82], length - 2); // ends inside a scalar
      expect(chunked(tail)).toBeNull();
      expect(whole(tail)).toBeNull();
    }
    expect(compared).toBe(16);
  });

  test("segment rules G1 to G6 on hand cases", () => {
    const outcome = (body: string, final = true): string => codeOf(() =>
      encodeStructured(documentOf(final ? [plane(0, body)] : [plane(0, body), plane(1, "end")])));
    const preamble = (text: string): string => codeOf(() => encodeStructured(documentOf([plane(0, "a")], { preamble: text })));
    expect(preamble("")).toBe("invalidDocument"); // G1
    expect(outcome("")).toBe("ok");
    expect(outcome("a\r")).toBe("invalidDocument"); // G2
    expect(outcome("a\rb")).toBe("ok");
    expect(outcome("a\r\nb")).toBe("invalidDocument"); // G3
    for (const body of ["\nb", "b\n", " \nb", "b\n\t", "\u00a0\nb", "b\n\u3000", "\u2000\u200b"]) expect(outcome(body)).toBe("invalidDocument"); // G4
    for (const body of ["\u0085\nb", "b\n\u200c", "\ufeff"]) expect(outcome(body)).toBe("ok"); // not in W
    for (const body of ["a\n@plane", "a\n@plane z=2", "a\n@plane\tz=2"]) expect(outcome(body)).toBe("invalidDocument"); // G5
    for (const body of ["a\n @plane z=2", "a\n@planet", "```\n~~~\n@plane z=1", "\u00a0```\n@plane z=1\n```", "~~~~\n@plane\n~~~"]) {
      expect(outcome(body)).toBe("ok");
    }
    expect(outcome("~~~\n```\n~~~\n@plane z=1")).toBe("invalidDocument");
    expect(outcome("```\ncode", false)).toBe("invalidDocument"); // G6
    expect(outcome("```\ncode\n```", false)).toBe("ok");
    expect(outcome("```\ncode")).toBe("ok");
    expect(preamble("```\ncode")).toBe("invalidDocument");
  });

  test("segment scanner agrees with the 2.0 parser round trip on 100,000 random bodies", () => {
    const random = generator(0x5e6e2101);
    const pick = <Value>(items: readonly Value[]): Value => items[Math.floor(random() * items.length)]!;
    const pieces = ["", " ", "\t", "\u00a0", "\u3000", "\u2028", "\u0085", "text", "@plane", "@plane z=1", "@plane\tz", "@planet",
      " @plane z=1", "```", "~~~", "  ```js", "\u3000~~~", "``", "~~ ~", "````", "\r", "a\r", "# h", "---", "x\u200b", "\u200b",
      "caf\u00e9", "\ufeff", "[[z=1]]", "\u00a0@plane", "a  b"];
    let accepted = 0;
    for (let round = 0; round < 100_000; round += 1) {
      let text = "";
      const count = 1 + Math.floor(random() * 5);
      for (let line = 0; line < count; line += 1) text += (line === 0 ? "" : random() < 0.08 ? "\r\n" : "\n") + pick(pieces);
      if (random() < 0.04) text += "\r";
      const role = Math.floor(random() * 3);
      const document = role === 0 ? documentOf([plane(0, "a")], { preamble: text })
        : role === 1 ? documentOf([plane(0, text), plane(1, "end")]) : documentOf([plane(0, text)]);
      const text20 = codeOf(() => DocumentStorageCodec.validate(document));
      const structured = codeOf(() => encodeStructured(document));
      if ((text20 === "ok") !== (structured === "ok")) {
        throw new Error(`segment disagreement for role ${role}: ${JSON.stringify(text)} text ${text20} kind 2 ${structured}`);
      }
      if (structured === "ok") accepted += 1;
    }
    expect(accepted).toBeGreaterThan(5_000);
  }, 120_000);

  test("canonical text metrics equal the 2.0 writer on every Example and 100,000 generated documents", () => {
    const check = (document: Document): void => {
      const canonical = DocumentStorageCodec.encode(document);
      const container = encodeStructured(document);
      const metrics: StructuredMetrics = { textLength: 0, lines: 0, longestFrontmatterLine: 0, directiveLengths: [] };
      readStructured(container, 40, container.byteLength, standard, false, undefined, metrics);
      const text = textDecoder.decode(canonical);
      const lines = text.split("\n");
      expect(metrics.textLength).toBe(canonical.byteLength);
      expect(metrics.lines).toBe(lines.length);
      const closing = lines.indexOf("---", 1);
      const frontmatter = Math.max(...lines.slice(1, closing).map((line) => encoder.encode(line).byteLength));
      expect(metrics.longestFrontmatterLine).toBe(frontmatter);
      const quote = (value: string): string => `"${value.replace(/[\\"]/g, "\\$&")}"`;
      const decoded = decode(canonical);
      expect(metrics.directiveLengths).toEqual(decoded.planes.map((item) => {
        let line = `@plane z=${canonicalNumber(item.z)}`;
        if (item.label !== null) line += ` label=${quote(item.label)}`;
        if (item.x !== null) line += ` x=${canonicalNumber(item.x)}`;
        if (item.y !== null) line += ` y=${canonicalNumber(item.y)}`;
        for (const key of canonicalKeys(item.attributes)) line += ` ${key}=${quote(item.attributes[key]!)}`;
        expect(lines).toContain(line);
        return encoder.encode(line).byteLength;
      }));
    };
    const examples = fileURLToPath(new URL("Examples/", repository));
    const names = readdirSync(examples).filter((name) => name.endsWith(".3md"));
    expect(names).toHaveLength(293);
    for (const name of names) check(decode(new Uint8Array(readFileSync(join(examples, name)))));
    const random = generator(0x3e7a1c50);
    let checked = 0;
    while (checked < 100_000) {
      const document = representable(random);
      if (codeOf(() => encodeStructured(document)) !== "ok") continue;
      check(document);
      checked += 1;
    }
  }, 300_000);

  test("byte-order keys: code point order equals UTF-8 byte order, never UTF-16 order", () => {
    const random = generator(0x6b657973);
    const alphabet = [0x41, 0x61, 0x7a, 0xe9, 0x301, 0x7ff, 0x800, 0xd7ff, 0xe000, 0xff61, 0xffff, 0x10000, 0x1f600, 0x10ffff];
    const randomKey = (): string => {
      let key = "";
      const length = 1 + Math.floor(random() * 4);
      for (let index = 0; index < length; index += 1) key += String.fromCodePoint(alphabet[Math.floor(random() * alphabet.length)]!);
      return key;
    };
    const sign = (value: number): number => (value > 0 ? 1 : value < 0 ? -1 : 0);
    let differsFromUTF16 = 0;
    for (let round = 0; round < 100_000; round += 1) {
      const left = randomKey();
      const right = randomKey();
      const bytes = sign(Buffer.compare(Buffer.from(left, "utf8"), Buffer.from(right, "utf8")));
      expect(sign(compareCodePoints(left, right))).toBe(bytes);
      if (sign(left < right ? -1 : left > right ? 1 : 0) !== bytes) differsFromUTF16 += 1;
    }
    expect(differsFromUTF16).toBeGreaterThan(0);
    // The writer sorts by code point; the reader requires strictly increasing bytes.
    const container = encodeStructured(documentOf([], { metadata: record([["\u{1f600}", "1"], ["\uff61", "2"], ["z", "3"]]) }));
    expect(payloadHex(container)).toBe("0001310003017a0133" + "03efbda10132" + "04f09f98800131" + "00");
  });

  test("key equivalence matches normalize(\"NFC\") on decode", () => {
    const pairs: [string, string][] = [["e\u0301", "\u00e9"], ["K", "\u212a"], ["\u00c5", "\u212b"], ["a", "b"],
      ["\u1e9b\u0323", "\u1e69"], ["q\u0307\u0323", "q\u0323\u0307"], ["\uac00", "\u1100\u1161"], ["x\u0308", "x"]];
    for (const [first, second] of pairs) {
      const [low, high] = compareCodePoints(first, second) < 0 ? [first, second] : [second, first];
      const equivalent = low.normalize("NFC") === high.normalize("NFC");
      const metadata = seal([0x00, ...str("1"), 0x00, 0x02, ...str(low), ...str("1"), ...str(high), ...str("2"), 0x00]);
      expect(codeOf(() => decode(metadata))).toBe(equivalent ? "invalidDocument" : "ok");
      const attributes = seal([0x00, ...str("1"), 0x00, 0x00, 0x01, 0x01, 0x00, 0x02, ...str(low.toLowerCase()), ...str("1"),
        ...str(high.toLowerCase()), ...str("2"), 0x00]);
      if (compareCodePoints(low.toLowerCase(), high.toLowerCase()) < 0) {
        const lowerEquivalent = low.toLowerCase().normalize("NFC") === high.toLowerCase().normalize("NFC");
        const outcome = codeOf(() => decode(attributes));
        if (lowerEquivalent) expect(outcome).toBe("invalidDocument");
      }
    }
  });

  test("numeric-powers.json: 4,318 canonical spellings", () => {
    const fixture = json<{ schema: string; vectors: { name: string; bitPattern: string; formatted: string }[] }>(
      "conformance/extensions/numeric-powers.json");
    expect(fixture.schema).toBe("3md-canonical-numbers-1");
    expect(fixture.vectors).toHaveLength(4_318);
    const view = new DataView(new ArrayBuffer(8));
    for (const vector of fixture.vectors) {
      view.setBigUint64(0, BigInt(`0x${vector.bitPattern}`));
      const value = view.getFloat64(0);
      expect(canonicalNumber(value), vector.name).toBe(vector.formatted);
      expect(threemd.serialize(documentOf([plane(value, "")]))).toContain(`@plane z=${vector.formatted}\n`);
    }
  });

  test("containerInfo reports raw header fields without validating them", () => {
    expect(DocumentStorageCodec.containerInfo(encoder.encode("---\n3md: 1\n---\n"))).toBeNull();
    expect(DocumentStorageCodec.containerInfo(encoder.encode("3MDB"))).toBeNull();
    expect(DocumentStorageCodec.containerInfo(encoder.encode("3mdbin\r"))).toBeNull();
    const file = encodeStructured(documentOf([plane(0, "a")]));
    for (let length = 8; length < 40; length += 1) rejects("invalidContainer", () => DocumentStorageCodec.containerInfo(file.subarray(0, length)));
    const odd = file.slice();
    const view = new DataView(odd.buffer);
    view.setUint16(8, 7, true); odd[10] = 0x7f; odd[11] = 9; view.setUint32(12, 0xdeadbeef, true); view.setUint32(16, 5, true);
    view.setBigUint64(20, 0xffffffffffffffffn, true); view.setBigUint64(28, 3n, true);
    const info = DocumentStorageCodec.containerInfo(odd.subarray(0, 40));
    expect(info).toEqual({ containerVersion: 7, payloadKind: 0x7f, compression: 9, flags: 0xdeadbeef, reserved: 5,
      encodedPayloadByteCount: 0xffffffffffffffffn, decodedPayloadByteCount: 3n, checksum: view.getUint32(36, true) });
    expect(Object.isFrozen(info)).toBe(true);
    const padded = new Uint8Array(file.byteLength + 5);
    padded.set(file, 3);
    expect(DocumentStorageCodec.containerInfo(padded.subarray(3, 3 + file.byteLength))?.payloadKind).toBe(2);
  });

  test("encodeTextContainer keeps the 2.0 binary writer's bytes and error order", () => {
    for (const entry of manifest.files) {
      if (entry.textContainerFile === undefined) continue;
      const { writerInput } = golden(entry);
      expect(hex(DocumentStorageCodec.encodeTextContainer(writerInput))).toBe(hex(read(entry.textContainerFile)));
    }
    const valid = documentOf([plane(0, "a")]);
    const size = DocumentStorageCodec.encodeTextContainer(valid).byteLength;
    rejects("invalidDocument", () => DocumentStorageCodec.encodeTextContainer({ ...valid, version: "" }, DocumentCompression.Lzfse));
    rejects("oversizedInput", () => DocumentStorageCodec.encodeTextContainer(valid, DocumentCompression.Lzfse, limits({ maximumEncodedBytes: 39 })));
    rejects("compressionUnavailable", () => DocumentStorageCodec.encodeTextContainer(valid, DocumentCompression.Lzfse, limits({ maximumEncodedBytes: 40 })));
    rejects("unsupportedCompression", () => DocumentStorageCodec.encodeTextContainer(valid, 7 as DocumentCompression, limits({ maximumEncodedBytes: 40 })));
    rejects("oversizedInput", () => DocumentStorageCodec.encodeTextContainer(valid, DocumentCompression.None, limits({ maximumEncodedBytes: size - 1 })));
    expect(DocumentStorageCodec.encodeTextContainer(valid, DocumentCompression.None, limits({ maximumEncodedBytes: size })).byteLength).toBe(size);
    rejects("oversizedOutput", () => DocumentStorageCodec.encodeTextContainer(valid, DocumentCompression.None, limits({ maximumDecodedBytes: 20 })));
    rejects("invalidLimits", () => DocumentStorageCodec.encodeTextContainer(valid, DocumentCompression.None, { ...standard, maximumLines: 0 }));
    const abort = new AbortController();
    const reason = new Error("stop");
    abort.abort(reason);
    expect(() => DocumentStorageCodec.encodeTextContainer(valid, undefined, undefined, abort.signal)).toThrow(reason);
  });

  test("writer edges: W1b, the exact Emax cap, compression after the self-check", () => {
    const valid = documentOf([plane(0, "a")]);
    const file = encodeStructured(valid);
    rejects("oversizedInput", () => encodeStructured(valid, limits({ maximumEncodedBytes: 39 })));
    expect(hex(encodeStructured(valid, limits({ maximumEncodedBytes: file.byteLength })))).toBe(hex(file));
    rejects("oversizedInput", () => encodeStructured(valid, limits({ maximumEncodedBytes: file.byteLength - 1 })));
    rejects("unsupportedCompression", () => DocumentStorageCodec.encode(valid, DocumentStorageFormat.binary(7 as DocumentCompression)));
    rejects("compressionUnavailable", () => DocumentStorageCodec.encode(valid, DocumentStorageFormat.binary(DocumentCompression.Lzfse)));
    rejects("invalidDocument", () => DocumentStorageCodec.encode({ ...valid, version: "" }, DocumentStorageFormat.binary(DocumentCompression.Lzfse)));
    rejects("invalidDocument", () => DocumentStorageCodec.encode(documentOf([plane(0, "a"), plane(0, "b")]),
      DocumentStorageFormat.binary(7 as DocumentCompression)));
    // Non-finite coordinates are emitted (infinity as form 2, NaN as form 3) and rejected by the self-check (W4).
    for (const value of [Infinity, -Infinity, NaN]) {
      rejects("invalidDocument", () => encodeStructured(documentOf([plane(value, "a")])));
      rejects("invalidDocument", () => encodeStructured(documentOf([plane(0, "a", { y: value })])));
    }
    const nanSize = 40 + 6 + 1 + 8 + 2; // a NaN z takes form 3: 8 bytes
    rejects("oversizedInput", () => encodeStructured(documentOf([plane(NaN, "")]), limits({ maximumEncodedBytes: nanSize - 2 })));
    rejects("invalidDocument", () => encodeStructured(documentOf([plane(NaN, "")]), limits({ maximumEncodedBytes: nanSize })));
    // Record limits are enforced by the self-check under the same limits.
    rejects("oversizedRecord", () => encodeStructured(documentOf([plane(0, "abcdef")]), limits({ maximumRecordBytes: 5 })));
    rejects("tooManyPlanes", () => encodeStructured(documentOf([plane(0, ""), plane(1, "")]), limits({ maximumPlanes: 1 })));
    rejects("invalidLimits", () => encodeStructured(valid, { ...standard, maximumPlanes: 1.5 }));
  });

  test("TypeScript writer: lone surrogates, equivalent-key merge, dropped values and __proto__", () => {
    const base = documentOf([plane(0, "a", { label: "l", attributes: record([["k", "v"]]) })], { title: "t", preamble: "p",
      metadata: record([["m", "v"]]) });
    const lone = "\ud800";
    const variants: Document[] = [
      { ...base, version: lone }, { ...base, axis: lone }, { ...base, title: lone }, { ...base, preamble: lone },
      { ...base, metadata: record([[lone, "v"]]) }, { ...base, metadata: record([["m", `x${lone}`]]) },
      { ...base, planes: [{ ...base.planes[0]!, label: "\udc00" }] }, { ...base, planes: [{ ...base.planes[0]!, body: `a${lone}` }] },
      { ...base, planes: [{ ...base.planes[0]!, attributes: record([[lone, "v"]]) }] },
      { ...base, planes: [{ ...base.planes[0]!, attributes: record([["k", lone]]) }] },
    ];
    for (const variant of variants) {
      let caught: unknown;
      try { encodeStructured(variant); } catch (error) { caught = error; }
      expect((caught as DocumentStorageError).code).toBe("invalidDocument");
      expect((caught as DocumentStorageError).detail).toBe("Strings must contain losslessly representable Unicode scalar values.");
      expect(codeOf(() => DocumentStorageCodec.validate(variant))).toBe("invalidDocument");
    }
    const merged = encodeStructured(documentOf([], { metadata: record([["e\u0301", "first"], ["\u00e9", "last"]]) }));
    expect(payloadHex(merged)).toBe("00013100010365cc81046c61737400");
    expect(decode(merged).metadata).toEqual(record([["e\u0301", "last"]]));
    const attributes = encodeStructured(documentOf([plane(0, "", { attributes: record([["\u00e9", "first"], ["e\u0301", "last"]]) })]));
    expect(decode(attributes).planes[0]?.attributes).toEqual(record([["\u00e9", "last"]]));
    // A lone surrogate in a value or spelling that the merge drops still fails, as in the 2.0 validate.
    for (const document of [documentOf([], { metadata: record([["e\u0301", lone], ["\u00e9", "last"]]) }),
      documentOf([plane(0, "", { attributes: record([["e\u0301", "\udfff"], ["\u00e9", "x"]]) })])]) {
      expect(codeOf(() => DocumentStorageCodec.validate(document))).toBe("invalidDocument");
      expect(codeOf(() => encodeStructured(document))).toBe("invalidDocument");
    }
    // The pre-check also applies 2.0 record limits to dropped values.
    const dropped = documentOf([], { metadata: record([["e\u0301", "x".repeat(50)], ["\u00e9", "y"]]) });
    expect(codeOf(() => DocumentStorageCodec.validate(dropped, limits({ maximumRecordBytes: 40 })))).toBe("oversizedRecord");
    expect(codeOf(() => encodeStructured(dropped, limits({ maximumRecordBytes: 40 })))).toBe("oversizedRecord");
    const proto = JSON.parse('{"__proto__":"value","constructor":"c"}') as Record<string, string>;
    const decoded = decode(encodeStructured(documentOf([plane(0, "", { attributes: proto })], { metadata: proto })));
    for (const map of [decoded.metadata, decoded.planes[0]!.attributes]) {
      expect(Object.hasOwn(map, "__proto__")).toBe(true);
      expect(map["__proto__"]).toBe("value");
      expect(Object.getPrototypeOf(map)).toBeNull();
    }
  });

  test("the portable utf8Length path, where String.prototype.isWellFormed is missing, writes the same bytes", () => {
    const documents = [mixed20(), ...manifest.files.slice(0, 20).map((entry) => golden(entry).expected)];
    const expected = documents.map((document) => hex(encodeStructured(document)));
    const lone = documentOf([plane(0, "\u00e9\ud800")]);
    const prototype = String.prototype as { isWellFormed?: (() => boolean) | undefined };
    const original = prototype.isWellFormed;
    delete prototype.isWellFormed;
    try {
      expect(typeof "".isWellFormed).toBe("undefined");
      expect(documents.map((document) => hex(encodeStructured(document)))).toEqual(expected);
      rejects("invalidDocument", () => encodeStructured(lone));
    } finally {
      prototype.isWellFormed = original;
    }
    rejects("invalidDocument", () => encodeStructured(lone));
  });

  test("decoded values have the 2.0 bounded decoder's shape", () => {
    const decoded = decode(read("conformance/structured/worked-document.3mdb"));
    expect(Object.keys(decoded)).toEqual(["version", "axis", "title", "metadata", "preamble", "planes"]);
    expect(Object.keys(decoded.planes[1]!)).toEqual(["z", "label", "x", "y", "attributes", "body"]);
    expect(Object.getPrototypeOf(decoded.metadata)).toBeNull();
    expect(Object.isFrozen(decoded) || Object.isFrozen(decoded.planes)).toBe(false);
    expect(decoded.planes[0]).toEqual({ z: 0, label: "Mon", x: null, y: null, attributes: record([]), body: "# Standup" });
    const text = decode(DocumentStorageCodec.encode(decoded));
    expect(sameDocument(decoded, text)).toBe(true);
  });

  test("Unicode skew vectors outside Unicode 13.0 (recorded for the runtime's Unicode data)", () => {
    const major = Number((process.versions.unicode ?? "0").split(".")[0]);
    // U+0897 (ccc 230 since Unicode 16) after U+0316 (ccc 220) is canonically equivalent to its reordered form.
    const low = "a\u0316\u0897";
    const high = "a\u0897\u0316";
    const keys = seal([0x00, ...str("1"), 0x00, 0x02, ...str(low), ...str("1"), ...str(high), ...str("2"), 0x00]);
    expect(codeOf(() => decode(keys))).toBe(major >= 16 ? "invalidDocument" : "ok");
    // The Garay case pair (Unicode 16): an uppercase attribute key fails R9.
    const garay = (key: string): Uint8Array => seal([0x00, ...str("1"), 0x00, 0x00, 0x01, 0x01, 0x00, 0x01, ...str(key), ...str("v"), 0x00]);
    expect(codeOf(() => decode(garay("\u{10d50}")))).toBe(major >= 16 ? "invalidDocument" : "ok");
    expect(codeOf(() => decode(garay("\u{10d70}")))).toBe("ok");
  });

  test("size gate G6 (perf-gate section 4) holds for the Examples and the committed large-input sizes", () => {
    const sizes = json<{ examples: { files: number; canonical: number; kind2: number }; perFile: { file: string;
      canonical: number; kind2: number }[]; large: Record<string, { canonical: number; kind2: number }> }>("conformance/structured/sizes.json");
    let canonical = 0;
    let kind2 = 0;
    for (const row of sizes.perFile) {
      const document = decode(read(row.file));
      const text = DocumentStorageCodec.encode(document).byteLength;
      const structured = encodeStructured(document).byteLength;
      expect([text, structured]).toEqual([row.canonical, row.kind2]);
      expect(structured).toBeLessThanOrEqual(text);
      canonical += text;
      kind2 += structured;
    }
    expect(sizes.perFile).toHaveLength(293);
    expect([canonical, kind2]).toEqual([sizes.examples.canonical, sizes.examples.kind2]);
    expect(kind2).toBeLessThanOrEqual(0.98 * canonical);
    const synthetic = sizes.large["synthetic-2000"]!;
    const sculpt = sizes.large["sculpt-4096-32x20"]!;
    expect(synthetic.kind2).toBeLessThanOrEqual(0.995 * synthetic.canonical);
    expect(sculpt.kind2).toBeLessThanOrEqual(0.98 * sculpt.canonical);
  }, 60_000);

  test("the package index exports exactly the two new storage names", () => {
    expect(Object.keys(threemd).sort()).toEqual(["CompositionEditor", "DocumentComposition", "DocumentCompositionCodec",
      "DocumentCompositionError", "DocumentCompositionLimits", "DocumentCompositionSnapshot", "DocumentCompression",
      "DocumentDecodeLimits", "DocumentDiagnostics", "DocumentEditError", "DocumentEditLimits", "DocumentEditor",
      "DocumentFileComposition", "DocumentFileCompositionError", "DocumentIdentity", "DocumentPayloadKind", "DocumentRevision",
      "DocumentSnapshot", "DocumentStorageCodec", "DocumentStorageError", "DocumentStorageFormat", "ParseError",
      "danglingLinks", "linkGraph", "links", "parse", "serialize", "stableID"]);
    expect(DocumentPayloadKind).toEqual({ canonicalText: 1, structuredDocument: 2 });
    expect(Object.isFrozen(DocumentPayloadKind)).toBe(true);
    expect(DocumentStorageCodec.supportedPayloadKinds).toEqual([1, 2]);
    expect(Object.isFrozen(DocumentStorageCodec.supportedPayloadKinds)).toBe(true);
    const info: threemd.DocumentContainerInfo | null = DocumentStorageCodec.containerInfo(encodeStructured(documentOf([])));
    expect(info?.payloadKind).toBe(DocumentPayloadKind.structuredDocument);
  });
});

// MARK: - TypeScript chunked decoding (SPEC.md 11.3.13), on Bun in-process and on Node in a subprocess

/** Two storage decodes in sequence: a body ending in E2 82, then a version starting with the continuation byte AC. */
function chunkedSequences(codec: typeof DocumentStorageCodec): string[] {
  const results: string[] = [];
  const code = (bytes: Uint8Array): string => {
    try { codec.decode(bytes); return "ok"; } catch (error) { return (error as { code?: string }).code ?? String(error); }
  };
  const container = (payload: number[]): Uint8Array => {
    const output = new Uint8Array(40 + payload.length);
    output.set([0x33, 0x6d, 0x64, 0x62, 0x69, 0x6e, 0x0d, 0x0a], 0);
    output.set(payload, 40);
    const view = new DataView(output.buffer);
    view.setUint16(8, 1, true); output[10] = 2;
    view.setBigUint64(20, BigInt(payload.length), true); view.setBigUint64(28, BigInt(payload.length), true);
    let crc = 0xffffffff;
    for (let index = 0; index < output.length; index += 1) {
      if (index >= 36 && index < 40) continue;
      crc ^= output[index]!;
      for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) === 0 ? 0 : 0xedb88320);
    }
    view.setUint32(36, (crc ^ 0xffffffff) >>> 0, true);
    return output;
  };
  const leb = (value: number): number[] => { const out: number[] = []; while (value >= 0x80) { out.push((value & 0x7f) | 0x80); value >>>= 7; } out.push(value); return out; };
  const second = container([0x00, 0x02, 0xac, 0x62, 0x00, 0x00, 0x00]);
  for (const length of [65_535, 65_536, 65_537, 200_000]) {
    const body = new Array<number>(length).fill(0x61);
    body[length - 2] = 0xe2; body[length - 1] = 0x82;
    const first = container([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, ...leb(length), ...body]);
    results.push(`${length}:${code(first)}:${code(second)}`);
  }
  return results;
}
const expectedSequences = ["65535:invalidUTF8:invalidUTF8", "65536:invalidUTF8:invalidUTF8", "65537:invalidUTF8:invalidUTF8",
  "200000:invalidUTF8:invalidUTF8"];

describe("TypeScript chunked decoding never carries bytes into the next string", () => {
  test("Bun: a truncated last chunk and the following string both report invalidUTF8", () => {
    expect(chunkedSequences(DocumentStorageCodec)).toEqual(expectedSequences);
  });

  test.skipIf(Bun.which("node") === null)("Node: the same two-call sequences on the current sources", async () => {
    const directory = mkdtempSync(join(tmpdir(), "threemd-structured-node-"));
    try {
      const built = await Bun.build({ entrypoints: [fileURLToPath(new URL("../src/index.ts", import.meta.url))],
        outdir: directory, target: "node", format: "esm" });
      expect(built.success).toBe(true);
      const script = join(directory, "sequences.mjs");
      writeFileSync(script, `import { DocumentStorageCodec } from ${JSON.stringify(join(directory, "index.js"))};\n` +
        `const chunkedSequences = ${chunkedSequences.toString()};\n` +
        "console.log(JSON.stringify({ node: process.version, results: chunkedSequences(DocumentStorageCodec) }));\n");
      const result = Bun.spawnSync(["node", script], { stdout: "pipe", stderr: "pipe" });
      expect(result.stderr.toString()).toBe("");
      const output = JSON.parse(result.stdout.toString()) as { node: string; results: string[] };
      expect(output.node.startsWith("v")).toBe(true);
      expect(output.results).toEqual(expectedSequences);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }, 60_000);
});

// MARK: - Section 4: differential properties P1, P2, P3, P5 and P6 at CI volume

const SEGMENT_LINES = ["", " ", "\t", "\u00a0", "\u3000", "text", "@plane", "@plane z=1", "@plane\tz", "@planet", " @plane z=1",
  "\u00a0@plane z=1", "```", "~~~", "  ```js", "\u3000~~~", "``", "\r", "a\r", "# h", "---", "\u2003", "x\u200b", "\u200b",
  "  ~~~~", "```` four", "caf\u00e9", "e\u0301", "\ufeff", "[[z=1]]"];
const VALUES = ["v", "", " lead", "trail ", "\"q\"", "a\\b", "\\", "'s'", "a\nb", "a\rb", "\u00a0", "x y", "\u3000", "\ud800",
  "caf\u00e9", "\u{1F600}"];
const META_KEYS = ["", "a", "B", "view", "3md", "AXIS", "Title", "#c", " k", "k ", "a:b", "\u00e9", "e\u0301", "\ufffd",
  "\u{1F600}", "\u00a0k", "k\u3000", "x\ry", "k#", "caf\u00e9", "tItle", "axis2", "Key", "1", "10", "__proto__", "\uff61", "K",
  "\u212a", "z", "Z", "9", "\ud83d"];
const ATTRIBUTE_KEYS = ["a", "A", "", "z", "Label", "x", "a b", "a'b c'd", "'a\\'b'", "a\"b", "k=v", " k", "k ", "\u00df", "\u01c5",
  "\u00e9", "e\u0301", "\u00a0k", "k\u03a3", "k\u03c3", "key", "data-x", "'", "a''", "\"x y\"", "\u0130", "i\u0307", "3md-id",
  "\uff61", "\u{1F600}", "k", "\u212a", "q''", "10", "2"];
const NUMBERS = [0, -0, 1, 1.5, -2, 0.1, 2 ** 53, 2 ** 53 + 2, 5e-324, 1.7976931348623157e308, -1.5, 1e21, 1e-7, 123456789.125,
  2 ** -140, 2 ** 27 - 1, -(2 ** 27), 2 ** 27, 2 ** 24 + 1, 3.4028234663852886e38, 1.401298464324817e-45, 0.5, 1e15, 1e16];

/** The edge-biased document generator of P5 and P6 (test-plan section 4). */
function edgeDocument(random: () => number): Document {
  const pick = <Value>(items: readonly Value[]): Value => items[Math.floor(random() * items.length)]!;
  const between = (low: number, high: number): number => low + Math.floor(random() * (high - low + 1));
  const segment = (): string => {
    if (random() < 0.08) return "";
    let text = "";
    const count = between(1, 5);
    for (let index = 0; index < count; index += 1) text += (index === 0 ? "" : random() < 0.1 ? "\r\n" : "\n") + pick(SEGMENT_LINES);
    if (random() < 0.05) text += "\r";
    if (random() < 0.03) text = `\n${text}`;
    return text;
  };
  const pairs = (keys: readonly string[], count: number): Record<string, string> => {
    const result: Record<string, string> = Object.create(null);
    for (let index = 0; index < count; index += 1) result[pick(keys)] = pick(VALUES);
    return result;
  };
  const planes: Plane[] = [];
  const count = between(0, 4);
  for (let index = 0; index < count; index += 1) {
    planes.push({
      z: random() < 0.03 ? pick([NaN, Infinity]) : random() < 0.5 ? index : pick(NUMBERS) * (random() < 0.3 ? -1 : 1),
      label: random() < 0.5 ? null : pick(VALUES), x: random() < 0.7 ? null : pick(NUMBERS), y: random() < 0.7 ? null : pick(NUMBERS),
      attributes: pairs(ATTRIBUTE_KEYS, random() < 0.5 ? 0 : between(1, 3)), body: segment(),
    });
  }
  return {
    version: pick(["1.0", "1.0", "1.0", "", " 1.0", "1\r", "v\n2", "0.1", "\u00e9"]),
    axis: pick(["layer", "time", "", "Time", " time", "time ", "\ttime", "t\u00efme", "T\u00cfME", "\u00a0time", "ti me", "\u0130"]),
    title: random() < 0.5 ? null : pick(VALUES), metadata: pairs(META_KEYS, random() < 0.4 ? 0 : between(1, 4)),
    preamble: random() < 0.7 ? null : segment(), planes,
  };
}

const SAFE_VALUES = ["v", "x y", "\"q\"", "a\\b", "it's", "", "caf\u00e9", "\u{1F600}", "a=b", "'s'", " lead", "trail ", "\"",
  "\\", "a \"b\" c"];
const SAFE_LINES = ["text", "# h", "- item", "caf\u00e9", "a  b", "> quote", "x\u200by", "[[z=1]]", "\ufeffbom", "a\rb", "  indented",
  "\t tab"];
const RISKY_LINES = ["", " ", "\u3000", "@plane z=9", "@plane", "@plane\tz", " @plane z=9", "@planet", "```", "~~~", " ```",
  "\u00a0~~~", "````", "~~ ~", "``", "\r", "a\r", "\u2028", "---"];
const QUOTE_KEYS = ["a\"b", "a'b", "\"", "'", "a\"b\"c\"", "x\\\"", "\"a b\"", "'a b'", "a'b c'd", "'a\\'b'", "k\"=", "q\"\"",
  "a\"\\\"b", "\"\\\"", "data-x", "key", "k_1", "\u00e9", "e\u0301", "\u00df", "\u0130", "i\u0307", "k\u03c3", "\u2160", "\u24b6"];

/** The focused generator of the prototype's P6: mostly representable documents with one or two risky fields. */
function focusedDocument(random: () => number): Document {
  const pick = <Value>(items: readonly Value[]): Value => items[Math.floor(random() * items.length)]!;
  const between = (low: number, high: number): number => low + Math.floor(random() * (high - low + 1));
  const segment = (): string => {
    const lines: string[] = [];
    const count = between(1, 4);
    for (let index = 0; index < count; index += 1) lines.push(random() < 0.25 ? pick(RISKY_LINES) : pick(SAFE_LINES));
    let text = lines.join(random() < 0.05 ? "\r\n" : "\n");
    if (random() < 0.03) text += "\r";
    return text;
  };
  const pairs = (keys: readonly string[], count: number): Record<string, string> => {
    const result: Record<string, string> = Object.create(null);
    for (let index = 0; index < count; index += 1) result[pick(keys)] = pick(SAFE_VALUES);
    return result;
  };
  const planes: Plane[] = [];
  const count = between(1, 4);
  for (let index = 0; index < count; index += 1) {
    planes.push({ z: random() < 0.1 ? pick(NUMBERS) : index * 1.5, label: random() < 0.5 ? null : pick(SAFE_VALUES),
      x: random() < 0.8 ? null : pick(NUMBERS), y: random() < 0.8 ? null : pick(NUMBERS),
      attributes: pairs(random() < 0.6 ? QUOTE_KEYS : ["key", "data-x", "tags", "k_1"], between(0, 3)),
      body: random() < 0.1 ? "" : segment() });
  }
  return {
    version: random() < 0.05 ? pick(["", " 1.0", "1\r"]) : "1.0",
    axis: random() < 0.1 ? pick(["Time", " time", "t\u00efme", "\u0130", "ti me", "\u00a0x"]) : pick(["layer", "time", ""]),
    title: random() < 0.5 ? null : pick(SAFE_VALUES),
    metadata: pairs(random() < 0.3 ? META_KEYS : ["author", "view", "palette", "k"], between(0, 3)),
    preamble: random() < 0.6 ? null : segment(), planes,
  };
}

/** Mixes the two generators and, three times in ten, number boundaries (test-plan section 4, P5 and P6). */
function generatedDocument(random: () => number, round: number): Document {
  const document = round % 2 === 0 ? edgeDocument(random) : focusedDocument(random);
  if (random() >= 0.3) return document;
  return { ...document, planes: document.planes.map((item, index) => ({ ...item,
    z: random() < 0.3 ? NUMBERS[Math.floor(random() * NUMBERS.length)]! * (random() < 0.5 ? 1 : -1) + (random() < 0.5 ? 0 : index * 1000) : item.z,
    x: random() < 0.2 ? NUMBERS[Math.floor(random() * NUMBERS.length)]! : item.x })) };
}

/** Mostly representable documents, for the metrics test. */
function representable(random: () => number): Document {
  const pick = <Value>(items: readonly Value[]): Value => items[Math.floor(random() * items.length)]!;
  const values = ["v", "x y", "\"q\"", "a\\b", "it's", "", "caf\u00e9", "\u{1F600}", "a=b", "\"\\\"", "\u65e5\u672c", " lead"];
  const keys = ["author", "view", "k", "", "\u00e9", "\u65e5", "data", "x-y", "9", "10"];
  const attributeKeys = ["kind", "tags", "k_1", "\u00e9", "\u65e5\u672c", "a'b c'd", "\"x y\"", "q''", "data-x", "7"];
  const lines = ["text", "# h", "- item", "caf\u00e9", "a  b", "> q", "x\u200by", "[[z=1]]", "\ufeffbom", "a\rb", "  indented",
    "\t tab", "\u00e9\u65e5", "\u{1F600}", "\"quoted\""];
  const body = (final: boolean): string => {
    if (random() < 0.15) return "";
    const parts: string[] = [];
    const count = 1 + Math.floor(random() * 6);
    for (let index = 0; index < count; index += 1) parts.push(pick(lines));
    if (random() < 0.2) parts.splice(1, 0, "```", "@plane z=9", ...(final && random() < 0.5 ? [] : ["```"]));
    return parts.join("\n");
  };
  const map = (source: readonly string[]): Record<string, string> => {
    const result: Record<string, string> = Object.create(null);
    const count = Math.floor(random() * 4);
    for (let index = 0; index < count; index += 1) result[pick(source)] = pick(values);
    return result;
  };
  const count = Math.floor(random() * 5);
  const planes: Plane[] = [];
  for (let index = 0; index < count; index += 1) {
    const z = random() < 0.4 ? index : random() < 0.5 ? index + 0.5 : index * 1e20 + (random() < 0.5 ? 1e-7 : 1e15);
    planes.push({ z: random() < 0.5 ? -z : z, label: random() < 0.5 ? null : pick(values),
      x: random() < 0.6 ? null : pick(NUMBERS), y: random() < 0.6 ? null : pick(NUMBERS), attributes: map(attributeKeys),
      body: body(index + 1 === count) });
  }
  return { version: pick(["1.0", "1", "0.9 \"beta\""]), axis: pick(["layer", "time", "", "\u00e9poque"]),
    title: random() < 0.5 ? null : pick(values), metadata: map(keys), preamble: random() < 0.7 || count === 0 ? null : body(false), planes };
}

/** Byte mutations of a kind-2 file, lengths and CRC resealed (the specification package's mutate.ts operators). */
function mutated(base: Uint8Array, random: () => number): Uint8Array {
  const between = (low: number, high: number): number => low + Math.floor(random() * (high - low + 1));
  const pick = <Value>(items: readonly Value[]): Value => items[Math.floor(random() * items.length)]!;
  let payload = Array.from(base.subarray(40));
  const rounds = between(1, 3);
  for (let round = 0; round < rounds; round += 1) {
    const at = Math.floor(random() * Math.max(1, payload.length));
    switch (between(0, 10)) {
      case 0: payload[at] = (payload[at] ?? 0) ^ (1 << between(0, 7)); break;
      case 1: payload[at] = between(0, 255); break;
      case 2: payload[at] = pick([0x00, 0x0a, 0x0d, 0x20, 0x22, 0x27, 0x3d, 0x3a, 0x40, 0x60, 0x7e, 0x7f, 0x80, 0xc0, 0xed, 0xff]); break;
      case 3: payload.splice(at, 0, between(0, 255)); break;
      case 4: payload.splice(at, between(1, 4)); break;
      case 5: payload = payload.slice(0, at); break;
      case 6: { const from = Math.floor(random() * payload.length); payload.splice(at, 0, ...payload.slice(from, from + between(1, 12))); break; }
      case 7: payload[at] = ((payload[at] ?? 0) + pick([-1, 1])) & 0xff; break;
      case 8: payload.splice(at, 1, 0x80 | between(0, 127), between(0, 3)); break;
      case 9: { const from = Math.floor(random() * payload.length); const span = payload.splice(from, between(1, 6)); payload.splice(at, 0, ...span); break; }
      default: payload.push(between(0, 255)); break;
    }
  }
  return seal(payload);
}

/** The 2.0 TypeScript normalization the structured writer applies (W2): merged keys, -0 as +0. */
function normalized(document: Document): Document {
  const merge = (source: Readonly<Record<string, string>>): Record<string, string> => {
    const result: Record<string, string> = Object.create(null);
    const spellings = new Map<string, string>();
    for (const [key, value] of Object.entries(source)) {
      const normal = key.normalize("NFC");
      const spelling = spellings.get(normal) ?? key;
      if (!spellings.has(normal)) spellings.set(normal, key);
      result[spelling] = value;
    }
    return result;
  };
  const zero = (value: number | null): number | null => (value === 0 ? 0 : value);
  return { ...document, metadata: merge(document.metadata), planes: document.planes.map((item) => ({ ...item,
    z: zero(item.z) as number, x: zero(item.x), y: zero(item.y), attributes: merge(item.attributes) })) };
}

function loweredLimits(random: () => number): DocumentDecodeLimits {
  const between = (low: number, high: number): number => low + Math.floor(random() * (high - low + 1));
  return limits({ maximumRecordBytes: between(1, 120), maximumDecodedBytes: between(20, 700), maximumLines: between(1, 40),
    maximumPlanes: between(1, 5) });
}

describe("differential properties at CI volume (test-plan section 4)", () => {
  test("P1, P2 and P3 over 10,410 mutants of every anchor and the kind-2 Examples (seed 0x51a7)", () => {
    const examples = fileURLToPath(new URL("Examples/", repository));
    const bases = readdirSync(examples).filter((name) => name.endsWith(".3md")).sort()
      .map((name) => encodeStructured(decode(new Uint8Array(readFileSync(join(examples, name))))));
    for (const entry of manifest.files) bases.push(read(entry.kind2File));
    expect(bases).toHaveLength(347);
    const random = generator(0x51a7);
    let accepted = 0;
    let total = 0;
    const codes = new Map<string, number>();
    for (const base of bases) {
      for (let round = 0; round < 30; round += 1) {
        const bytes = mutated(base, random);
        total += 1;
        let document: Document;
        try { document = decode(bytes); } catch (error) {
          // P1: exactly one typed error, never a foreign exception.
          expect(error).toBeInstanceOf(DocumentStorageError);
          const code = (error as DocumentStorageError).code;
          codes.set(code, (codes.get(code) ?? 0) + 1);
          continue;
        }
        accepted += 1;
        expect(sameBytes(encodeStructured(document), bytes)).toBe(true); // P2
        const text = DocumentStorageCodec.encode(document); // P3
        expect(sameDocument(decode(text), document)).toBe(true);
      }
    }
    expect(total).toBe(10_410);
    expect(accepted).toBeGreaterThan(500);
    expect(codes.size).toBeGreaterThanOrEqual(4);
  }, 120_000);

  test("P5: encode(D, L) succeeds exactly when decode(encode(D, L), L) does, and returns the normalized D", () => {
    const random = generator(0x5005);
    let accepted = 0;
    for (let round = 0; round < 10_000; round += 1) {
      const document = generatedDocument(random, round);
      const policy = round % 3 === 0 ? standard : loweredLimits(random);
      let bytes: Uint8Array;
      try { bytes = encodeStructured(document, policy); } catch (error) {
        expect(error).toBeInstanceOf(DocumentStorageError);
        continue;
      }
      accepted += 1;
      const decoded = decode(bytes, policy);
      expect(sameDocument(decoded, normalized(document))).toBe(true);
    }
    expect(accepted).toBeGreaterThan(400);
  }, 120_000);

  test("P6: binary acceptance equals validate under standard and lowered limits, and decode equals the text decode", () => {
    const random = generator(0x3d3d2101);
    const tally = { standard: 0, lowered: 0, accepted: 0, disagreements: [] as string[], mismatches: 0 };
    for (let round = 0; round < 40_000; round += 1) {
      const lowered = round >= 10_000;
      const document = generatedDocument(random, round);
      const policy = lowered ? loweredLimits(random) : standard;
      if (lowered) tally.lowered += 1; else tally.standard += 1;
      const text = codeOf(() => DocumentStorageCodec.validate(document, policy));
      let bytes: Uint8Array | null = null;
      const structured = codeOf(() => { bytes = encodeStructured(document, policy); });
      if ((text === "ok") !== (structured === "ok")) {
        if (tally.disagreements.length < 5) tally.disagreements.push(`${text} vs ${structured}: ${JSON.stringify(document)}`);
        continue;
      }
      if (bytes === null) continue;
      tally.accepted += 1;
      const fromText = decode(DocumentStorageCodec.encode(document, DocumentStorageFormat.text, policy), policy);
      const fromBinary = decode(bytes, policy);
      if (!sameDocument(fromText, fromBinary) || !sameBytes(encodeStructured(fromBinary, policy), bytes)) tally.mismatches += 1;
    }
    expect(tally.disagreements).toEqual([]);
    expect(tally.mismatches).toBe(0);
    expect(tally.standard).toBe(10_000);
    expect(tally.lowered).toBe(30_000);
    expect(tally.accepted).toBeGreaterThan(1_500);
  }, 300_000);
});

// MARK: - Section 5: cancellation, resource bounds, buffer ownership

/** A real AbortSignal whose checks are counted; it aborts with `reason` on check number `abortAt`. */
function countingSignal(abortAt: number, reason: unknown, callers?: string[]): { signal: AbortSignal; calls: () => number } {
  const controller = new AbortController();
  const signal = controller.signal;
  const original = signal.throwIfAborted.bind(signal);
  let calls = 0;
  Object.defineProperty(signal, "throwIfAborted", { value: () => {
    calls += 1;
    if (callers !== undefined) callers.push(callerOf(new Error().stack ?? ""));
    if (calls === abortAt) controller.abort(reason);
    original();
  } });
  return { signal, calls: () => calls };
}
/**
 * The function that called `checkCancellation`, from a stack trace. A check made by the work budget is reported as
 * "spend" followed by the function that charged the work, for example "spend writeString".
 */
function callerOf(stack: string): string {
  const frames = stack.split("\n").map((line) => line.trim()).filter((line) => line.startsWith("at "));
  const index = frames.findIndex((frame) => frame.includes("checkCancellation"));
  const name = (offset: number): string => (frames[index + offset] ?? "").slice(3).split(" ")[0] ?? "";
  const caller = name(1);
  return caller.endsWith("spend") ? `spend ${name(2)}` : caller;
}
function recordCallers(operation: (signal: AbortSignal) => unknown): string[] {
  const callers: string[] = [];
  const limit = Error.stackTraceLimit;
  Error.stackTraceLimit = 8;
  try { operation(countingSignal(0, undefined, callers).signal); } catch { /* the caller compares outcomes */ }
  finally { Error.stackTraceLimit = limit; }
  return callers;
}
/** Aborts at check `index` (0-based) and requires the abort reason, unwrapped, with no result. */
function abortsAt(operation: (signal: AbortSignal) => unknown, index: number): void {
  const reason = new Error(`cancelled at check ${index}`);
  let result: unknown = "no exception";
  try { result = operation(countingSignal(index + 1, reason).signal); } catch (error) { result = error; }
  expect(result).toBe(reason);
}
const nth = (callers: readonly string[], name: string, occurrence: number): number => {
  let seen = 0;
  for (let index = 0; index < callers.length; index += 1) {
    if (callers[index]!.includes(name) && seen++ === occurrence) return index;
  }
  throw new Error(`no check number ${occurrence} in ${name}`);
};
const count = (callers: readonly string[], name: string): number => callers.filter((caller) => caller.includes(name)).length;

/**
 * Replaces a writable method or function on `owner` for the duration of one operation, keeping the original
 * reachable. Assignment, not redefinition: Bun's `TextDecoder.prototype.decode` is writable but not configurable.
 */
type Patch = { readonly restore: () => void };
function patch<Owner extends object>(owner: Owner, name: keyof Owner & string,
  replacement: (original: (...args: unknown[]) => unknown) => (...args: unknown[]) => unknown): Patch {
  const slots = owner as unknown as Record<string, unknown>;
  const original = slots[name] as (...args: unknown[]) => unknown;
  slots[name] = replacement(original);
  return { restore: () => { slots[name] = original; } };
}

/**
 * Measures the work done between consecutive cancellation checks independently of the library's own accounting:
 * `install` patches native string operations so that each call advances a work clock (characters built, scanned or
 * normalized), and a counting signal reads the clock at every check. The start and the end of the operation count as
 * checks. Returns the largest clock advance between two checks, the number of checks and the total.
 */
function workBetweenChecks(operation: (signal: AbortSignal) => unknown,
  install: (tick: (units: number) => void) => readonly Patch[]): { largest: number; checks: number; total: number; outcome: string } {
  let clock = 0;
  let last = 0;
  let largest = 0;
  let checks = 0;
  const controller = new AbortController();
  Object.defineProperty(controller.signal, "throwIfAborted", { value: () => {
    checks += 1;
    if (clock - last > largest) largest = clock - last;
    last = clock;
  } });
  let outcome = "ok";
  const patches = install((units) => { clock += units; });
  try { operation(controller.signal); } catch (error) {
    outcome = error instanceof DocumentStorageError ? error.code : String(error);
  } finally {
    for (const item of [...patches].reverse()) item.restore();
  }
  if (clock - last > largest) largest = clock - last;
  return { largest, checks, total: clock, outcome };
}
/** Counts the characters of every string built by `String.fromCharCode` (short ASCII strings). */
const fromCharCodeClock = (tick: (units: number) => void): Patch =>
  patch(String, "fromCharCode", (original) => (...units: unknown[]) => { tick(units.length); return original.apply(String, units); });
/** Counts the bytes of every `TextDecoder.decode` call (non-ASCII and long strings). */
const textDecoderClock = (tick: (units: number) => void): Patch =>
  patch(TextDecoder.prototype, "decode", (original) => function (this: TextDecoder, ...args: unknown[]) {
    const input = args[0] as Uint8Array | undefined;
    tick(input === undefined ? 0 : input.byteLength);
    return original.apply(this, args);
  });
/** Counts the code units of every string passed to `String.prototype.normalize`. */
const normalizeClock = (tick: (units: number) => void): Patch =>
  patch(String.prototype, "normalize", (original) => function (this: string, ...args: unknown[]) {
    tick(this.length);
    return original.apply(this, args);
  });
/** Counts every `String.prototype.charCodeAt` call: key scans, key comparisons and short ASCII writes. */
const charCodeAtClock = (tick: (units: number) => void): Patch =>
  patch(String.prototype, "charCodeAt", (original) => function (this: string, ...args: unknown[]) {
    tick(1);
    return original.apply(this, args);
  });
/** Counts the code units of every string tested by a regular expression (the writer's ASCII test). */
const regExpClock = (tick: (units: number) => void): Patch =>
  patch(RegExp.prototype, "test", (original) => function (this: RegExp, ...args: unknown[]) {
    tick(String(args[0]).length);
    return original.apply(this, args);
  });

/**
 * One memory worst case of test-plan section 5, run in a fresh process because resident memory never shrinks: builds
 * the input by hand (no library writer), then reports the growth of the resident set from just before the decode to
 * its peak, sampled at every cancellation check and once more while the result is still held. Resident memory counts
 * every string's storage; the heap statistics of both runtimes miss large decoded strings (Bun's `heapUsed`, and
 * Node's `heapUsed` and `external` for two-byte strings).
 */
function memoryCase(codec: typeof DocumentStorageCodec, name: string, collect: () => void): {
  name: string; outcome: string; planes: number; input: number; growth: number;
} {
  const leb = (value: number): number[] => { const out: number[] = []; while (value >= 0x80) { out.push((value & 0x7f) | 0x80); value >>>= 7; } out.push(value); return out; };
  const maximum = 64 * 1024 * 1024;
  let parts: { head: number[]; size: number; fill: (file: Uint8Array, at: number) => void };
  if (name.startsWith("body ")) {
    // One body of at most R = 8 MiB: lines of about 1,000 bytes of one scalar.
    const unit = new TextEncoder().encode(name.slice(5));
    const line = new Uint8Array(Math.floor(1_000 / unit.length) * unit.length + 1);
    for (let at = 0; at + unit.length < line.length; at += unit.length) line.set(unit, at);
    line[line.length - 1] = 0x0a;
    const lines = Math.floor((8 * 1024 * 1024 + 1) / line.length);
    const size = lines * line.length - 1;
    parts = { head: [0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, ...leb(size)], size, fill: (file, at) => {
      for (let index = 0; index < lines; index += 1) {
        file.set(index + 1 === lines ? line.subarray(0, line.length - 1) : line, at + index * line.length);
      }
    } };
  } else if (name === "planes") {
    // The most planes with bodies that fit the 100,000 lines: 33,000 single-line bodies of 2,000 bytes.
    const planes = 33_000;
    const records = Array.from({ length: planes }, (_, index) => [0x01, ...leb(index * 2), 0x00, ...leb(2_000)]);
    const size = records.reduce((sum, record) => sum + record.length + 2_000, 0);
    parts = { head: [0x00, 0x01, 0x31, 0x00, 0x00, ...leb(planes)], size, fill: (file, at) => {
      for (const record of records) {
        file.set(record, at);
        file.fill(0x62, at + record.length, at + record.length + 2_000);
        at += record.length + 2_000;
      }
    } };
  } else {
    // The most minimal attributes a 64 MiB container holds, in one plane: "k" and five base-36 digits (distinct and
    // increasing), then an empty value, 8 bytes each. L3 rejects the directive line after Phase S read them all.
    const attributes = Math.floor((maximum - 40 - 16) / 8);
    const digits = "0123456789abcdefghijklmnopqrstuvwxyz";
    parts = { head: [0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, ...leb(attributes)], size: attributes * 8 + 1,
      fill: (file, at) => {
        for (let index = 0; index < attributes; index += 1) {
          file[at++] = 6;
          file[at++] = 0x6b;
          for (let place = 4; place >= 0; place -= 1) file[at++] = digits.charCodeAt(Math.floor(index / 36 ** place) % 36);
          file[at++] = 0;
        }
      } };
  }
  const payload = parts.head.length + parts.size;
  const file = new Uint8Array(40 + payload);
  file.set([0x33, 0x6d, 0x64, 0x62, 0x69, 0x6e, 0x0d, 0x0a], 0);
  const view = new DataView(file.buffer);
  view.setUint16(8, 1, true); file[10] = 2;
  view.setBigUint64(20, BigInt(payload), true); view.setBigUint64(28, BigInt(payload), true);
  file.set(parts.head, 40);
  parts.fill(file, 40 + parts.head.length);
  const table = new Uint32Array(256);
  for (let byte = 0; byte < 256; byte += 1) {
    let value = byte;
    for (let bit = 0; bit < 8; bit += 1) value = (value >>> 1) ^ ((value & 1) === 0 ? 0 : 0xedb88320);
    table[byte] = value >>> 0;
  }
  let crc = 0xffffffff;
  for (let index = 0; index < file.length; index += 1) {
    if (index === 36) { index = 39; continue; }
    crc = table[(crc ^ file[index]!) & 0xff]! ^ (crc >>> 8);
  }
  view.setUint32(36, (crc ^ 0xffffffff) >>> 0, true);
  collect();
  const resident = (): number => process.memoryUsage.rss();
  const base = resident();
  let peak = base;
  const controller = new AbortController();
  Object.defineProperty(controller.signal, "throwIfAborted", { value: () => { const now = resident(); if (now > peak) peak = now; } });
  let outcome = "ok";
  let planes = 0;
  try { planes = codec.decode(file, undefined, controller.signal).planes.length; } catch (error) {
    outcome = (error as { code?: string }).code ?? String(error);
  }
  const after = resident();
  if (after > peak) peak = after;
  return { name, outcome, planes, input: file.byteLength, growth: peak - base };
}
const MEMORY_CASES: readonly (readonly [string, string, number])[] = [["body a", "ok", 1], ["body \u00e9", "ok", 1],
  ["body \u20ac", "ok", 1], ["body \u{1F600}", "ok", 1], ["planes", "ok", 33_000], ["attributes", "oversizedRecord", 0]];

/** Runs every memory case in its own process of `command` and checks outcome and growth. */
function checkMemoryCases(command: readonly string[], library: string, collect: string, directory: string): string[] {
  const script = join(directory, "memory.mjs");
  writeFileSync(script, `import { DocumentStorageCodec } from ${JSON.stringify(library)};\n` +
    `const memoryCase = ${memoryCase.toString()};\n` +
    `console.log(JSON.stringify(memoryCase(DocumentStorageCodec, process.argv[process.argv.length - 1], ${collect})));\n`);
  const report: string[] = [];
  for (const [name, outcome, planes] of MEMORY_CASES) {
    const run = Bun.spawnSync([...command, script, name], { stdout: "pipe", stderr: "pipe" });
    expect(run.stderr.toString(), name).toBe("");
    const result = JSON.parse(run.stdout.toString()) as ReturnType<typeof memoryCase>;
    expect(result.outcome, name).toBe(outcome);
    expect(result.planes, name).toBe(planes);
    expect(result.input, name).toBeGreaterThan(name === "planes" || name === "attributes" ? 60 * 1024 * 1024 : 8_000_000);
    expect(result.growth, name).toBeLessThan(4 * result.input);
    report.push(`${name}: ${(result.growth / result.input).toFixed(2)}`);
  }
  return report;
}

describe("cancellation, resource bounds and buffer ownership (test-plan section 5)", () => {
  const mixed = documentOf([
    plane(0, `${"x".repeat(70_000)}\n\u00e9${"y".repeat(70_000)}`, { label: "first" }),
    plane(1, "short", { attributes: record([["a'b c'd", "q"], ["kind", "v"]]) }),
    plane(2.5, "```\n@plane z=9", { x: 0.1, attributes: record([["tags", "t"]]) }),
  ], { title: "t".repeat(70_000), metadata: record([["k", "v"]]), preamble: "Intro" });
  const mixedFile = encodeStructured(mixed);

  test("before entry: a pre-aborted signal fails every storage entry point with its reason", () => {
    const abort = new AbortController();
    const reason = new Error("stop");
    abort.abort(reason);
    for (const operation of [() => DocumentStorageCodec.decode(mixedFile, standard, abort.signal),
      () => DocumentStorageCodec.encode(mixed, binary, standard, abort.signal),
      () => DocumentStorageCodec.encodeTextContainer(mixed, DocumentCompression.None, standard, abort.signal)]) {
      expect(operation).toThrow(reason);
    }
  });

  test("every decode and encode check point aborts with the reason and leaves no partial result", () => {
    const reference = decode(mixedFile);
    const decodeChecks = recordCallers((signal) => DocumentStorageCodec.decode(mixedFile, standard, signal));
    const encodeChecks = recordCallers((signal) => DocumentStorageCodec.encode(mixed, binary, standard, signal));
    for (const name of ["containerChecksum", "scan", "decodeUTF8", "readStructured", "checkSegment"]) {
      expect(count(decodeChecks, name), name).toBeGreaterThan(0);
    }
    expect(count(encodeChecks, "writeStructuredPayload")).toBeGreaterThanOrEqual(6);
    expect(count(encodeChecks, "readStructured")).toBeGreaterThanOrEqual(6);
    for (let index = 0; index < decodeChecks.length; index += 1) {
      abortsAt((signal) => DocumentStorageCodec.decode(mixedFile, standard, signal), index);
    }
    for (let index = 0; index < encodeChecks.length; index += 1) {
      abortsAt((signal) => DocumentStorageCodec.encode(mixed, binary, standard, signal), index);
    }
    expect(sameDocument(decode(mixedFile), reference)).toBe(true);
    expect(sameBytes(encodeStructured(mixed), mixedFile)).toBe(true);
  }, 60_000);

  test("mid-CRC on a 64 MiB input", () => {
    // Hand-built, because the writer's self-check refuses it: T exceeds the 64 MiB Dmax by 28 bytes, so the
    // reference outcome is L4 after a complete CRC and Phase S.
    const total = 64 * 1024 * 1024;
    const big = new Uint8Array(total);
    big.set([0x00, 0x01, 0x31, 0x00, 0x00, 0x08], 40);
    const pattern = encoder.encode(`${"0123456789abcdef".repeat(64)}\n`);
    const bodyLength = Math.floor((total - 40 - 6 - 8 * 7) / 8);
    let position = 46;
    for (let index = 0; index < 8; index += 1) {
      const length = index === 7 ? total - position - 7 : bodyLength;
      big.set([0x01, index * 2, 0x00, ...varBytes(length)], position);
      position += 7;
      for (let offset = 0; offset < length; offset += pattern.byteLength) {
        big.set(pattern.subarray(0, Math.min(pattern.byteLength, length - offset)), position + offset);
      }
      position += length;
      big[position - 1] = 0x7a;
    }
    expect(position).toBe(total);
    const view = new DataView(big.buffer);
    big.set([0x33, 0x6d, 0x64, 0x62, 0x69, 0x6e, 0x0d, 0x0a], 0);
    view.setUint16(8, 1, true); big[10] = 2;
    view.setBigUint64(20, BigInt(total - 40), true); view.setBigUint64(28, BigInt(total - 40), true);
    view.setUint32(36, containerChecksum(big), true);
    const policy = limits({ maximumRecordBytes: total });
    expect(codeOf(() => decode(big, policy))).toBe("oversizedOutput");
    const callers = recordCallers((signal) => DocumentStorageCodec.decode(big, policy, signal));
    expect(count(callers, "containerChecksum")).toBe(1_025);
    abortsAt((signal) => DocumentStorageCodec.decode(big, policy, signal), nth(callers, "containerChecksum", 512));
    expect(codeOf(() => decode(big, policy))).toBe("oversizedOutput");
  }, 120_000);

  test("inside a 1 MiB scalar scan and between the UTF-8 chunks of an 8 MiB body", () => {
    const scalar = encodeStructured(documentOf([plane(0, "a")], { title: "s".repeat(1024 * 1024) }));
    const scalarCallers = recordCallers((signal) => DocumentStorageCodec.decode(scalar, standard, signal));
    expect(count(scalarCallers, "scan")).toBeGreaterThanOrEqual(15);
    abortsAt((signal) => DocumentStorageCodec.decode(scalar, standard, signal), nth(scalarCallers, "scan", 8));
    const body = `${"\u00e9".repeat(1000)}\n`.repeat(4_192).slice(0, -1);
    const large = encodeStructured(documentOf([plane(0, body)]));
    const bodyCallers = recordCallers((signal) => DocumentStorageCodec.decode(large, standard, signal));
    expect(count(bodyCallers, "validateUTF8")).toBeGreaterThanOrEqual(127);
    abortsAt((signal) => DocumentStorageCodec.decode(large, standard, signal), nth(bodyCallers, "validateUTF8", 64));
    expect(decode(large).planes[0]?.body).toBe(body);
    expect(decode(scalar).title).toBe("s".repeat(1024 * 1024));
  }, 60_000);

  test("before plane k of 65,536 and in Phase L", () => {
    // 65,536 empty planes need 131,077 lines, so the complete decode stops at L5, after Phase S and the Phase L check.
    const payload = [0x00, ...str("1"), 0x00, 0x00, ...varBytes(65_536)];
    for (let index = 0; index < 65_536; index += 1) payload.push(0x01, ...varBytes(index * 2), 0x00, 0x00);
    const file = seal(payload);
    expect(codeOf(() => decode(file))).toBe("tooManyLines");
    const callers = recordCallers((signal) => DocumentStorageCodec.decode(file, standard, signal));
    // readStructured's own checks: one before each plane, then one at the start of Phase L.
    expect(count(callers, "readStructured")).toBe(65_536 + 1);
    abortsAt((signal) => DocumentStorageCodec.decode(file, standard, signal), nth(callers, "readStructured", 40_000));
    abortsAt((signal) => DocumentStorageCodec.decode(file, standard, signal), nth(callers, "readStructured", 65_536)); // Phase L
    // The Phase L check runs after S10: a trailing byte never reaches it.
    const trailing = seal([...payload, 0x00]);
    expect(codeOf(() => decode(trailing))).toBe("lengthMismatch");
    expect(count(recordCallers((signal) => DocumentStorageCodec.decode(trailing, standard, signal)), "readStructured")).toBe(65_536);
    // The largest plane count that fits 100,000 lines decodes. readStructured checks before each plane, in Phase L
    // and before returning; the result walk charges 64 units per plane to the work budget, so a run of planes
    // without strings reaches a check every 1,024 planes.
    const fits = Array.from({ length: 49_997 }, (_, index) => plane(index, ""));
    const accepted = encodeStructured(documentOf(fits));
    const acceptedCallers = recordCallers((signal) => DocumentStorageCodec.decode(accepted, standard, signal));
    const walkChecks = count(acceptedCallers, "spend readStructured");
    expect(walkChecks).toBeGreaterThanOrEqual(Math.floor(49_997 / 1_024));
    expect(walkChecks).toBeLessThanOrEqual(Math.ceil(49_997 / 1_024));
    expect(count(acceptedCallers, "readStructured")).toBe(49_997 + 1 + walkChecks + 1);
    abortsAt((signal) => DocumentStorageCodec.decode(accepted, standard, signal), nth(acceptedCallers, "spend", 20));
    expect(decode(accepted).planes).toHaveLength(49_997);
  }, 60_000);

  test("before and after a Phase Q parse", () => {
    const file = encodeStructured(documentOf([plane(0, "a", { attributes: record([["a'b c'd", "v"]]) })]));
    const callers = recordCallers((signal) => DocumentStorageCodec.decode(file, standard, signal));
    expect(count(callers, "readStructured")).toBe(5); // plane, Phase L, before Q, after Q, return
    const before = structuredProbe.phaseQParses;
    abortsAt((signal) => DocumentStorageCodec.decode(file, standard, signal), nth(callers, "readStructured", 2));
    expect(structuredProbe.phaseQParses).toBe(before);
    abortsAt((signal) => DocumentStorageCodec.decode(file, standard, signal), nth(callers, "readStructured", 3));
    expect(structuredProbe.phaseQParses).toBe(before + 1);
  });

  test("mid-emission and mid-self-check on encode", () => {
    const planes = Array.from({ length: 50 }, (_, index) => plane(index, `body ${index}`, { label: `p${index}` }));
    const document = documentOf(planes);
    const callers = recordCallers((signal) => DocumentStorageCodec.encode(document, binary, standard, signal));
    // The W2 plan and the W3 emission, once per plane each, and once before the W4 self-check.
    expect(count(callers, "writeStructuredPayload")).toBe(101);
    abortsAt((signal) => DocumentStorageCodec.encode(document, binary, standard, signal), nth(callers, "writeStructuredPayload", 75));
    abortsAt((signal) => DocumentStorageCodec.encode(document, binary, standard, signal), nth(callers, "readStructured", 25));
    expect(decode(encodeStructured(document)).planes).toHaveLength(50);
  });

  // SPEC.md 11.3.13: between two checks at most 65,536 bytes of scanning or validation, or one native string
  // construction of at most R bytes. The work clocks below observe the patched natives, not the library's accounting.
  test("the result walk checks by bytes inside one plane of 700,000 attributes (standard limits)", () => {
    const attributes = 700_000;
    const digits = "0123456789abcdefghijklmnopqrstuvwxyz";
    const head = [0x00, ...str("1"), 0x00, 0x00, 0x01, 0x01, 0x00, ...varBytes(attributes)];
    const payload = new Uint8Array(head.length + attributes * 10 + 1);
    payload.set(head, 0);
    let position = head.length;
    for (let index = 0; index < attributes; index += 1) {
      // "k" and five base-36 digits, strictly increasing in byte order, with the value "v".
      payload[position++] = 6;
      payload[position++] = 0x6b;
      for (let place = 4; place >= 0; place -= 1) payload[position++] = digits.charCodeAt(Math.floor(index / 36 ** place) % 36);
      payload[position++] = 1;
      payload[position++] = 0x76;
    }
    const file = seal(payload.subarray(0, position + 1)); // and an empty body
    // The directive line is 10 + 11 * 700,000 bytes, under the 8 MiB R.
    const work = workBetweenChecks((signal) => DocumentStorageCodec.decode(file, standard, signal),
      (tick) => [fromCharCodeClock(tick)]);
    expect(work.outcome).toBe("ok");
    expect(work.total).toBe(1 + attributes * 7); // the version, then every key and value
    // Every string is charged with at least one more byte (its Var) than it has characters.
    expect(work.largest).toBeLessThanOrEqual(65_536);
    expect(work.checks).toBeGreaterThanOrEqual(Math.floor(work.total / 65_536));
    const callers = recordCallers((signal) => DocumentStorageCodec.decode(file, standard, signal));
    expect(count(callers, "spend next")).toBeGreaterThanOrEqual(Math.floor(attributes * 9 / 65_536));
    abortsAt((signal) => DocumentStorageCodec.decode(file, standard, signal), nth(callers, "spend next", 48)); // mid-walk
    const decoded = decode(file).planes[0]!.attributes;
    expect(Object.keys(decoded)).toHaveLength(attributes);
    expect(decoded.k00000).toBe("v");
    expect(decoded[`k${(attributes - 1).toString(36).padStart(5, "0")}`]).toBe("v");
  }, 60_000);

  test("the equivalence checks of long decomposed keys check by bytes, metadata and attributes (standard limits)", () => {
    const key = (index: number): string => `${"e\u0301".repeat(6_000)}k${index.toString(36)}`;
    const keys = Array.from({ length: 100 }, (_, index) => key(index));
    const document = documentOf([plane(0, "b", { attributes: record(keys.map((name) => [name, "v"])) })],
      { metadata: record(keys.map((name) => [name, "w"])) });
    const file = encodeStructured(document);
    const work = workBetweenChecks((signal) => DocumentStorageCodec.decode(file, standard, signal),
      (tick) => [textDecoderClock(tick), normalizeClock(tick)]);
    expect(work.outcome).toBe("ok");
    // Each 18,002-byte key is decoded in Phase S, decoded and normalized by S6b or P7a, and decoded for the result.
    expect(work.total).toBeGreaterThan(200 * 3 * 18_000);
    expect(work.largest).toBeLessThanOrEqual(65_536);
    const callers = recordCallers((signal) => DocumentStorageCodec.decode(file, standard, signal));
    abortsAt((signal) => DocumentStorageCodec.decode(file, standard, signal), nth(callers, "checkEquivalence", 0));
    abortsAt((signal) => DocumentStorageCodec.decode(file, standard, signal), nth(callers, "checkEquivalence", 40));
    expect(sameDocument(decode(file), document)).toBe(true);
    // An equivalent pair of long keys is still found.
    const long = "x".repeat(30_000);
    const pair = seal([0x00, ...str("1"), 0x00, 0x02, ...str(`e\u0301${long}`), ...str("1"), ...str(`\u00e9${long}`),
      ...str("2"), 0x00]);
    expect(codeOf(() => decode(pair))).toBe("invalidDocument");
  }, 60_000);

  test("the writer checks by work inside large maps: merge tests, sorts, the plan and the emission", () => {
    const random = generator(0x5eed);
    const names = Array.from({ length: 100_000 }, (_, index) => `k${index.toString(36).padStart(4, "0")}`);
    for (let index = names.length - 1; index > 0; index -= 1) { // insertion order is shuffled, so the sort is real
      const other = Math.floor(random() * (index + 1));
      [names[index], names[other]] = [names[other]!, names[index]!];
    }
    const attributes = record(names.map((name) => [name, "v"]));
    const metadata = record(names.slice(0, 30_000).map((name) => [name, "w"])); // within the 100,000 lines
    const ascii = documentOf([plane(0, "b", { attributes }), plane(1, "c", { attributes })], { metadata });
    const asciiWork = workBetweenChecks((signal) => DocumentStorageCodec.encode(ascii, binary, standard, signal),
      (tick) => [charCodeAtClock(tick), regExpClock(tick)]);
    expect(asciiWork.outcome).toBe("ok");
    expect(asciiWork.total).toBeGreaterThan(2 * 100_000 * 20);
    // A comparison is charged with its shorter key and reads two code units per character; everything else reads
    // at most one unit per unit charged.
    expect(asciiWork.largest).toBeLessThanOrEqual(2 * 65_536);
    // Equivalent non-ASCII keys: the merge test, the 2.0 validation of the unmerged input, the merge and the sort.
    const merged = record([...names.slice(0, 20_000).map((name): [string, string] => [`\u00e9${name}`, "v"]),
      ["e\u0301merge", "first"], ["\u00e9merge", "last"]]);
    const nonASCII = documentOf([plane(0, "b", { attributes: merged })], { metadata: merged }); // 20,002 lines
    const mergedWork = workBetweenChecks((signal) => DocumentStorageCodec.encode(nonASCII, binary, standard, signal),
      (tick) => [charCodeAtClock(tick), regExpClock(tick), normalizeClock(tick)]);
    expect(mergedWork.outcome).toBe("ok");
    expect(mergedWork.largest).toBeLessThanOrEqual(2 * 65_536);
    const mergedMetadata = decode(encodeStructured(nonASCII)).metadata;
    // The 2.0 TypeScript merge in Object.keys order: the first spelling with the last value.
    const spellings = Object.keys(mergedMetadata).filter((key) => key.normalize("NFC") === "\u00e9merge");
    expect(spellings).toEqual(["e\u0301merge"]);
    expect(mergedMetadata["e\u0301merge"]).toBe("last");
    const callers = recordCallers((signal) => DocumentStorageCodec.encode(ascii, binary, standard, signal));
    for (const name of ["entriesOf", "hasEquivalentKeys", "compareEntries", "string", "writeString"]) {
      expect(count(callers, `spend ${name}`), name).toBeGreaterThan(0);
    }
    for (const name of ["hasEquivalentKeys", "compareEntries", "writeString"]) {
      abortsAt((signal) => DocumentStorageCodec.encode(ascii, binary, standard, signal), nth(callers, `spend ${name}`, 3));
    }
    expect(decode(encodeStructured(ascii)).planes[1]!.attributes.k0000).toBe("v");
  }, 120_000);

  test("memory on Bun: resident growth under 4 times the input for the 64 MiB worst cases and an 8 MiB body", () => {
    const directory = mkdtempSync(join(tmpdir(), "threemd-structured-memory-"));
    try {
      const library = fileURLToPath(new URL("../src/index.ts", import.meta.url));
      console.log(`Bun memory growth / input: ${checkMemoryCases([process.execPath], library, "() => Bun.gc(true)", directory).join(", ")}`);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }, 120_000);

  test.skipIf(Bun.which("node") === null)("memory on Node: the same cases on the current sources", async () => {
    const directory = mkdtempSync(join(tmpdir(), "threemd-structured-memory-node-"));
    try {
      const built = await Bun.build({ entrypoints: [fileURLToPath(new URL("../src/index.ts", import.meta.url))],
        outdir: directory, target: "node", format: "esm" });
      expect(built.success).toBe(true);
      const report = checkMemoryCases(["node", "--expose-gc"], join(directory, "index.js"), "() => globalThis.gc()", directory);
      console.log(`Node memory growth / input: ${report.join(", ")}`);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }, 120_000);

  test("amplification: 65,536 quoted-key planes over R are rejected before any Phase Q parse, in under a second", () => {
    const payload: number[] = [0x00, ...str("1"), 0x00, 0x00, ...varBytes(65_536)];
    const label = str("L".repeat(54));
    const attribute = [0x01, ...str("a'"), ...str("")];
    for (let index = 0; index < 65_536; index += 1) payload.push(0x41, ...varBytes(index * 2), ...label, ...attribute, 0x00);
    const file = seal(payload);
    const before = structuredProbe.phaseQParses;
    const started = performance.now();
    expect(codeOf(() => decode(file, limits({ maximumRecordBytes: 64 })))).toBe("oversizedRecord"); // L3
    expect(codeOf(() => decode(file, limits({ maximumDecodedBytes: 3_000_000 })))).toBe("oversizedOutput"); // L4, past D10
    expect(performance.now() - started).toBeLessThan(1_000);
    expect(structuredProbe.phaseQParses).toBe(before);
  }, 30_000);

  test("Phase S allocates nothing per key: 2,000,000 minimal attributes stay far below 4 times the input", () => {
    const attributes = 2_000_000;
    const digits = "0123456789abcdefghijklmnopqrstuvwxyz";
    const head = [0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, ...varBytes(attributes)];
    const payload = new Uint8Array(head.length + attributes * 8 + 1);
    payload.set(head, 0);
    let position = head.length;
    for (let index = 0; index < attributes; index += 1) {
      // "k" and five base-36 digits: distinct, lowercase, strictly increasing in byte order; then an empty value.
      payload[position++] = 6;
      payload[position++] = 0x6b;
      for (let place = 4; place >= 0; place -= 1) payload[position++] = digits.charCodeAt(Math.floor(index / 36 ** place) % 36);
      payload[position++] = 0;
    }
    payload[position] = 0; // empty body
    const file = seal(payload);
    Bun.gc(true);
    const start = process.memoryUsage().heapUsed;
    let peak = 0;
    const controller = new AbortController();
    Object.defineProperty(controller.signal, "throwIfAborted", { value: () => {
      peak = Math.max(peak, process.memoryUsage().heapUsed - start);
    } });
    // The single directive line is longer than R, so L3 rejects the plane after Phase S has read every attribute.
    expect(codeOf(() => DocumentStorageCodec.decode(file, standard, controller.signal))).toBe("oversizedRecord");
    expect(peak).toBeLessThan(4 * file.byteLength);
  }, 60_000);

  test("buffer ownership: overwriting or slicing the caller's buffer never changes a decoded value", () => {
    const file = mixedFile.slice();
    const reference = decode(mixedFile);
    const decoded = decode(file);
    file.fill(0xff);
    expect(sameDocument(decoded, reference)).toBe(true);
    const padded = new Uint8Array(mixedFile.byteLength + 11);
    padded.set(mixedFile, 7);
    const slice = padded.subarray(7, 7 + mixedFile.byteLength);
    const fromSlice = decode(slice);
    padded.fill(0);
    expect(sameDocument(fromSlice, reference)).toBe(true);
    const output = encodeStructured(reference);
    expect(output.byteOffset).toBe(0);
    expect(output.buffer.byteLength).toBe(output.byteLength);
  });

  test("a kind-2 file whose uncompressed container exceeds Emax or 2 Dmax stops at D10 before the CRC", () => {
    const file = encodeStructured(documentOf([plane(0, "x".repeat(60))]));
    const corrupt = file.slice();
    corrupt[36] = corrupt[36]! ^ 0xff;
    const payload = file.byteLength - 40;
    rejects("oversizedOutput", () => decode(corrupt, limits({ maximumDecodedBytes: Math.floor((payload - 1) / 2) })));
    rejects("checksumMismatch", () => decode(corrupt, limits({ maximumDecodedBytes: Math.ceil(payload / 2) })));
    rejects("oversizedInput", () => decode(file, limits({ maximumEncodedBytes: file.byteLength - 1 })));
    expect(codeOf(() => decode(file, limits({ maximumEncodedBytes: file.byteLength })))).toBe("ok");
    const header = resealed(file);
    new DataView(header.buffer).setBigUint64(28, 0xffffffffffffffffn, true);
    rejects("oversizedOutput", () => decode(header));
  });
});
