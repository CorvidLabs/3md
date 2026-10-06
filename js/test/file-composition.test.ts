import { describe, expect, test } from "bun:test";
import {
  DocumentComposition, DocumentCompositionCodec, DocumentCompositionError, DocumentCompositionLimits,
  DocumentDecodeLimits, DocumentFileComposition, DocumentFileCompositionError, DocumentStorageCodec,
  DocumentStorageError, DocumentStorageFormat,
  type Document, type DocumentCompositionErrorCode, type DocumentFileCompositionErrorCode, type DocumentFileSource,
  type DocumentStorageErrorCode,
} from "../src/index.ts";

function document(body = "Markdown stays local", metadata: Record<string, string> = {}): Document {
  return { version: "2.0", axis: "custom", title: "Linked model", preamble: "Host controls glyph placement.", metadata,
    planes: [{ z: 1, x: 2, y: null, label: "Section", attributes: {}, body }] };
}
function source(path: string, value = document(), binary = false): DocumentFileSource {
  return { path, data: DocumentStorageCodec.encode(value, binary ? DocumentStorageFormat.binary() : DocumentStorageFormat.text) };
}
function host(ledger: string): Document { return document("1 2\n[ordinary Markdown](not-a-file-link.3md)", { "3md-files": ledger, retained: "opaque" }); }
function rejects(code: DocumentFileCompositionErrorCode, operation: () => unknown): void {
  try { operation(); throw new Error("Expected file composition failure"); }
  catch (error) { expect(error).toBeInstanceOf(DocumentFileCompositionError); expect((error as DocumentFileCompositionError).code).toBe(code); }
}
function graphRejects(code: DocumentCompositionErrorCode, operation: () => unknown): void {
  try { operation(); throw new Error("Expected composition failure"); }
  catch (error) { expect(error).toBeInstanceOf(DocumentCompositionError); expect((error as DocumentCompositionError).code).toBe(code); }
}

