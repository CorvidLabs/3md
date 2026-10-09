import { describe, expect, test } from "bun:test";
import { parse, DocumentStorageCodec } from "../js/src/index.ts";
import { indexLines, kind2Bytes, packDocuments, searchRank, searchScore, sectionsToDocument } from "./gather.ts";

const readme = `# Project

The opening.

## Install

Run bun.

## Notes

A heading inside a fence stays put:

\`\`\`
# not a plane
\`\`\`
`;

describe("sections", () => {
  test("readme headings become planes and a fence does not", () => {
    const text = sectionsToDocument(readme, "README.md");
    const document = parse(text);
    expect(document.title).toBe("README");
    expect(document.axis).toBe("section");
    expect(document.planes.map((plane) => plane.label)).toEqual(["Project", "Install", "Notes"]);
    expect(document.planes[0]?.body).toContain("The opening.");
    expect(document.planes[2]?.body).toContain("# not a plane");
    expect(document.planes).toHaveLength(3);
  });
});

describe("pack", () => {
  test("markdown files and a 3md file become one document", () => {
    const text = packDocuments([
      { path: "notes/beta.md", text: "# Beta\n\nSecond." },
      { path: "notes/alpha.3md", text: "---\n3md: \"1.0\"\naxis: \"layer\"\ntitle: \"Alpha\"\n---\n\n@plane z=0 label=\"Ground\"\nFloor.\n" },
    ]);
    const document = parse(text);
    expect(document.title).toBe("Documents");
    expect(document.axis).toBe("doc");
    expect(document.planes.map((plane) => plane.label)).toEqual(["alpha", "beta / Beta"]);
    expect(document.planes[0]?.body).toBe("Floor.");
  });
});

describe("kind 2", () => {
  test("the download round-trips through the library", () => {
    const text = sectionsToDocument("# Grove\n\nTrees.\n", "grove.md");
    const bytes = kind2Bytes(text);
    expect(new TextDecoder().decode(bytes.slice(0, 8))).toBe("3mdbin\r\n");
    expect(bytes[10]).toBe(2);
    const decoded = DocumentStorageCodec.decode(bytes);
    expect(decoded.title).toBe("grove");
    expect(decoded.planes[0]?.label).toBe("Grove");
    expect(decoded.planes[0]?.body).toContain("Trees.");
  });
});

describe("lines", () => {
  test("a line in the second plane remembers that plane", () => {
    const text = "---\n3md: \"1.0\"\naxis: \"time\"\ntitle: \"Week\"\n---\n\n@plane z=0 label=\"Monday\"\nStart.\n\n@plane z=1 label=\"Tuesday\"\nShip the viewer.\n";
    const hits = indexLines("notes/week.3md", text);
    const hit = hits.find((item) => item.label === "Ship the viewer.");
    expect(hit?.planeIndex).toBe(1);
    expect(hit?.meta).toBe("notes/week.3md · Tuesday");
    expect(hit?.text).toBe(text);
  });
});

describe("search", () => {
  test("a typed phrase beats a fuzzy neighbor, and a fuzzy name still matches", () => {
    const exact = searchRank("game-of-life.3md", "Conway's Game of Life", "frame · game-of-life.3md");
    const neighbor = searchRank("game-of-life.3md", "Conway Spacetime", "generation · conways-game-of-life.3md");
    const fuzzy = searchScore("conw", "Conway's Game of Life");
    expect(exact).not.toBeNull();
    expect(neighbor).not.toBeNull();
    expect(fuzzy).not.toBeNull();
    expect(exact as number).toBeGreaterThan(neighbor as number);
    expect(searchScore("zzz", "Linked village")).toBeNull();
  });
});
