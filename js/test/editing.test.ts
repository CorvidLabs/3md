import { describe, expect, test } from "bun:test";
import {
  CompositionEditor, DocumentComposition, DocumentCompositionLimits, DocumentCompositionSnapshot,
  DocumentDecodeLimits, DocumentDiagnostics, DocumentEditError, DocumentEditLimits, DocumentEditor,
  DocumentIdentity, DocumentRevision, DocumentSnapshot, DocumentStorageCodec, parse, stableID,
  type CompositionEdit, type Document, type DocumentDiagnosticCode, type DocumentEdit, type DocumentEntry, type Plane,
} from "../src/index.ts";

const plain = (body = "Body"): Document => parse(`---\n3md: 1\n---\n@plane z=0\n${body}\n`);
function plane(id: string, z = 0, body = "Body"): Plane {
  return { z, x: null, y: null, label: null, attributes: { "3md-id": id, id: "opaque" }, body };
}
function snapshot(): DocumentSnapshot { return new DocumentSnapshot({ ...plain(), planes: [plane("first"), plane("second", 1)] }); }
function entry(id: string, targets: readonly string[] = []): DocumentEntry {
  return { id, document: plain(id), references: targets.map((targetID, index) => ({ targetID, attributes: { "3md-id": `reference-${index + 1}` } })) };
}
function graph(): DocumentCompositionSnapshot {
  return new DocumentCompositionSnapshot(new DocumentComposition("root", [entry("root", ["leaf", "leaf"]), entry("leaf"), entry("other")]));
}
function rejects(code: DocumentDiagnosticCode, operation: () => unknown, path?: string): void {
  let caught: unknown;
  try { operation(); } catch (error) { caught = error; }
  expect(caught).toBeInstanceOf(DocumentEditError);
  const diagnostic = (caught as DocumentEditError).diagnostic;
  expect(diagnostic.code).toBe(code);
  if (path !== undefined) expect(diagnostic.path).toBe(path);
  expect(diagnostic.sourceLine).toBeNull();
}

