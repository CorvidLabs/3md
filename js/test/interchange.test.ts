import { describe, expect, test } from "bun:test";
import {
  DocumentDecodeLimits, DocumentStorageCodec, DocumentStorageFormat,
  links, parse, serialize,
} from "../src/index.ts";

const whitespace = [0x0009, 0x0020, 0x00a0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003,
  0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x200b, 0x202f, 0x205f, 0x3000];
const encoder = new TextEncoder();

describe("lossless cross-language interchange", () => {
  test("raw parsing and bounded decoding use the literal Foundation whitespace set", () => {
    for (const unit of whitespace) {
      const gap = String.fromCharCode(unit);
      const source = `${gap}\n${gap}---${gap}\n${gap}3md${gap}:${gap}1${gap}\naxis: ${gap}TIME${gap}\ntitle: ${gap}Title${gap}\n---${gap}\n${gap}\nBody\n${gap}`;
      const parsed = parse(source);
      expect(parsed.version).toBe("1"); expect(parsed.axis).toBe("time"); expect(parsed.title).toBe("Title");
      expect(parsed.planes[0]?.body).toBe("Body");
      expect(DocumentStorageCodec.decode(encoder.encode(source))).toEqual(parsed);
    }
    for (const gap of ["\u000b", "\u000c", "\u0085", "\u2028", "\u2029", "\ufeff"]) {
      expect(() => parse(`\n${gap}---\n3md: 1\n---\nBody`)).toThrow();
    }
  });
  test("Unicode whitespace fences do not invent directives during bounded preflight", () => {
    const source = "---\n3md: 1\n---\n@plane z=0\n\u200b```\u200b\n@plane z=1\n\u200b```\n";
    const parsed = parse(source);
    expect(parsed.planes).toHaveLength(1);
    expect(DocumentStorageCodec.decode(encoder.encode(source), new DocumentDecodeLimits({ maximumPlanes: 1 }))).toEqual(parsed);
    expect(parse("---\n3md: 1\n---\n\u00a0@plane z=1\nBody").planes[0]?.body).toBe("\u00a0@plane z=1\nBody");
  });
  test("UTF-8 decoding leaves BOM removal to the parser exactly once", () => {
    const source = "---\n3md: 1\n---\nBody\n";
    expect(DocumentStorageCodec.decode(encoder.encode(`\ufeff${source}`))).toEqual(parse(source));
    expect(() => parse(`\ufeff\ufeff${source}`)).toThrow();
    try { DocumentStorageCodec.decode(encoder.encode(`\ufeff\ufeff${source}`)); throw new Error("Expected invalid text."); }
    catch (error) { expect((error as { code: string }).code).toBe("invalidText"); }
  });
  test("source dictionary collisions retain first spelling and the last assignment in source order", () => {
    const source = "---\n3md: 1\ne\u0301: first\né: second\ne\u0301: final\n__proto__: safe\n---\n@plane z=0 E\u0301=first É=second e\u0301=final __proto__=safe\nBody\n";
    const parsed = parse(source);
    expect(Object.keys(parsed.metadata)).toEqual(["e\u0301", "__proto__"]);
    expect(parsed.metadata["e\u0301"]).toBe("final");
    expect(Object.keys(parsed.planes[0]?.attributes ?? {})).toEqual(["e\u0301", "__proto__"]);
    expect(parsed.planes[0]?.attributes["e\u0301"]).toBe("final");
    expect(parsed.planes[0]?.attributes["__proto__"]).toBe("safe");
    expect(Object.getPrototypeOf(parsed.metadata)).toBeNull();
    expect(parsed.metadata["__proto__"]).toBe("safe");
    expect(DocumentStorageCodec.decode(DocumentStorageCodec.encode(parsed, DocumentStorageFormat.binary()))).toEqual(parsed);
  });
  test("legacy serialization preserves literal apostrophes, edge whitespace, quotes and backslashes", () => {
    const base = parse("---\n3md: 1\n---\n@plane z=0\nBody\n");
    for (const scalar of ["'quoted'", "''", "'", "\u00a0edge\u200b", "\u3000", 'say "hello"', "C:\\folder\\", "emoji 😀"]) {
      const document = { ...base, version: scalar, axis: "'time'", title: scalar, metadata: { value: scalar } };
      expect(parse(serialize(document))).toEqual(document);
    }
  });
  test("legacy number formatting and Unicode scalar key order agree with canonical wire writers", () => {
    const parsed = parse("---\n3md: 1\n😀: emoji\n\ue000: private\ne\u0301: accent\nz: ascii\n---\n@plane z=1000000000000000 x=0.000001\nBody\n");
    const source = serialize(parsed);
    expect(source).toContain("@plane z=1000000000000000.0 x=1e-06\n");
    expect(source.indexOf("z: ascii")).toBeLessThan(source.indexOf("e\u0301: accent"));
    expect(source.indexOf("e\u0301: accent")).toBeLessThan(source.indexOf("\ue000: private"));
    expect(source.indexOf("\ue000: private")).toBeLessThan(source.indexOf("😀: emoji"));
    expect(parse(source)).toEqual(parsed);
  });
  test("links preserve long finite targets, long labels and multiline labels", () => {
    const label = `${"label ".repeat(1000)}\nsecond line`;
    const source = `---\n3md: 1\n---\n@plane z=0\n[[z=${"0".repeat(1000)}1|${label}]]\n[[z=1|]]\n@plane z=1\nTarget\n`;
    expect(links(parse(source))).toEqual([
      { sourceZ: 0, targetZ: 1, text: label, targetExists: true },
      { sourceZ: 0, targetZ: 1, text: "", targetExists: true },
    ]);
  });
  test("linear link scanning preserves reference regex matching for malformed nested candidates", () => {
    const bodies = ["[[z=|bad [[z=1]]", "[[z=bad [[z=1]]", "[[z=bad] [[z=1]]", "[[z=1|a [[z=2]]", "[[z=1|no close] [[z=2]]", "[[z=]] [[z=.5]]"];
    for (const body of bodies) {
      const matches = [...body.matchAll(/\[\[z=([^\]|]+)(?:\|([^\]]*))?\]\]/g)]
        .filter((match) => /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(match[1] ?? ""))
        .map((match) => ({ sourceZ: 0, targetZ: Number(match[1]), text: match[2] ?? null, targetExists: false }));
      expect(links(parse(`---\n3md: 1\n---\n@plane z=0\n${body}`))).toEqual(matches);
    }
    const hostile = "[[z=1|".repeat(100_000);
    expect(links(parse(`---\n3md: 1\n---\n@plane z=0\n${hostile}`))).toEqual([]);
  });
});
