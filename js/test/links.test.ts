import { describe, expect, test } from "bun:test";

import { parse, links, type CrossPlaneLink } from "../src/index.ts";

/** Parses 3md source and returns its extracted cross-plane links. */
function extract(source: string): CrossPlaneLink[] {
  return links(parse(source));
}

describe("links()", () => {
  test("basic reference resolves source, target, and existence", () => {
    const result = extract("---\n3md: 0.1\n---\n@plane z=0\nsee [[z=1]]\n\n@plane z=1\nthere\n");
    expect(result).toEqual([{ sourceZ: 0, targetZ: 1, text: null, targetExists: true }]);
  });

  test("captures optional link text", () => {
    const result = extract("---\n3md: 0.1\n---\n@plane z=0\n[[z=1|go there]]\n\n@plane z=1\nthere\n");
    expect(result).toEqual([{ sourceZ: 0, targetZ: 1, text: "go there", targetExists: true }]);
  });

  test("present-but-empty link text is the empty string", () => {
    const result = extract("---\n3md: 0.1\n---\n@plane z=0\n[[z=1|]]\n\n@plane z=1\nx\n");
    expect(result).toEqual([{ sourceZ: 0, targetZ: 1, text: "", targetExists: true }]);
  });

  test("multiple links in one body are returned left to right", () => {
    const result = extract(
      "---\n3md: 0.1\n---\n@plane z=0\nfirst [[z=1]] then [[z=2|two]]\n\n@plane z=1\na\n\n@plane z=2\nb\n",
    );
    expect(result).toEqual([
      { sourceZ: 0, targetZ: 1, text: null, targetExists: true },
      { sourceZ: 0, targetZ: 2, text: "two", targetExists: true },
    ]);
  });

  test("links across planes follow source order", () => {
    const result = extract(
      "---\n3md: 0.1\n---\n@plane z=0\nto [[z=1]]\n\n@plane z=1\nback [[z=0]]\n",
    );
    expect(result).toEqual([
      { sourceZ: 0, targetZ: 1, text: null, targetExists: true },
      { sourceZ: 1, targetZ: 0, text: null, targetExists: true },
    ]);
  });

  test("dangling reference reports targetExists false", () => {
    const result = extract("---\n3md: 0.1\n---\n@plane z=0\ngo [[z=99]]\n");
    expect(result).toEqual([{ sourceZ: 0, targetZ: 99, text: null, targetExists: false }]);
  });

  test("decimal target matches a decimal plane z", () => {
    const result = extract("---\n3md: 0.1\n---\n@plane z=0\nhalf [[z=1.5]]\n\n@plane z=1.5\nmid\n");
    expect(result).toEqual([{ sourceZ: 0, targetZ: 1.5, text: null, targetExists: true }]);
  });

  test("non-finite and non-link sequences are ignored", () => {
    const result = extract(
      "---\n3md: 0.1\n---\n@plane z=0\n[[z=abc]] and [text](http://x) and [[notz]]\n",
    );
    expect(result).toEqual([]);
  });

  test("signed and exponent targets parse as finite decimals", () => {
    const result = extract("---\n3md: 0.1\n---\n@plane z=0\n[[z=-2.5]] and [[z=1e3]]\n");
    expect(result).toEqual([
      { sourceZ: 0, targetZ: -2.5, text: null, targetExists: false },
      { sourceZ: 0, targetZ: 1000, text: null, targetExists: false },
    ]);
  });

  test("a document with no links returns an empty array", () => {
    expect(extract("---\n3md: 0.1\n---\n@plane z=0\njust text\n")).toEqual([]);
  });
});