describe("explicit supplied-file composition", () => {
  test("simple and repeated glyph links deduplicate files and refresh changed child bytes", () => {
    const root = host('{"2":"child.3md","1":"./child.3md"}');
    const sources = [source("root.3md", root), source("child.3md", document("Original child")),
      { path: "unreachable.3md", data: new Uint8Array([0xff]) }];
    const first = DocumentFileComposition.resolve("./root.3md", sources);
    expect(first.rootPath).toBe("root.3md");
    expect(first.resolvedPaths).toEqual(["child.3md", "root.3md"]);
    expect(first.composition.entries).toHaveLength(2);
    expect(first.fileRootIDs).toEqual({ "child.3md": "file-000000", "root.3md": "file-000001" });
    expect(first.composition.rootEntry.document).toEqual({ ...root, metadata: { retained: "opaque" } });
    expect(first.composition.rootEntry.references).toEqual([
      { targetID: "file-000000", attributes: { glyph: "1", "source-file": "child.3md" } },
      { targetID: "file-000000", attributes: { glyph: "2", "source-file": "child.3md" } },
    ]);
    const refreshed = DocumentFileComposition.resolve("root.3md", [sources[0]!, source("child.3md", document("Changed child"))]);
    expect(refreshed.composition.entry("file-000000")?.document.planes[0]?.body).toBe("Changed child");
    expect(first.composition.entry("file-000000")?.document.planes[0]?.body).toBe("Original child");
    expect(Object.isFrozen(first) && Object.isFrozen(first.fileRootIDs) && Object.isFrozen(first.resolvedPaths)).toBe(true);
  });

  test("nested parent paths and duplicate basenames resolve relative to each containing file", () => {
    const result = DocumentFileComposition.resolve("root.3md", [
      source("root.3md", host('{"1":"a/child.3md","2":"b/child.3md"}')),
      source("a/child.3md", host('{"x":"../shared/model.3md"}')),
      source("b/child.3md", document("Different child")), source("shared/model.3md", document("Shared leaf"), true),
    ]);
    expect(result.resolvedPaths).toEqual(["a/child.3md", "b/child.3md", "root.3md", "shared/model.3md"]);
    expect(result.composition.entry(result.fileRootIDs["a/child.3md"]!)?.references[0]?.targetID)
      .toBe(result.fileRootIDs["shared/model.3md"]);
    expect(result.composition.entry(result.fileRootIDs["b/child.3md"]!)?.document.planes[0]?.body).toBe("Different child");
  });

  test("binary nested bundles retain unused entries, stable identities and opaque edges before new ledger edges", () => {
    const attributes = JSON.parse('{"3md-id":"original-reference","opaque":"\\u0000\\n雪","__proto__":"kept"}') as Record<string, string>;
    const leaf = { ...document("Existing leaf", { "3md-id": "existing-document" }),
      planes: [{ ...document().planes[0]!, attributes: { "3md-id": "existing-plane" } }] };
    const nested = new DocumentComposition("zRoot", [
      { id: "zRoot", document: host('{"1":"external.3mdb"}'), references: [{ targetID: "aLeaf", attributes }] },
      { id: "aLeaf", document: leaf, references: [] },
      { id: "uUnused", document: host('{"2":"unused-child.3md"}'), references: [] },
    ]);
    const result = DocumentFileComposition.resolve("root.3mdb", [
      source("root.3mdb", DocumentCompositionCodec.document(nested), true),
      source("external.3mdb", document("Binary child"), true), source("unused-child.3md", document("Unused ledger child")),
    ]);
    expect(result.composition.entries).toHaveLength(5);
    expect(result.composition.rootID).toBe("file-000003");
    expect(result.composition.entry("file-000001")?.document).toEqual(leaf);
    expect(result.composition.rootEntry.references).toEqual([
      { targetID: "file-000001", attributes },
      { targetID: "file-000000", attributes: { glyph: "1", "source-file": "external.3mdb" } },
    ]);
    expect(result.composition.entry("file-000002")?.references[0]?.targetID).toBe("file-000004");
    expect(result.composition.rootEntry.references[1]?.attributes["3md-id"]).toBeUndefined();
    for (const entry of result.composition.entries) expect(Object.hasOwn(entry.document.metadata, "3md-files")).toBe(false);
    const portable = DocumentStorageCodec.encode(DocumentCompositionCodec.document(result.composition), DocumentStorageFormat.binary());
    expect(DocumentCompositionCodec.decode(portable)).toEqual(result.composition);
    expect(DocumentCompositionCodec.decode(DocumentCompositionCodec.encode(result.composition))).toEqual(result.composition);
  });

  test("nested profile records use the outer composition policy while embedded ordinary records retain child bounds", () => {
    const body = "x".repeat(4 * 1024 * 1024 + 256);
    const nested = new DocumentComposition("a", [
      { id: "a", document: document(body), references: [] },
      { id: "b", document: document(body), references: [] },
    ]);
    const text = DocumentCompositionCodec.encode(nested);
    expect(text.length).toBeGreaterThan(DocumentDecodeLimits.standard.maximumRecordBytes);
    const result = DocumentFileComposition.resolve("large.3md", [{ path: "large.3md", data: text }]);
    expect(result.composition.entries).toHaveLength(2);
    expect(result.composition.rootEntry.document.planes[0]?.body).toBe(body);
    expect(() => DocumentFileComposition.resolve("large.3md", [{ path: "large.3md", data: text }], undefined,
      new DocumentDecodeLimits({ maximumRecordBytes: 1024 }))).toThrow(DocumentStorageError);
  });

  test("paths use NFC and Unicode scalar ordering rather than UTF16 or locale sorting", () => {
    const result = DocumentFileComposition.resolve("root.3md", [
      source("root.3md", host('{"z":"😀.3md","a":"\\ue000.3md","e":"e\\u0301.3md"}')),
      source("😀.3md"), source("\ue000.3md"), source("é.3md"),
    ]);
    expect(result.resolvedPaths).toEqual(["root.3md", "é.3md", "\ue000.3md", "😀.3md"]);
    expect(result.composition.rootEntry.references.map((edge) => edge.attributes["source-file"]))
      .toEqual(["\ue000.3md", "é.3md", "😀.3md"]);
    expect(DocumentFileComposition.resolvePath("../e\u0301.3md", "folder/owner.3md")).toBe("é.3md");
    expect(DocumentFileComposition.resolvePath("%2e%2e/file.any", "folder/owner.3md")).toBe("folder/%2e%2e/file.any");
    expect(DocumentFileComposition.resolvePath("File", "folder/owner.3md")).not.toBe(DocumentFileComposition.resolvePath("file", "folder/owner.3md"));
  });

  test("path grammar rejects escape, absolute paths, empty segments, controls and normalized aliases", () => {
    for (const path of ["", "/root.3md", "a\\b", "a:b", "a//b", "a/", "..", "../root.3md", "a/../../b", ".", "a/..", "a\u0000b", "a\u007fb", "\ud800"]) {
      rejects("invalidPath", () => DocumentFileComposition.resolvePath(path));
    }
    rejects("invalidPath", () => DocumentFileComposition.resolvePath("child", "/owner"));
    rejects("duplicatePath", () => DocumentFileComposition.resolve("root", [source("root"), source("a/../root")]));
    rejects("duplicatePath", () => DocumentFileComposition.resolve("root", [source("root"), source("e\u0301"), source("é")]));
  });

  test("strict ledger scanner rejects duplicate escaped keys, malformed JSON and invalid glyphs before values", () => {
    expect(DocumentFileComposition.ledger(document())).toEqual([]);
    expect(DocumentFileComposition.ledger(host('{}'))).toEqual([]);
    expect(DocumentFileComposition.ledger(host('{"~":"last","!":"first"}'))).toEqual([{ glyph: "!", source: "first" }, { glyph: "~", source: "last" }]);
    for (const ledger of ['{"1":"a","\\u0031":"b"}', '[]', 'null', '{"1":true}', '{"1":2}', '{"1":{}}', '{"1":"a",}', '{"1":"a"} false', '{"1":"\\ud800"}', '{"1":"\\udc00"}', '{"1":"a\u0001b"}', '{"1":"a\tb"}', '{"1":"a'] ) {
      rejects("invalidLedger", () => DocumentFileComposition.ledger(host(ledger)));
    }
    for (const glyph of [" ", "é", "😀", "two", "\n"]) rejects("invalidGlyph", () => DocumentFileComposition.ledger(host(JSON.stringify({ [glyph]: "child" }))));
    rejects("invalidGlyph", () => DocumentFileComposition.ledger(host('{"é":"a","e\\u0301":"b"}')));
    rejects("invalidGlyph", () => DocumentFileComposition.ledger(host('{"é":null}')));
    rejects("invalidPath", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":""}'))]));
  });

  test("missing files and malformed reachable storage retain distinct errors, unreachable storage is ignored", () => {
    rejects("missingFile", () => DocumentFileComposition.resolve("missing", []));
    rejects("missingFile", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"missing"}'))]));
    expect(() => DocumentFileComposition.resolve("bad", [{ path: "bad", data: new Uint8Array([255]) }])).toThrow(DocumentStorageError);
    expect(DocumentFileComposition.resolve("root", [source("root"), { path: "bad", data: new Uint8Array([255]) }]).resolvedPaths).toEqual(["root"]);
  });

  test("file cycles also fail when unused bundle entries form a cycle across files", () => {
    graphRejects("cycle", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"root"}'))]));
    graphRejects("cycle", () => DocumentFileComposition.resolve("a", [source("a", host('{"1":"b"}')), source("b", host('{"2":"a"}'))]));
    const graph = new DocumentComposition("main", [
      { id: "main", document: document(), references: [] },
      { id: "unused", document: host('{"1":"b"}'), references: [] },
    ]);
    graphRejects("cycle", () => DocumentFileComposition.resolve("a", [source("a", DocumentCompositionCodec.document(graph)), source("b", host('{"1":"a"}'))]));
  });

  test("supplied counts, original path bytes and reachable bytes use input limits before decoding", () => {
    rejects("inputLimit", () => DocumentFileComposition.resolve("root", [source("root"), source("unused")], new DocumentCompositionLimits({ maximumDefinitions: 1 })));
    rejects("inputLimit", () => DocumentFileComposition.resolve("root", [{ path: "root", data: new Uint8Array([255]) }], new DocumentCompositionLimits({ maximumProfileBytes: 7 })));
    const root = source("r");
    rejects("inputLimit", () => DocumentFileComposition.resolve("r", [root], new DocumentCompositionLimits({ maximumProfileBytes: root.data.length - 1 })));
    expect(DocumentFileComposition.resolve("r", [root, { path: "unreachable", data: new Uint8Array(500) }]).resolvedPaths).toEqual(["r"]);
    const bound = DocumentDecodeLimits.standard.maximumRecordBytes;
    rejects("inputLimit", () => DocumentFileComposition.resolvePath("a".repeat(bound), "b"));
    rejects("inputLimit", () => DocumentFileComposition.ledger(host(" ".repeat(bound + 1))));
  });

  test("outer recognition applies child byte and line policies before its lowered plane ceiling", () => {
    const base = document();
    const value = { ...base, planes: [{ ...base.planes[0]!, z: 0 }, { ...base.planes[0]!, z: 1 }] };
    for (const binary of [false, true]) {
      const input = source("root", value, binary);
      const policies: [DocumentDecodeLimits, DocumentStorageErrorCode][] = [
        [new DocumentDecodeLimits({ maximumEncodedBytes: 1, maximumPlanes: 1 }), "oversizedInput"],
        [new DocumentDecodeLimits({ maximumDecodedBytes: 1, maximumPlanes: 1 }), "oversizedOutput"],
        [new DocumentDecodeLimits({ maximumLines: 1, maximumPlanes: 1 }), "tooManyLines"],
      ];
      for (const [policy, expected] of policies) {
        try { DocumentFileComposition.resolve("root", [input], undefined, policy); throw new Error("Expected storage failure"); }
        catch (error) { expect(error).toBeInstanceOf(DocumentStorageError); expect((error as DocumentStorageError).code).toBe(expected); }
      }
    }
  });

  test("disconnected embedded ledgers use final entry depth rather than incoming file depth", () => {
    const embedded = new DocumentComposition("r", [
      { id: "r", document: document(), references: [] },
      { id: "u", document: host('{"1":"x"}'), references: [] },
    ]);
    const result = DocumentFileComposition.resolve("root", [
      source("root", host('{"1":"bundle","2":"bundle"}')),
      source("bundle", DocumentCompositionCodec.document(embedded)), source("x"),
    ], new DocumentCompositionLimits({ maximumDepth: 2 }));
    expect(result.composition.entries).toHaveLength(4);
    expect(result.resolvedPaths).toEqual(["bundle", "root", "x"]);
    expect(result.composition.rootEntry.references.map((value) => value.targetID)).toEqual(["file-000000", "file-000000"]);
    expect(result.composition.entry("file-000001")?.references[0]?.targetID).toBe("file-000003");
  });

  test("repeated cached dependencies validate final depth after complete discovery", () => {
    const sources = [source("root", host('{"1":"short","2":"long"}')),
      source("short", host('{"1":"leaf"}')), source("long", host('{"1":"short","2":"short"}')), source("leaf")];
    graphRejects("depthExceeded", () => DocumentFileComposition.resolve("root", sources, new DocumentCompositionLimits({ maximumDepth: 3 })));
    const valid = DocumentFileComposition.resolve("root", sources, new DocumentCompositionLimits({ maximumDepth: 4 }));
    expect(valid.composition.entries).toHaveLength(4);
    expect(valid.composition.entry("file-000001")?.references.map((value) => value.targetID)).toEqual(["file-000003", "file-000003"]);
    const missing = [...sources.slice(0, 2), source("long", host('{"1":"short","2":"missing"}')), sources[3]!];
    rejects("missingFile", () => DocumentFileComposition.resolve("root", missing, new DocumentCompositionLimits({ maximumDepth: 3 })));
  });

  test("independent fixed64 discovery safety bounds disconnected file chains", () => {
    const files = (count: number): DocumentFileSource[] => Array.from({ length: count }, (_, index) => {
      const ledger: Record<string, string> = index + 1 < count ? { "3md-files": `{"1":"f${index + 1}"}` } : {};
      const graph = new DocumentComposition("r", [
        { id: "r", document: document(), references: [] },
        { id: "u", document: document("Unused", ledger), references: [] },
      ]);
      return source(`f${index}`, DocumentCompositionCodec.document(graph));
    });
    expect(DocumentFileComposition.resolve("f0", files(64), new DocumentCompositionLimits({ maximumDepth: 2 })).composition.entries).toHaveLength(128);
    graphRejects("depthExceeded", () => DocumentFileComposition.resolve("f0", files(65), new DocumentCompositionLimits({ maximumDepth: 2 })));
  });

  test("lowered policies enforce final graph depth, imported entries, edges, conceptual traversal and final profile size", () => {
    const sources = [source("root", host('{"1":"short","2":"long"}')), source("short", host('{"1":"leaf"}')),
      source("long", host('{"1":"short"}')), source("leaf")];
    graphRejects("depthExceeded", () => DocumentFileComposition.resolve("root", sources, new DocumentCompositionLimits({ maximumDepth: 3 })));
    graphRejects("tooManyReferences", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"child"}')), source("child")], new DocumentCompositionLimits({ maximumReferences: 0 })));
    graphRejects("traversalOccurrencesExceeded", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"child","2":"child"}')), source("child")], new DocumentCompositionLimits({ maximumTraversalOccurrences: 2 })));
    const nested = new DocumentComposition("a", [{ id: "a", document: document(), references: [] }, { id: "b", document: document(), references: [] }]);
    graphRejects("tooManyDefinitions", () => DocumentFileComposition.resolve("root", [source("root", DocumentCompositionCodec.document(nested))], new DocumentCompositionLimits({ maximumDefinitions: 1 })));
    const only = source("r");
    graphRejects("profileBytesExceeded", () => DocumentFileComposition.resolve("r", [only], new DocumentCompositionLimits({ maximumProfileBytes: only.data.length + 10 })));
    expect(() => DocumentFileComposition.resolve("r", [only], undefined, { ...DocumentDecodeLimits.standard, maximumPlanes: Infinity })).toThrow(DocumentStorageError);
    graphRejects("invalidLimits", () => DocumentFileComposition.resolve("r", [only], { ...DocumentCompositionLimits.standard, maximumDepth: Infinity }));
  });

  test("pre-aborted and cooperatively aborted operations propagate the caller's cancellation reason", () => {
    const controller = new AbortController(); const reason = new Error("stop linked intake"); controller.abort(reason);
    expect(() => DocumentFileComposition.ledger(document(), controller.signal)).toThrow(reason);
    expect(() => DocumentFileComposition.resolvePath("root", undefined, controller.signal)).toThrow(reason);
    expect(() => DocumentFileComposition.resolve("root", [source("root")], undefined, undefined, controller.signal)).toThrow(reason);
    const ongoing = new AbortController(); const check = ongoing.signal.throwIfAborted.bind(ongoing.signal); let calls = 0;
    Object.defineProperty(ongoing.signal, "throwIfAborted", { value: () => { calls += 1; if (calls === 20) ongoing.abort(reason); check(); } });
    expect(() => DocumentFileComposition.resolve("root", [source("root"), source("a"), source("b")], undefined, undefined, ongoing.signal)).toThrow(reason);
    expect(calls).toBe(20);
  });
});

/** Aborts the first time `checkCancellation` is reached from a matching call site, then reports whether it fired. */
function abortAt(site: (caller: string, stack: string) => boolean) {
  const controller = new AbortController(); const reason = new Error("stop at call site"); let fired = false;
  const check = controller.signal.throwIfAborted.bind(controller.signal);
  Object.defineProperty(controller.signal, "throwIfAborted", { value: () => {
    const stack = new Error().stack ?? "";
    const frames = stack.split("\n").map((frame) => frame.trim());
    const index = frames.findIndex((frame) => frame.startsWith("at checkCancellation"));
    const caller = (frames[index + 1] ?? "").split(" (")[0] ?? "";
    if (!fired && index >= 0 && site(caller, stack)) { fired = true; controller.abort(reason); }
    check();
  } });
  return { signal: controller.signal, reason, fired: () => fired };
}
function ledgerJSON(fields: Record<string, string>): string { return JSON.stringify(fields); }
function glyphs(): string[] { return Array.from({ length: 94 }, (_, index) => String.fromCharCode(33 + index)); }

describe("linked composition parity hardening", () => {
  test("static resolve, ledger and resolvePath do not depend on their class binding", () => {
    const { resolve, ledger, resolvePath } = DocumentFileComposition;
    const result = resolve("root", [source("root", host('{"1":"child"}')), source("child")]);
    expect(result.resolvedPaths).toEqual(["child", "root"]);
    expect(ledger(host('{"1":"x"}'))).toEqual([{ glyph: "1", source: "x" }]);
    expect(resolvePath("x", "a/b")).toBe("a/x");
  });

  test("owner directories keep parent, dot and grammar semantics", () => {
    for (const [path, owner, expected] of [["../../x", "a/b/c/owner", "a/x"], ["x/..", "a/owner", "a"],
      ["../c", "a/́b/owner", "a/c"], ["./x/./y", "a/./b/owner", "a/b/x/y"], ["child", "owner", "child"],
      ["x/../../y", "a/b/owner", "a/y"]] as const) {
      expect(DocumentFileComposition.resolvePath(path, owner)).toBe(expected);
    }
    for (const [path, owner] of [["../..", "a/b/owner"], ["x/../..", "a/owner"], ["..", "owner"], ["../../..", "a/b/o"]]) {
      rejects("invalidPath", () => DocumentFileComposition.resolvePath(path!, owner));
    }
  });

  test("a long owner path with many references resolves every reference in its directory", () => {
    const ledger = ledgerJSON(Object.fromEntries(glyphs().map((glyph) => [glyph, "leaf.3md"])));
    const entries = [0, 1, 2].map((index) => ({ id: `e${index}`, document: host(ledger), references: [] }));
    const graph = new DocumentComposition("m", [...entries,
      { id: "m", document: document(), references: entries.map((entry) => ({ targetID: entry.id, attributes: {} })) }]);
    const owner = `owner/${"é".repeat(200_000)}.3md`;
    const result = DocumentFileComposition.resolve(owner, [source(owner, DocumentCompositionCodec.document(graph)),
      source("owner/leaf.3md")]);
    expect(result.resolvedPaths).toEqual(["owner/leaf.3md", owner]);
    const edges = result.composition.entries.flatMap((entry) => entry.references).filter((edge) => edge.attributes.glyph);
    expect(edges).toHaveLength(3 * 94);
    expect(edges.every((edge) => edge.attributes["source-file"] === "owner/leaf.3md")).toBe(true);
  });

  test("refusals follow entry ID, then glyph, discovery order", () => {
    rejects("missingFile", () => DocumentFileComposition.resolve("root", [source("root", host('{"a":"missing","b":"/x"}'))]));
    rejects("invalidPath", () => DocumentFileComposition.resolve("root", [source("root", host('{"a":"/x","b":"missing"}'))]));
    for (const [first, second, code] of [["missing", "/x", "missingFile"], ["/x", "missing", "invalidPath"]] as const) {
      const graph = new DocumentComposition("m", [{ id: "m", document: document(), references: [] },
        { id: "a", document: host(ledgerJSON({ z: first })), references: [] },
        { id: "b", document: host(ledgerJSON({ a: second })), references: [] }]);
      rejects(code, () => DocumentFileComposition.resolve("root", [source("root", DocumentCompositionCodec.document(graph))]));
    }
  });

  test("root and unreachable supplied paths use the ledger path grammar", () => {
    const leaf = source("root.3md");
    for (const path of ["/root.3md", ".", "../root.3md", "", "a\\b.3md", "a:b.3md", "a\u007fb.3md", "a\u0000b.3md"]) {
      rejects("invalidPath", () => DocumentFileComposition.resolve(path, [leaf]));
      rejects("invalidPath", () => DocumentFileComposition.resolve("root.3md", [leaf, { path, data: leaf.data }]));
    }
    expect(DocumentFileComposition.resolve("root", [source("root", host('{"1":"%2e%2e/leaf"}')), source("%2e%2e/leaf")])
      .resolvedPaths).toEqual(["%2e%2e/leaf", "root"]);
    expect(DocumentFileComposition.resolve("root", [source("root", host('{"1":"Leaf","2":"leaf"}')),
      source("Leaf", document("Upper")), source("leaf", document("Lower"))]).resolvedPaths).toEqual(["Leaf", "leaf", "root"]);
  });

  test("ledger escapes decode before path grammar", () => {
    const leaf = source("models/leaf");
    const slash = DocumentFileComposition.resolve("root", [source("root", host('{"1":"models\\/leaf","2":"models/leaf"}')), leaf]);
    expect(slash.resolvedPaths).toEqual(["models/leaf", "root"]);
    expect(new Set(slash.composition.rootEntry.references.map((edge) => edge.targetID)).size).toBe(1);
    rejects("invalidPath", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"models\\\\leaf"}')), leaf]));
    rejects("invalidPath", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"a\\u0001b"}'))]));
    expect(DocumentFileComposition.resolve("root", [source("root", host('{"1":"\\ud83d\\ude00"}')), source("😀")]).resolvedPaths)
      .toEqual(["root", "😀"]);
    rejects("invalidLedger", () => DocumentFileComposition.resolve("root", [source("root", host('{"\\ud800":"leaf"}'))]));
  });

  test("self and alias cycles compare normalized paths", () => {
    for (const ledger of ['{"1":"root.3md"}', '{"1":"./root.3md"}']) {
      graphRejects("cycle", () => DocumentFileComposition.resolve("root.3md", [source("root.3md", host(ledger))]));
    }
    for (const [child, link] of [["models/child.3md", "../root.3md"], ["child.3md", "models/../root.3md"]] as const) {
      graphRejects("cycle", () => DocumentFileComposition.resolve("root.3md", [source("root.3md", host(ledgerJSON({ 1: child }))),
        source(child, host(ledgerJSON({ 1: link })))]));
    }
  });

  test("a cached subtree is charged at its deeper occurrence against the discovery ceiling", () => {
    // `last` holds the final file's ledger fields.
    const chain = (prefix: string, count: number, last?: Record<string, string>): DocumentFileSource[] =>
      Array.from({ length: count }, (_, offset) => {
        const index = offset + 1; const fields = index < count ? { 1: `${prefix}${index + 1}` } : last;
        const graph = new DocumentComposition("r", [{ id: "r", document: document(), references: [] },
          { id: "u", document: document("Unused", fields === undefined ? {} : { "3md-files": ledgerJSON(fields) }), references: [] }]);
        return source(`${prefix}${index}`, DocumentCompositionCodec.document(graph));
      });
    const root = source("root", host('{"1":"a1","2":"b1"}')); const long = chain("a", 40);
    graphRejects("depthExceeded", () => DocumentFileComposition.resolve("root", [root, ...long, ...chain("b", 24, { 1: "a1" })]));
    // Only the cache-hit height check can refuse before b24's second glyph names a missing file.
    graphRejects("depthExceeded", () => DocumentFileComposition.resolve("root",
      [root, ...long, ...chain("b", 24, { 1: "a1", 2: "missing" })]));
    expect(DocumentFileComposition.resolve("root", [root, ...long, ...chain("b", 23, { 1: "a1" })]).composition.entries).toHaveLength(127);
  });

  test("existing edges precede ledger edges; embedded ledgers resolve from their bundle folder; output rebundles", () => {
    const group = new DocumentComposition("m", [
      { id: "m", document: host('{"2":"leaf"}'), references: [{ targetID: "c", attributes: { glyph: "1", opaque: "keep" } }] },
      { id: "c", document: document("Kept"), references: [] }]);
    const result = DocumentFileComposition.resolve("root", [source("root", host('{"1":"models/group"}')),
      source("models/group", DocumentCompositionCodec.document(group)), source("models/leaf", document("Leaf"))]);
    expect(result.composition.entry(result.fileRootIDs["models/group"]!)?.references).toEqual([
      { targetID: "file-000000", attributes: { glyph: "1", opaque: "keep" } },
      { targetID: result.fileRootIDs["models/leaf"]!, attributes: { glyph: "2", "source-file": "models/leaf" } },
    ]);
    const second = DocumentFileComposition.resolve("root.3md", [source("root.3md", host('{"1":"archive/bundle.3md"}')),
      source("archive/bundle.3md", DocumentCompositionCodec.document(result.composition))]);
    expect(second.resolvedPaths).toEqual(["archive/bundle.3md", "root.3md"]);
    expect(second.composition.entries).toHaveLength(5);
    const archived = second.composition.entry(second.fileRootIDs["archive/bundle.3md"]!);
    expect(archived?.references[0]?.attributes).toEqual({ glyph: "1", "source-file": "models/group" });
  });

  test("the source-file attribute bound counts normalized UTF-8 bytes", () => {
    const attempt = (padding: number, limits?: DocumentCompositionLimits) => {
      const path = `models/${"é".repeat(8_000)}${"a".repeat(padding)}`;
      return DocumentFileComposition.resolve("root", [source("root", host(ledgerJSON({ 1: path }))), source(path)], limits);
    };
    const exact = attempt(360);
    expect(new TextEncoder().encode(exact.composition.rootEntry.references[0]!.attributes["source-file"]).length).toBe(16_367);
    graphRejects("referenceAttributesExceeded", () => attempt(361));
    graphRejects("referenceAttributesExceeded", () => attempt(360, new DocumentCompositionLimits({ maximumReferenceAttributeBytes: 16_383 })));
    graphRejects("referenceAttributesExceeded", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"leaf"}')),
      source("leaf")], new DocumentCompositionLimits({ maximumReferenceAttributes: 1 })));
  });

  test("lowered policies charge original path bytes before path grammar; invalid limits are refused first", () => {
    const root = source("/root");
    rejects("inputLimit", () => DocumentFileComposition.resolve("/root", [root], new DocumentCompositionLimits({ maximumProfileBytes: 9 })));
    rejects("invalidPath", () => DocumentFileComposition.resolve("/root", [root], new DocumentCompositionLimits({ maximumProfileBytes: 10 })));
    graphRejects("invalidLimits", () => DocumentFileComposition.resolve("/root", [root], { ...DocumentCompositionLimits.standard, maximumDepth: 0 }));
    expect(() => DocumentFileComposition.resolve("/root", [root], undefined, { ...DocumentDecodeLimits.standard, maximumLines: 0 }))
      .toThrow(DocumentStorageError);
  });

  test("an abort inside the ledger scanner propagates the caller's reason", () => {
    const abort = abortAt((caller, stack) => (caller === "at string" || caller === "at whitespace") && stack.includes("at ledger"));
    const ledger = `{"1":"${"a".repeat(10_000)}"}`;
    expect(() => DocumentFileComposition.resolve("root", [source("root", host(ledger))], undefined, undefined, abort.signal))
      .toThrow(abort.reason);
    expect(abort.fired()).toBe(true);
  });

  test("an abort inside the scalar path sort propagates the caller's reason", () => {
    const abort = abortAt((caller) => caller === "at scalarCompare");
    expect(() => DocumentFileComposition.resolve("root", [source("root", host('{"1":"b","2":"a"}')), source("a"), source("b")],
      undefined, undefined, abort.signal)).toThrow(abort.reason);
    expect(abort.fired()).toBe(true);
  });
});

