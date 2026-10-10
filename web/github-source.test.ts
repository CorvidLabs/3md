import { describe, expect, test } from "bun:test";
import { loadGitHubPoint, parseGitHubLocator } from "./github-source.ts";

describe("parseGitHubLocator", () => {
  test("reads a repo, a folder, a file, and a raw URL", () => {
    expect(parseGitHubLocator("https://github.com/CorvidLabs/3md")).toEqual({
      owner: "CorvidLabs",
      repo: "3md",
      explicitRef: null,
      path: "",
      kind: "repo",
    });
    expect(parseGitHubLocator("CorvidLabs/3md")).toMatchObject({ kind: "repo", owner: "CorvidLabs" });
    expect(parseGitHubLocator("https://github.com/CorvidLabs/3md/tree/main/Examples")).toMatchObject({
      kind: "folder",
      explicitRef: "main",
      path: "Examples",
    });
    expect(parseGitHubLocator("https://github.com/CorvidLabs/3md/blob/main/Examples/dungeon.3md")).toMatchObject({
      kind: "file",
      path: "Examples/dungeon.3md",
    });
    expect(parseGitHubLocator("https://raw.githubusercontent.com/CorvidLabs/3md/main/README.md")).toMatchObject({
      kind: "file",
      path: "README.md",
      explicitRef: "main",
    });
    expect(parseGitHubLocator("not a repo")).toBeNull();
    expect(parseGitHubLocator("https://github.com/CorvidLabs/3md/issues")).toBeNull();
  });
});

describe("loadGitHubPoint", () => {
  test("loads text and 3md files from a public tree and skips other files", async () => {
    const loaded = await loadGitHubPoint("https://github.com/CorvidLabs/3md", async (url) => {
      const parsed = new URL(String(url));
      if (parsed.hostname === "api.github.com" && parsed.pathname === "/repos/CorvidLabs/3md") {
        return Response.json({ default_branch: "main" });
      }
      if (parsed.hostname === "api.github.com" && parsed.pathname.startsWith("/repos/CorvidLabs/3md/git/trees/")) {
        return Response.json({
          truncated: false,
          tree: [
            { path: "README.md", type: "blob", size: 6 },
            { path: "Examples/dungeon.3md", type: "blob", size: 40 },
            { path: "image.png", type: "blob", size: 9 },
          ],
        });
      }
      if (parsed.hostname === "raw.githubusercontent.com") {
        const body = parsed.pathname.endsWith("/README.md") ? "# Hi\n" : "@plane z=0 label=\"Room\"\nDoor.\n";
        return new Response(body, { status: 200 });
      }
      return new Response("missing", { status: 404 });
    });
    expect(loaded.ref).toBe("main");
    expect(loaded.label).toBe("CorvidLabs/3md");
    expect(loaded.files.map((file) => file.path)).toEqual(["Examples/dungeon.3md", "README.md"]);
    expect(loaded.truncated).toBe(false);
  });
});