describe("portable atomic editing and diagnostics", () => {
  test("adoption skips existing IDs, preserves id metadata and rejects unsafe or duplicated identities", () => {
    const document = { ...plain(), planes: [{ ...plane("x"), attributes: { id: "legacy" } }, plane("plane-1", 1)] };
    const adopted = DocumentIdentity.adopt(document);
    expect(adopted.planes.map(stableID)).toEqual(["plane-2", "plane-1"]);
    expect(adopted.planes[0]?.attributes["id"]).toBe("legacy");
    expect(DocumentIdentity.adopt(adopted)).toEqual(adopted);
    rejects("invalidIdentity", () => DocumentIdentity.adopt({ ...plain(), planes: [plane("../bad")] }), "planes[0].attributes[3md-id]");
    rejects("duplicateIdentity", () => DocumentIdentity.adopt({ ...plain(), planes: [plane("same"), plane("same", 1)] }), "planes[1].attributes[3md-id]");
  });
  test("snapshots deep-copy and freeze values; reconstruction rejects a forged revision", () => {
    const document = { ...plain(), metadata: { author: "first" }, planes: [plane("first")] };
    const value = new DocumentSnapshot(document);
    document.metadata.author = "changed";
    document.planes.push(plane("next", 1));
    expect(value.document.metadata["author"]).toBe("first"); expect(value.document.planes.length).toBe(1);
    expect(Object.isFrozen(value.document.planes[0]?.attributes)).toBe(true);
    rejects("staleRevision", () => DocumentSnapshot.fromJSON({ document: value.document, revision: { canonicalContent: "forged" } }), "revision");
    const graphValue = graph();
    rejects("staleRevision", () => DocumentCompositionSnapshot.fromJSON({ composition: graphValue.composition,
      revision: { canonicalContent: "forged" } }), "revision");
  });
  test("insert, move, remove and header replacements are one pure transaction", () => {
    const value = snapshot();
    const result = DocumentEditor.apply({ expectedRevision: value.revision, operations: [
      { kind: "insert", plane: plane("third", 2), at: 0 }, { kind: "move", id: "first", to: 2 },
      { kind: "remove", id: "second" }, { kind: "replaceHeader", header: { ...value.document, title: "Changed", metadata: { author: "kept" } } },
    ] }, value);
    expect(result.document.planes.map(stableID)).toEqual(["third", "first"]);
    expect(result.document.title).toBe("Changed"); expect(result.document.metadata["author"]).toBe("kept");
    expect(value.document.planes.map(stableID)).toEqual(["first", "second"]);
  });
  test("later invalid operation rolls back; replacement identities, indices and missing targets are precise", () => {
    const value = snapshot();
    const invalid: [DocumentEdit, DocumentDiagnosticCode][] = [
      [{ kind: "insert", plane: plane("first", 2), at: 0 }, "duplicateIdentity"],
      [{ kind: "insert", plane: { ...plane("new", 2), attributes: {} }, at: 0 }, "missingIdentity"],
      [{ kind: "insert", plane: plane("new", 2), at: -1 }, "invalidIndex"],
      [{ kind: "move", id: "first", to: 2 }, "invalidIndex"],
      [{ kind: "move", id: "first", to: 0.5 }, "invalidIndex"],
      [{ kind: "remove", id: "absent" }, "missingTarget"],
      [{ kind: "replace", id: "first", plane: plane("changed") }, "identityChanged"],
    ];
    for (const [operation, code] of invalid) rejects(code, () => DocumentEditor.apply({ expectedRevision: value.revision,
      operations: [{ kind: "replace", id: "first", plane: plane("first", 0, "Changed") }, operation] }, value), "operations[1]");
    expect(value.document.planes[0]?.body).toBe("Body");
  });
  test("exact revisions reject NFC-equivalent bytes and expected-content budgets", () => {
    const value = new DocumentSnapshot({ ...plain(), title: "café", planes: [plane("first")] });
    const decomposed = value.revision.canonicalContent.replace("café", "cafe\u0301");
    expect(new DocumentRevision(decomposed).equals(value.revision)).toBe(false);
    rejects("staleRevision", () => DocumentEditor.apply({ expectedRevision: new DocumentRevision(decomposed), operations: [] }, value), "expectedRevision");
    rejects("payloadLimit", () => DocumentEditor.apply({ expectedRevision: new DocumentRevision("x".repeat(100)), operations: [] }, value,
      undefined, new DocumentDecodeLimits({ maximumDecodedBytes: 99 })), "expectedRevision");
  });
  test("structurally typed snapshot revisions cannot replace the exact-content comparison", () => {
    const value = snapshot();
    const forged = { document: value.document, revision: { canonicalContent: value.revision.canonicalContent, equals: () => true } };
    rejects("staleRevision", () => DocumentEditor.apply({ expectedRevision: new DocumentRevision("stale"), operations: [] }, forged), "expectedRevision");
    const graphValue = graph();
    const forgedGraph = { composition: graphValue.composition,
      revision: { canonicalContent: graphValue.revision.canonicalContent, equals: () => true } };
    rejects("staleRevision", () => CompositionEditor.apply({ expectedRevision: new DocumentRevision("stale"), operations: [] }, forgedGraph), "expectedRevision");
  });
  test("operation, payload and final invalid-document policies return no partial result", () => {
    const value = snapshot();
    rejects("operationLimit", () => DocumentEditor.apply({ expectedRevision: value.revision, operations: [{ kind: "remove", id: "first" }] }, value,
      new DocumentEditLimits({ maximumOperations: 0 })), "operations");
    rejects("payloadLimit", () => DocumentEditor.apply({ expectedRevision: value.revision,
      operations: [{ kind: "replace", id: "first", plane: plane("first", 0, "雪".repeat(30)) }] }, value, new DocumentEditLimits({ maximumPayloadBytes: 64 })));
    rejects("invalidDocument", () => DocumentEditor.apply({ expectedRevision: value.revision,
      operations: [{ kind: "replace", id: "first", plane: { ...plane("first"), x: NaN } }] }, value));
    expect(DocumentEditor.apply({ expectedRevision: value.revision, operations: [] }, value, new DocumentEditLimits({ maximumOperations: 0 }))).toEqual(value);
  });
  test("two NaN coordinate replacements reach invalid-document validation without a false duplicate", () => {
    const value = snapshot();
    rejects("invalidDocument", () => DocumentEditor.apply({ expectedRevision: value.revision, operations: [
      { kind: "replace", id: "first", plane: plane("first", NaN) },
      { kind: "replace", id: "second", plane: plane("second", NaN) },
    ] }, value));
    expect(value.document.planes.map((plane) => plane.z)).toEqual([0, 1]);
  });
  test("graph patches allow forward definitions and final root swaps without flattening", () => {
    const value = graph();
    const result = CompositionEditor.apply({ expectedRevision: value.revision, operations: [
      { kind: "insertReference", ownerID: "root", reference: { targetID: "future", attributes: { "3md-id": "future-instance" } }, at: 0 },
      { kind: "insertEntry", entry: entry("future", ["other"]) }, { kind: "selectRoot", id: "future" },
    ] }, value);
    expect(result.composition.rootID).toBe("future"); expect(result.composition.entry("root")?.references[0]?.targetID).toBe("future");
    const repaired = CompositionEditor.apply({ expectedRevision: value.revision, operations: [
      { kind: "removeEntry", id: "leaf" }, { kind: "removeReference", ownerID: "root", id: "reference-2" },
      { kind: "replaceReference", ownerID: "root", id: "reference-1", reference: { targetID: "other", attributes: { "3md-id": "reference-1" } } },
    ] }, value);
    expect(repaired.composition.entry("leaf")).toBeUndefined(); expect(value.composition.entry("leaf")).toBeDefined();
  });
  test("graph final failures identify the missing target or root and enforce scoped IDs", () => {
    const value = graph();
    rejects("invalidComposition", () => CompositionEditor.apply({ expectedRevision: value.revision,
      operations: [{ kind: "removeEntry", id: "leaf" }] }, value), "entries[1].references[0].targetID");
    rejects("invalidComposition", () => CompositionEditor.apply({ expectedRevision: value.revision,
      operations: [{ kind: "selectRoot", id: "missing" }] }, value), "rootID");
    const invalid: [CompositionEdit, DocumentDiagnosticCode][] = [
      [{ kind: "replaceEntry", id: "leaf", entry: entry("new") }, "identityChanged"],
      [{ kind: "insertEntry", entry: entry("leaf") }, "duplicateIdentity"],
      [{ kind: "removeReference", ownerID: "other", id: "reference-1" }, "missingTarget"],
      [{ kind: "replaceReference", ownerID: "root", id: "reference-1", reference: { targetID: "other", attributes: { "3md-id": "changed" } } }, "identityChanged"],
      [{ kind: "insertReference", ownerID: "root", at: 0, reference: { targetID: "other", attributes: { "3md-id": "reference-1" } } }, "duplicateIdentity"],
    ];
    for (const [operation, code] of invalid) rejects(code, () => CompositionEditor.apply({ expectedRevision: value.revision, operations: [operation] }, value), "operations[0]");
  });
  test("source diagnostics carry only actual parser lines; value paths and truncation stay precise", () => {
    const parsed = DocumentDiagnostics.inspect('---\n3md: 1\n---\n\n@plane label="Missing"\nBody\n');
    expect(parsed.diagnostics[0]?.code).toBe("parseFailure"); expect(parsed.diagnostics[0]?.sourceLine).toBe(5);
    const value = { ...plain(), planes: [plane("same"), plane("same", 1), plane("../bad", 1)] };
    const issues = DocumentDiagnostics.inspect(value);
    expect(issues.diagnostics.map((issue) => issue.code)).toEqual(["duplicateIdentity", "invalidIdentity", "duplicatePosition"]);
    expect(issues.diagnostics.map((issue) => issue.path)).toEqual(["planes[1].attributes[3md-id]", "planes[2].attributes[3md-id]", "planes[2].z"]);
    expect(issues.diagnostics.every((issue) => issue.sourceLine === null)).toBe(true);
    const bounded = DocumentDiagnostics.inspect(value, new DocumentEditLimits({ maximumDiagnostics: 1 }));
    expect(bounded.isTruncated).toBe(true); expect(bounded.diagnostics.length).toBe(1);
  });
  test("diagnostic payload preflight precedes expensive graph validation and retains owner paths", () => {
    const composition = new DocumentComposition("root", [entry("leaf"), { ...entry("root", ["leaf", "leaf"]),
      references: [{ targetID: "leaf", attributes: { "3md-id": "same" } }, { targetID: "leaf", attributes: { "3md-id": "same" } }] }]);
    expect(DocumentDiagnostics.inspect(composition).diagnostics[0]?.path).toBe("entries[1].references[1].attributes[3md-id]");
    rejects("payloadLimit", () => DocumentDiagnostics.inspect(composition, new DocumentEditLimits({ maximumDiagnosticBytes: 8 }),
      new DocumentCompositionLimits({ maximumDefinitionBytes: 8 })));
    rejects("payloadLimit", () => DocumentDiagnostics.inspect("x".repeat(9), new DocumentEditLimits({ maximumDiagnosticBytes: 8 })), "source");
    expect(DocumentDiagnostics.inspect(plain("[[z=".repeat(30_000))).diagnostics).toEqual([]);
    expect(DocumentStorageCodec.decode(DocumentStorageCodec.encode(plain()))).toEqual(plain());
  });
  test("all identity, transaction and diagnostic entry points honor pre-aborted signals", () => {
    const value = snapshot(); const graphValue = graph();
    const abort = new AbortController(); const reason = new Error("cancelled"); abort.abort(reason);
    const operations = [
      () => DocumentIdentity.adopt(value.document, undefined, abort.signal),
      () => DocumentIdentity.adopt(graphValue.composition, undefined, undefined, abort.signal),
      () => DocumentEditor.apply({ expectedRevision: value.revision, operations: [] }, value, undefined, undefined, abort.signal),
      () => CompositionEditor.apply({ expectedRevision: graphValue.revision, operations: [] }, graphValue, undefined, undefined, undefined, abort.signal),
      () => DocumentDiagnostics.inspect("bad", undefined, undefined, abort.signal),
      () => DocumentDiagnostics.inspect(graphValue.composition, undefined, undefined, undefined, abort.signal),
    ];
    for (const operation of operations) expect(operation).toThrow(reason);
  });
  test("public editor and diagnostic boundaries reject forged plain-object policies", () => {
    const value = snapshot(); const graphValue = graph();
    const invalid = { ...DocumentEditLimits.standard, maximumOperations: Infinity, maximumPayloadBytes: Infinity,
      maximumDiagnostics: Infinity, maximumDiagnosticBytes: Infinity };
    rejects("invalidLimits", () => DocumentEditor.apply({ expectedRevision: value.revision, operations: [] }, value, invalid));
    rejects("invalidLimits", () => CompositionEditor.apply({ expectedRevision: graphValue.revision, operations: [] }, graphValue, invalid));
    rejects("invalidLimits", () => DocumentDiagnostics.inspect("bad", invalid));
    rejects("invalidLimits", () => DocumentDiagnostics.inspect(value.document, invalid));
    rejects("invalidLimits", () => DocumentDiagnostics.inspect(graphValue.composition, invalid));
  });
});
