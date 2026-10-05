import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import {
  DocumentCompression, DocumentDecodeLimits, DocumentStorageCodec, DocumentStorageError, DocumentStorageFormat,
  parse, serialize, type Document, type DocumentStorageErrorCode,
} from "../src/index.ts";

const encoder = new TextEncoder();
const plain = (): Document => parse("---\n3md: 1.0\naxis: space\n---\n@plane z=0\nBody\n");
function rejects(code: DocumentStorageErrorCode, operation: () => unknown): void {
  let caught: unknown;
  try { operation(); } catch (error) { caught = error; }
  expect(caught).toBeInstanceOf(DocumentStorageError);
  expect((caught as DocumentStorageError).code).toBe(code);
}
function crc(data: Uint8Array): number {
  let value = 0xffffffff;
  for (let index = 0; index < data.length; index += 1) {
    if (index >= 36 && index < 40) continue;
    value ^= data[index] ?? 0;
    for (let bit = 0; bit < 8; bit += 1) value = (value >>> 1) ^ ((value & 1) === 0 ? 0 : 0xedb88320);
  }
  return (value ^ 0xffffffff) >>> 0;
}
function resign(data: Uint8Array): Uint8Array {
  new DataView(data.buffer, data.byteOffset, data.byteLength).setUint32(36, crc(data), true); return data;
}

