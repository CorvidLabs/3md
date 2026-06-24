import { describe, expect, test } from "bun:test";
import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import { parse, serialize, ParseError, type Document, type ParseErrorCode } from "../src/index.ts";

const here = dirname(fileURLToPath(import.meta.url));
const conformanceDir = join(here, "..", "..", "conformance");

interface ExpectedPlane {
  readonly z: number;
  readonly label: string | null;
  readonly x: number | null;
  readonly y: number | null;
  readonly attributes: Record<string, string>;
  readonly body: string;
}

interface ValidVector {
  readonly name: string;
  readonly source: string;
  readonly expected: {
    readonly version: string;
    readonly axis: string;
    readonly title: string | null;
    readonly metadata: Record<string, string>;
    readonly preamble: string | null;
    readonly planes: readonly ExpectedPlane[];
  };
}

interface InvalidVector {
  readonly name: string;
  readonly source: string;
  readonly error: ParseErrorCode;
}

type Vector = ValidVector | InvalidVector;

function isInvalid(vector: Vector): vector is InvalidVector {
  return "error" in vector;
}

/** Normalizes a parsed document into the plain shape used by the vectors. */
function normalize(document: Document): ValidVector["expected"] {
  return {
    version: document.version,
    axis: document.axis,
    title: document.title,
    metadata: { ...document.metadata },
    preamble: document.preamble,
    planes: document.planes.map((plane) => ({
      z: plane.z,
      label: plane.label,
      x: plane.x,
      y: plane.y,
      attributes: { ...plane.attributes },
      body: plane.body,
    })),
  };
}

async function loadVectors(): Promise<Array<{ file: string; vector: Vector }>> {
  const files = readdirSync(conformanceDir)
    .filter((name) => name.endsWith(".json"))
    .sort();

  const loaded: Array<{ file: string; vector: Vector }> = [];
  for (const file of files) {
    const text = await Bun.file(join(conformanceDir, file)).text();
    loaded.push({ file, vector: JSON.parse(text) as Vector });
  }
  return loaded;
}

const vectors = await loadVectors();

describe("conformance vectors", () => {
  test("at least one valid and one invalid vector exist", () => {
    expect(vectors.some(({ vector }) => isInvalid(vector))).toBe(true);
    expect(vectors.some(({ vector }) => !isInvalid(vector))).toBe(true);
  });

  for (const { file, vector } of vectors) {
    test(`${file}: ${vector.name}`, () => {
      if (isInvalid(vector)) {
        let thrown: unknown;
        expect(() => {
          try {
            parse(vector.source);
          } catch (error) {
            thrown = error;
            throw error;
          }
        }).toThrow(ParseError);
        expect(thrown).toBeInstanceOf(ParseError);
        expect((thrown as ParseError).code).toBe(vector.error);
      } else {
        const result = normalize(parse(vector.source));
        expect(result).toEqual(vector.expected as unknown as ValidVector["expected"]);
      }
    });
  }
});

describe("round trip: parse -> serialize -> parse", () => {
  for (const { file, vector } of vectors) {
    if (isInvalid(vector)) {
      continue;
    }
    test(`${file}: ${vector.name}`, () => {
      const first = parse(vector.source);
      const serialized = serialize(first);
      const second = parse(serialized);
      expect(normalize(second)).toEqual(normalize(first));
    });
  }
});