describe("early source-file attribute bound and long-directory owners", () => {
  test("an over-bound ledger edge is refused while resolving, before later refusals", () => {
    // A 40-byte policy leaves 23 bytes for a target after "glyph", the glyph and "source-file".
    const tight = new DocumentCompositionLimits({ maximumReferenceAttributeBytes: 40 });
    const long = `${"x".repeat(30)}.3md`; const target = source(long);
    const attempt = (root: string, sources: DocumentFileSource[]) => DocumentFileComposition.resolve(root, sources, tight);
    graphRejects("referenceAttributesExceeded", () => attempt("root", [source("root", host(ledgerJSON({ a: long, b: "missing" }))), target]));
    rejects("missingFile", () => attempt("root", [source("root", host(ledgerJSON({ a: "missing", b: long }))), target]));
    graphRejects("referenceAttributesExceeded", () => attempt("root", [source("root", host(ledgerJSON({ 1: long })))]));
    graphRejects("referenceAttributesExceeded", () => attempt(long, [source(long, host(ledgerJSON({ 1: `./${long}` })))]));
    rejects("invalidPath", () => attempt("root", [source("root", host(ledgerJSON({ 1: `${long}/` })))]));
  });

  test("the attribute bound counts normalized directory prefix bytes", () => {
    // Twelve decomposed é become 24 NFC bytes, so "é…/leaf" is 29 bytes and needs a 46-byte policy.
    const directory = "é".repeat(12);
    const sources = [source(`${directory}/root`, host('{"1":"leaf","2":"../top"}')), source(`${directory}/leaf`), source("top")];
    const result = DocumentFileComposition.resolve(`${directory}/root`, sources,
      new DocumentCompositionLimits({ maximumReferenceAttributeBytes: 46 }));
    expect(new TextEncoder().encode(result.composition.rootEntry.references[0]!.attributes["source-file"]).length).toBe(29);
    graphRejects("referenceAttributesExceeded", () => DocumentFileComposition.resolve(`${directory}/root`, sources,
      new DocumentCompositionLimits({ maximumReferenceAttributeBytes: 45 })));
  });

  test("long-directory owners resolve repeated sources once and refuse over-bound targets at the first edge", () => {
    const ledger = ledgerJSON(Object.fromEntries(glyphs().map((glyph) => [glyph, "leaf.3md"])));
    const owner = (directory: string, count: number): DocumentFileSource[] => {
      const entries = Array.from({ length: count }, (_, index) => ({ id: `e${index}`, document: host(ledger), references: [] }));
      const graph = new DocumentComposition("m", [...entries,
        { id: "m", document: document(), references: entries.map((entry) => ({ targetID: entry.id, attributes: {} })) }]);
      return [source(`${directory}/root`, DocumentCompositionCodec.document(graph)), source(`${directory}/leaf.3md`)];
    };
    const inBound = "d".repeat(8_000);
    const result = DocumentFileComposition.resolve(`${inBound}/root`, owner(inBound, 3));
    const edges = result.composition.entries.flatMap((entry) => entry.references).filter((edge) => edge.attributes.glyph);
    expect(edges).toHaveLength(3 * 94);
    expect(edges.every((edge) => edge.attributes["source-file"] === `${inBound}/leaf.3md`)).toBe(true);
    const overBound = "d".repeat(262_144);
    graphRejects("referenceAttributesExceeded", () => DocumentFileComposition.resolve(`${overBound}/root`, owner(overBound, 170)));
  });
});
