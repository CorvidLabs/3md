import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  CompositionEditor, DocumentComposition, DocumentCompositionCodec, DocumentCompositionSnapshot,
  DocumentEditError, DocumentEditor, DocumentIdentity, DocumentRevision, DocumentSnapshot,
  DocumentStorageCodec, DocumentStorageFormat,
  type CompositionEdit, type Document, type DocumentDiagnosticCode, type DocumentEdit, type DocumentEntry, type Plane,
} from "../src/index.ts";
import { canonicalNumber } from "../src/storage.ts";

const fixtures = new URL("../../conformance/extensions/", import.meta.url);
function bytes(name: string): Uint8Array { return readFileSync(fileURLToPath(new URL(name, fixtures))); }
function json<Value>(name: string): Value { return JSON.parse(new TextDecoder().decode(bytes(name))) as Value; }
function plane(value: Plane): Plane {
  return { z: value.z, label: value.label ?? null, x: value.x ?? null, y: value.y ?? null,
    attributes: value.attributes, body: value.body };
}
function document(value: Document): Document {
  return { version: value.version, axis: value.axis, title: value.title ?? null, preamble: value.preamble ?? null,
    metadata: value.metadata, planes: value.planes.map(plane) };
}
type RawComposition = { readonly rootID: string; readonly entries: readonly DocumentEntry[] };
function composition(value: RawComposition): DocumentComposition {
  return new DocumentComposition(value.rootID, value.entries.map((entry) => ({ ...entry, document: document(entry.document) })));
}
function documentOperations(operations: readonly DocumentEdit[]): DocumentEdit[] {
  return operations.map((operation) => operation.kind === "replace" || operation.kind === "insert" ?
    { ...operation, plane: plane(operation.plane) } : operation);
}