describe("bounded portable storage", () => {
  test("fixed envelope vector matches Swift and sliced data retains its byte offset", () => {
    const document: Document = { version: "1.0", axis: "layer", title: null, metadata: {}, preamble: null, planes: [] };
    const expected = Uint8Array.fromHex("336d6462696e0d0a0100010000000000000000002100000000000000210000000000000027cca0ba2d2d2d0a336d643a2022312e30220a617869733a20226c61796572220a2d2d2d0a");
    expect(DocumentStorageCodec.encode(document, DocumentStorageFormat.binary())).toEqual(expected);
    const padded = new Uint8Array(expected.length + 4); padded.set(expected, 2);
    expect(DocumentStorageCodec.decode(padded.subarray(2, -2))).toEqual(document);
    expect(DocumentStorageCodec.isBinary(encoder.encode("3MDB"))).toBe(false);
    expect(DocumentStorageCodec.isBinary(encoder.encode("3mdbin\r"))).toBe(false);
  });

  test("existing Swift canopy and grove envelopes remain readable and byte-identical", () => {
    for (const name of ["canopy", "shared-grove"]) {
      const text = readFileSync(new URL(`../../Examples/Extensions/${name}.3md`, import.meta.url));
      const binary = readFileSync(new URL(`../../Examples/Extensions/${name}.3mdb`, import.meta.url));
      const document = DocumentStorageCodec.decode(text);
      expect(DocumentStorageCodec.decode(binary)).toEqual(document);
      expect(DocumentStorageCodec.encode(document, DocumentStorageFormat.binary())).toEqual(new Uint8Array(binary));
    }
  });

  test("LZFSE is explicitly unavailable while unknown compression remains a different error", () => {
    rejects("compressionUnavailable", () => DocumentStorageCodec.encode(plain(), DocumentStorageFormat.binary(DocumentCompression.Lzfse)));
    const binary = readFileSync(new URL("../../Examples/Extensions/canopy.lzfse.3mdb", import.meta.url));
    rejects("compressionUnavailable", () => DocumentStorageCodec.decode(binary));
    rejects("unsupportedCompression", () => DocumentStorageCodec.encode(plain(), DocumentStorageFormat.binary(7 as DocumentCompression)));
  });

  test("header fields, checksums, trailing bytes and unsafe 64-bit lengths are checked", () => {
    const source = DocumentStorageCodec.encode(plain(), DocumentStorageFormat.binary());
    const corruptions: [number, number, DocumentStorageErrorCode][] = [
      [8, 2, "unsupportedVersion"], [10, 2, "unsupportedPayloadKind"], [11, 9, "unsupportedCompression"],
      [12, 1, "unsupportedFlags"], [16, 1, "nonzeroReserved"], [20, 0, "lengthMismatch"],
      [28, 0, "lengthMismatch"], [36, 0, "checksumMismatch"], [40, 0, "checksumMismatch"],
    ];
    for (const [offset, value, code] of corruptions) {
      const corrupted = source.slice(); corrupted[offset] = value; rejects(code, () => DocumentStorageCodec.decode(corrupted));
    }
    rejects("invalidContainer", () => DocumentStorageCodec.decode(source.subarray(0, 20)));
    rejects("lengthMismatch", () => DocumentStorageCodec.decode(source.subarray(0, -1)));
    const trailing = new Uint8Array(source.length + 1); trailing.set(source);
    rejects("lengthMismatch", () => DocumentStorageCodec.decode(trailing));
    const huge = source.slice(); new DataView(huge.buffer).setBigUint64(28, 0xffffffffffffffffn, true);
    rejects("oversizedOutput", () => DocumentStorageCodec.decode(huge));
    const invalidUTF8 = source.slice(); invalidUTF8[40] = 0xff;
    rejects("invalidUTF8", () => DocumentStorageCodec.decode(resign(invalidUTF8)));
  });

  test("resource constructors reject noninteger, nonpositive and raised limits", () => {
    for (const maximumEncodedBytes of [0, -1, 1.5, NaN, Infinity, 64 * 1024 * 1024 + 1]) {
      rejects("invalidLimits", () => new DocumentDecodeLimits({ maximumEncodedBytes }));
    }
    rejects("invalidLimits", () => new DocumentDecodeLimits({ maximumPlanes: 65_537 }));
    rejects("invalidLimits", () => new DocumentDecodeLimits({ maximumLines: 100_001 }));
    expect(new DocumentDecodeLimits({ maximumRecordBytes: 64 * 1024 * 1024 }).maximumRecordBytes).toBe(64 * 1024 * 1024);
  });
  test("public storage boundaries validate structurally typed plain-object policies", () => {
    const limits = { ...DocumentDecodeLimits.standard, maximumEncodedBytes: Infinity, maximumDecodedBytes: Infinity,
      maximumLines: Infinity, maximumPlanes: Infinity, maximumRecordBytes: Infinity };
    const document = plain();
    rejects("invalidLimits", () => DocumentStorageCodec.validate(document, limits));
    rejects("invalidLimits", () => DocumentStorageCodec.encode(document, DocumentStorageFormat.text, limits));
    rejects("invalidLimits", () => DocumentStorageCodec.decode(new TextEncoder().encode("bad"), limits));
  });

  test("exact byte boundaries succeed; physical lines, planes and entire records are bounded", () => {
    const document = plain(); const source = DocumentStorageCodec.encode(document);
    const limits = new DocumentDecodeLimits({ maximumEncodedBytes: source.length, maximumDecodedBytes: source.length });
    expect(DocumentStorageCodec.decode(source, limits)).toEqual(document);
    expect(DocumentStorageCodec.encode(document, DocumentStorageFormat.text, limits)).toEqual(source);
    rejects("oversizedInput", () => DocumentStorageCodec.decode(source, new DocumentDecodeLimits({ maximumEncodedBytes: source.length - 1 })));
    rejects("oversizedOutput", () => DocumentStorageCodec.encode(document, DocumentStorageFormat.text, new DocumentDecodeLimits({ maximumDecodedBytes: source.length - 1 })));
    rejects("tooManyLines", () => DocumentStorageCodec.decode(encoder.encode("\n".repeat(10)), new DocumentDecodeLimits({ maximumLines: 10 })));
    const two = parse("---\n3md: 1\n---\n@plane z=0\na\n@plane z=1\nb\n");
    rejects("tooManyPlanes", () => DocumentStorageCodec.decode(encoder.encode(serialize(two)), new DocumentDecodeLimits({ maximumPlanes: 1 })));
    rejects("oversizedRecord", () => DocumentStorageCodec.decode(encoder.encode(`---\n3md: 1\n---\n@plane z=0\n${"a".repeat(40)}\n${"b".repeat(40)}`), new DocumentDecodeLimits({ maximumRecordBytes: 64 })));
    rejects("oversizedRecord", () => DocumentStorageCodec.encode({ ...document, title: '"'.repeat(40) }, DocumentStorageFormat.text, new DocumentDecodeLimits({ maximumRecordBytes: 64 })));
  });

  test("preflight respects code fences and preserves the existing parser/serializer behavior", () => {
    const document = parse('---\n3md: 9.5\ncustom: first\ncustom: last\n---\n@plane z=0 custom=first custom=last\n```\n@plane z=1\n```\n~~~\n@plane z=2\n~~~\n');
    const before = serialize(document);
    expect(DocumentStorageCodec.decode(DocumentStorageCodec.encode(document), new DocumentDecodeLimits({ maximumPlanes: 1 }))).toEqual(document);
    expect(serialize(document)).toBe(before);
    expect(document.version).toBe("9.5");
    expect(document.metadata["custom"]).toBe("last");
  });

  test("direct lossy values and malformed decimals fail without changing legacy text APIs", () => {
    const document = plain(); const first = document.planes[0]; expect(first).toBeDefined();
    const cases: Document[] = [
      { ...document, version: "" }, { ...document, title: "physical\nline" }, { ...document, title: "\ud800" },
      { ...document, metadata: { axis: "bad" } }, { ...document, metadata: { "#comment": "bad" } },
      { ...document, planes: [{ ...first!, z: Infinity }] }, { ...document, planes: [{ ...first!, attributes: { Z: "bad" } }] },
      { ...document, planes: [{ ...first!, body: "\nBody" }] }, { ...document, planes: [{ ...first!, body: "@plane z=1\nInjected" }] },
    ];
    for (const value of cases) rejects("invalidDocument", () => DocumentStorageCodec.encode(value));
    rejects("invalidText", () => DocumentStorageCodec.decode(encoder.encode(`---\n3md: 1\n---\n@plane z=${"7".repeat(100_000)}x\nBody`)));
  });
  test("hostile interior and trailing ASCII whitespace remains exact through text and portable storage", () => {
    const interior = `a${" \t".repeat(250_000)}X`;
    const trailing = `a${" \t".repeat(250_000)}`;
    const source = `---\n3md: 1\n---\n@plane z=0\n${interior}\n${trailing}\n`;
    const parsed = parse(source);
    expect(parsed.planes[0]?.body).toBe(`${interior}\n${trailing}`);
    expect(DocumentStorageCodec.decode(new TextEncoder().encode(source))).toEqual(parsed);
    const binary = DocumentStorageCodec.encode(parsed, DocumentStorageFormat.binary());
    expect(DocumentStorageCodec.decode(binary)).toEqual(parsed);
    expect(serialize(parsed)).toContain(`${interior}\n${trailing}\n`);
    const scalar = `value${" \t".repeat(250_000)}X`;
    expect(parse(`---\n3md: 1\nmetadata: ${scalar}\n---\n`).metadata["metadata"]).toBe(scalar);
  });

  test("pre-aborted operations propagate the abort reason", () => {
    const abort = new AbortController(); const reason = new Error("cancelled"); abort.abort(reason);
    for (const operation of [() => DocumentStorageCodec.validate(plain(), undefined, abort.signal),
      () => DocumentStorageCodec.encode(plain(), undefined, undefined, abort.signal),
      () => DocumentStorageCodec.decode(encoder.encode("bad"), undefined, abort.signal)]) {
      expect(operation).toThrow(reason);
    }
  });

  test("new canonical maps use Swift Unicode key equality, scalar order and original spelling", () => {
    const metadata = { "😀": "emoji", "\ue000": "private", "é": "composed", z: "last-ascii", "e\u0301": "updated" };
    const { z: _position, ...attributes } = metadata;
    const document = { ...plain(), metadata, planes: [{ ...plain().planes[0]!, attributes: { ...attributes, zz: "last-ascii" } }] };
    const text = new TextDecoder().decode(DocumentStorageCodec.encode(document));
    expect(text.indexOf('z: "last-ascii"')).toBeLessThan(text.indexOf('é: "updated"'));
    expect(text.indexOf('é: "updated"')).toBeLessThan(text.indexOf('\ue000: "private"'));
    expect(text.indexOf('\ue000: "private"')).toBeLessThan(text.indexOf('😀: "emoji"'));
    expect(text).toContain(' zz="last-ascii" é="updated" \ue000="private" 😀="emoji"');
    expect(text).not.toContain('e\u0301:');
    const decoded = DocumentStorageCodec.decode(new TextEncoder().encode('---\n3md: 1\ne\u0301: first\né: last\n---\n@plane z=0 e\u0301=first é=last\nBody\n'));
    expect(Object.keys(decoded.metadata)).toEqual(["e\u0301"]);
    expect(decoded.metadata["e\u0301"]).toBe("last");
    expect(Object.keys(decoded.planes[0]?.attributes ?? {})).toEqual(["e\u0301"]);
    expect(Object.keys(parse('---\n3md: 1\ne\u0301: first\né: last\n---\n').metadata)).toEqual(["e\u0301", "é"]);
  });
});
