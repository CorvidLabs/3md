import { describe, expect, test } from "bun:test";
import { openBytes, openFileSet, openText, OpenDocumentError } from "./open-document.ts";

async function bytes(path: string): Promise<Uint8Array> {
  return new Uint8Array(await Bun.file(path).arrayBuffer());
}

describe("open document", () => {
  test("text that is not a composition stays the caller's source", async () => {
    const text = await Bun.file("Examples/game-of-life.3md").text();
    const opened = openText(text);
    expect(opened.container).toBe("text");
    expect(opened.pieces).toEqual([]);
    expect(opened.text).toBe(text);
    expect(opened.note).toBeNull();
  });

  test("a composition profile shows the root document and the other entry", async () => {
    const text = await Bun.file("Examples/Extensions/shared-grove.3md").text();
    const opened = openText(text);
    expect(opened.text).toContain("Shared grove");
    expect(opened.activeId).toBe("grove");
    expect(opened.pieces.map((piece) => piece.id)).toEqual(["profile", "canopy", "grove"]);
    expect(opened.pieces.find((piece) => piece.id === "canopy")?.text).toContain("Reusable canopy");
    expect(opened.pieces.find((piece) => piece.id === "profile")?.text).toBe(text);
  });

  test("kind 2 canopy bytes become the text document", async () => {
    const opened = openBytes(await bytes("Examples/Extensions/canopy.structured.3mdb"));
    expect(opened.container).toBe("kind2");
    expect(opened.text).toContain("Reusable canopy");
    expect(opened.note).toContain("kind 2");
    expect(opened.pieces).toEqual([]);
  });

  test("uncompressed kind 1 canopy bytes become the same document", async () => {
    const opened = openBytes(await bytes("Examples/Extensions/canopy.3mdb"));
    expect(opened.container).toBe("kind1");
    expect(opened.text).toContain("Reusable canopy");
  });

  test("a kind 2 composition shows the grove, not the envelope", async () => {
    const opened = openBytes(await bytes("Examples/Extensions/shared-grove.structured.3mdb"));
    expect(opened.container).toBe("kind2");
    expect(opened.activeId).toBe("grove");
    expect(opened.text).toContain("Shared grove");
    expect(opened.text).not.toContain("3md-composition-1");
    expect(opened.pieces.map((piece) => piece.id)).toContain("canopy");
  });

  test("Apple LZFSE is refused", async () => {
    const lzfse = await bytes("Examples/Extensions/canopy.lzfse.3mdb");
    expect(() => openBytes(lzfse)).toThrow(OpenDocumentError);
    try {
      openBytes(lzfse);
    } catch (error) {
      expect(error).toBeInstanceOf(OpenDocumentError);
      expect((error as OpenDocumentError).code).toBe("compressionUnavailable");
      expect((error as OpenDocumentError).message).toContain("LZFSE");
    }
  });

  test("a linked village folder resolves from supplied bytes", async () => {
    const names = ["scene.3md", "models/house.3md", "models/tree.3md", "models/tower.3md"];
    const files = await Promise.all(names.map(async (path) => ({
      path,
      data: await bytes(`Examples/LinkedVillage/${path}`),
    })));
    const opened = openFileSet(files);
    expect(opened.text).toContain("Linked village");
    expect(opened.pieces.map((piece) => piece.label).join(" ")).toContain("models/house.3md");
    expect(opened.pieces.map((piece) => piece.label).join(" ")).toContain("models/tower.3md");
    const tower = opened.pieces.find((piece) => piece.label.endsWith("tower.3md"));
    expect(tower?.text).toContain("|___| T");
    expect(opened.pieces.some((piece) => piece.label.endsWith("models/tree.3md"))).toBe(true);
  });

  test("the same village resolves when the drop includes the parent folder", async () => {
    const names = ["scene.3md", "models/house.3md", "models/tree.3md", "models/tower.3md"];
    const files = await Promise.all(names.map(async (path) => ({
      path: `LinkedVillage/${path}`,
      data: await bytes(`Examples/LinkedVillage/${path}`),
    })));
    const opened = openFileSet(files);
    expect(opened.text).toContain("Linked village");
    expect(opened.pieces.some((piece) => piece.label.endsWith("models/house.3md"))).toBe(true);
  });
});