describe("Swift portable extension conformance", () => {
  test("all IEEE754 number vectors match Swift canonical formatting", () => {
    const vectors = json<{ schema: string; vectors: { name: string; bitPattern: string; formatted: string }[] }>("numeric-vectors.json");
    expect(vectors.schema).toBe("3md-canonical-numbers-1");
    for (const vector of vectors.vectors) {
      const view = new DataView(new ArrayBuffer(8));
      view.setBigUint64(0, BigInt(`0x${vector.bitPattern}`), false);
      const value = view.getFloat64(0, false);
      expect(canonicalNumber(value), vector.name).toBe(vector.formatted);
      const source = new TextDecoder().decode(DocumentStorageCodec.encode({ version: "1.0", axis: "layer", title: null,
        metadata: {}, preamble: null, planes: [{ z: value, label: null, x: null, y: null, attributes: {}, body: "Number" }] }));
      expect(source).toContain(`@plane z=${vector.formatted}\n`);
    }
  });
  test("Swift scientific notation starts strictly above the exact 2^53 boundary", () => {
    expect(canonicalNumber(9007199254740991)).toBe("9007199254740991.0");
    expect(canonicalNumber(9007199254740992)).toBe("9007199254740992.0");
    expect(canonicalNumber(9007199254740994)).toBe("9.007199254740994e+15");
    expect(canonicalNumber(-9007199254740994)).toBe("-9.007199254740994e+15");
    expect(canonicalNumber(9810561196134064)).toBe("9.810561196134064e+15");
  });

  test("canonical Unicode document text, envelope and revision are byte-identical to Swift", () => {
    const expected = document(json<Document>("document-unicode.json"));
    expect(DocumentStorageCodec.decode(bytes("document-unicode.3md"))).toEqual(expected);
    expect(DocumentStorageCodec.decode(bytes("document-unicode.3mdb"))).toEqual(expected);
    expect(DocumentStorageCodec.encode(expected)).toEqual(bytes("document-unicode.3md"));
    expect(DocumentStorageCodec.encode(expected, DocumentStorageFormat.binary())).toEqual(bytes("document-unicode.3mdb"));
    expect(new DocumentSnapshot(expected).revision.canonicalContent).toBe(new TextDecoder().decode(bytes("document-unicode.3md")));
  });

  test("canonical composition preserves shared definitions, instance IDs and exact profile bytes", () => {
    const expected = composition(json<RawComposition>("composition-instances.json"));
    const decoded = DocumentCompositionCodec.decode(bytes("composition-instances.3mdb"));
    expect(decoded).toEqual(expected);
    expect(DocumentCompositionCodec.encode(expected)).toEqual(bytes("composition-instances.3md"));
    expect(DocumentStorageCodec.encode(DocumentCompositionCodec.document(expected), DocumentStorageFormat.binary()))
      .toEqual(bytes("composition-instances.3mdb"));
    expect(new DocumentCompositionSnapshot(decoded).revision.canonicalContent)
      .toBe(new TextDecoder().decode(bytes("composition-instances.3md")));
    expect(expected.rootEntry.references.map((reference) => reference.targetID)).toEqual(["leaf", "leaf", "other"]);
    expect(expected.entry("other")?.references[0]?.attributes["3md-id"]).toBe("left");
  });

  test("additive Swift Unicode key ordering and source-collision goldens match the portable codecs", () => {
    const manifest = json<{ unicodeFixtures: { documentSourceFile: string; documentBinaryFile: string;
      documentExpectedFile: string; sourceCollisionFile: string; sourceCollisionExpectedFile: string;
      compositionDuplicateFile: string; compositionDuplicateError: string } }>("manifest.json").unicodeFixtures;
    const expected = document(json<Document>(manifest.documentExpectedFile));
    expect(DocumentStorageCodec.decode(bytes(manifest.documentSourceFile))).toEqual(expected);
    expect(DocumentStorageCodec.encode(expected)).toEqual(bytes(manifest.documentSourceFile));
    expect(DocumentStorageCodec.encode(expected, DocumentStorageFormat.binary())).toEqual(bytes(manifest.documentBinaryFile));
    expect(DocumentStorageCodec.decode(bytes(manifest.documentBinaryFile))).toEqual(expected);
    expect(DocumentStorageCodec.decode(bytes(manifest.sourceCollisionFile)))
      .toEqual(document(json<Document>(manifest.sourceCollisionExpectedFile)));
    try { DocumentCompositionCodec.decode(bytes(manifest.compositionDuplicateFile)); throw new Error("Expected invalid profile"); }
    catch (error) { expect((error as { code: string }).code).toBe(manifest.compositionDuplicateError); }
  });

  const edits = json<{
    schema: string;
    documentFixture: string;
    compositionFixture: string;
    documentAdoption: { input: Document; expected: Document };
    compositionAdoption: { input: RawComposition; expected: RawComposition };
    documentTransactions: { name: string; operations: DocumentEdit[]; expected: Document }[];
    compositionTransactions: { name: string; operations: CompositionEdit[]; expected: RawComposition }[];
    failures: { name: string; scope: string; operations: DocumentEdit[] | CompositionEdit[];
      expectedCode: DocumentDiagnosticCode; expectedPath: string; expectedRevisionSuffix?: string }[];
  }>("editing-vectors.json");
  const docSnapshot = new DocumentSnapshot(DocumentStorageCodec.decode(bytes(`${edits.documentFixture}.3md`)));
  const graphSnapshot = new DocumentCompositionSnapshot(DocumentCompositionCodec.decode(bytes(`${edits.compositionFixture}.3md`)));

  test("identity adoption follows the Swift fixture and preserves ordinary id metadata", () => {
    expect(edits.schema).toBe("3md-editing-semantic-fixtures-1");
    expect(DocumentIdentity.adopt(document(edits.documentAdoption.input))).toEqual(document(edits.documentAdoption.expected));
    expect(DocumentIdentity.adopt(composition(edits.compositionAdoption.input))).toEqual(composition(edits.compositionAdoption.expected));
  });
  for (const transaction of edits.documentTransactions) {
    test(`document transaction: ${transaction.name}`, () => {
      const result = DocumentEditor.apply({ expectedRevision: docSnapshot.revision,
        operations: documentOperations(transaction.operations) }, docSnapshot);
      expect(result.document).toEqual(document(transaction.expected));
      expect(DocumentStorageCodec.decode(DocumentStorageCodec.encode(result.document, DocumentStorageFormat.binary()))).toEqual(result.document);
      expect(DocumentSnapshot.fromJSON(JSON.parse(JSON.stringify(result)) as DocumentSnapshot)).toEqual(result);
    });
  }
  for (const transaction of edits.compositionTransactions) {
    test(`composition transaction: ${transaction.name}`, () => {
      const result = CompositionEditor.apply({ expectedRevision: graphSnapshot.revision, operations: transaction.operations }, graphSnapshot);
      expect(result.composition).toEqual(composition(transaction.expected));
      expect(DocumentCompositionSnapshot.fromJSON(JSON.parse(JSON.stringify(result)) as DocumentCompositionSnapshot)).toEqual(result);
    });
  }
  for (const invalid of edits.failures) {
    test(`atomic failure: ${invalid.name}`, () => {
      let error: unknown;
      try {
        if (invalid.scope === "document") DocumentEditor.apply({
          expectedRevision: new DocumentRevision(docSnapshot.revision.canonicalContent + (invalid.expectedRevisionSuffix ?? "")),
          operations: documentOperations(invalid.operations as DocumentEdit[]),
        }, docSnapshot);
        else CompositionEditor.apply({
          expectedRevision: new DocumentRevision(graphSnapshot.revision.canonicalContent + (invalid.expectedRevisionSuffix ?? "")),
          operations: invalid.operations as CompositionEdit[],
        }, graphSnapshot);
      } catch (caught) { error = caught; }
      expect(error).toBeInstanceOf(DocumentEditError);
      expect((error as DocumentEditError).diagnostic.code).toBe(invalid.expectedCode);
      expect((error as DocumentEditError).diagnostic.path).toBe(invalid.expectedPath);
      expect((error as DocumentEditError).diagnostic.sourceLine).toBeNull();
      expect(docSnapshot.revision.canonicalContent).toBe(new TextDecoder().decode(bytes(`${edits.documentFixture}.3md`)));
      expect(graphSnapshot.revision.canonicalContent).toBe(new TextDecoder().decode(bytes(`${edits.compositionFixture}.3md`)));
    });
  }
});
