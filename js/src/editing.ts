import { ParseError, type Document, type Plane } from "./index.js";
import { DocumentComposition, DocumentCompositionCodec, DocumentCompositionError, DocumentCompositionLimits,
  type DocumentEntry, type DocumentReference } from "./composition.js";
import { boundedInteger, checkCancellation, frozenDocument, InvalidUnicodeError, utf8Length, validID } from "./portable.js";
import { canonicalNumber, DocumentDecodeLimits, DocumentStorageCodec, DocumentStorageError, DocumentStorageFormat } from "./storage.js";

export type DocumentDiagnosticCode = "invalidIdentity" | "duplicateIdentity" | "missingIdentity" | "missingTarget" |
  "identityChanged" | "staleRevision" | "invalidIndex" | "duplicatePosition" | "invalidDocument" |
  "invalidComposition" | "operationLimit" | "payloadLimit" | "invalidLimits" | "parseFailure";
export interface DocumentDiagnostic {
  readonly code: DocumentDiagnosticCode;
  readonly message: string;
  readonly severity: "error" | "warning";
  readonly sourceLine: number | null;
  readonly path: string | null;
}
export interface DocumentDiagnosticReport {
  readonly diagnostics: readonly DocumentDiagnostic[];
  readonly isTruncated: boolean;
}
export class DocumentEditError extends Error {
  public readonly diagnostic: DocumentDiagnostic;
  public constructor(diagnostic: DocumentDiagnostic) {
    super(diagnostic.message); this.name = "DocumentEditError";
    this.diagnostic = Object.freeze({ ...diagnostic });
  }
}
function diagnostic(code: DocumentDiagnosticCode, message: string, path: string | null = null,
  sourceLine: number | null = null): DocumentDiagnostic {
  return Object.freeze({ code, message, path, sourceLine, severity: "error" });
}
function failure(code: DocumentDiagnosticCode, message: string, path: string | null = null): DocumentEditError {
  return new DocumentEditError(diagnostic(code, message, path));
}
function message(error: unknown): string { return error instanceof Error ? error.message : String(error); }
function report(diagnostics: readonly DocumentDiagnostic[], isTruncated = false): DocumentDiagnosticReport {
  return Object.freeze({ diagnostics: Object.freeze([...diagnostics]), isTruncated });
}

/** A complete canonical expected value. No hash, normalization or authenticity assertion. */
export class DocumentRevision {
  public readonly canonicalContent: string;
  public constructor(canonicalContent: string) { this.canonicalContent = canonicalContent; Object.freeze(this); }
  public equals(other: Pick<DocumentRevision, "canonicalContent">): boolean { return this.canonicalContent === other.canonicalContent; }
}
export class DocumentEditLimits {
  public readonly maximumOperations: number;
  public readonly maximumPayloadBytes: number;
  public readonly maximumDiagnostics: number;
  public readonly maximumDiagnosticBytes: number;
  public static readonly standard = /* @__PURE__ */ new DocumentEditLimits();
  public constructor(options: Partial<Pick<DocumentEditLimits, "maximumOperations" | "maximumPayloadBytes" |
    "maximumDiagnostics" | "maximumDiagnosticBytes">> = {}) {
    this.maximumOperations = options.maximumOperations ?? 1024;
    this.maximumPayloadBytes = options.maximumPayloadBytes ?? 16 * 1024 * 1024;
    this.maximumDiagnostics = options.maximumDiagnostics ?? 256;
    this.maximumDiagnosticBytes = options.maximumDiagnosticBytes ?? 64 * 1024 * 1024;
    if (!boundedInteger(this.maximumOperations, 0, 4096) || !boundedInteger(this.maximumPayloadBytes, 1, 64 * 1024 * 1024) ||
      !boundedInteger(this.maximumDiagnostics, 1, 1024) || !boundedInteger(this.maximumDiagnosticBytes, 1, 64 * 1024 * 1024)) {
      throw failure("invalidLimits", "Editing limits exceed their supported bounds.");
    }
    Object.freeze(this);
  }
}

export interface DocumentHeader {
  readonly version: string;
  readonly axis: string;
  readonly title: string | null;
  readonly metadata: Readonly<Record<string, string>>;
  readonly preamble: string | null;
}
export type DocumentEdit =
  { readonly kind: "insert"; readonly plane: Plane; readonly at: number } |
  { readonly kind: "remove"; readonly id: string } |
  { readonly kind: "replace"; readonly id: string; readonly plane: Plane } |
  { readonly kind: "move"; readonly id: string; readonly to: number } |
  { readonly kind: "replaceHeader"; readonly header: DocumentHeader };
export interface DocumentPatch {
  readonly expectedRevision: Pick<DocumentRevision, "canonicalContent">;
  readonly operations: readonly DocumentEdit[];
}
export type CompositionEdit =
  { readonly kind: "insertEntry"; readonly entry: DocumentEntry } |
  { readonly kind: "removeEntry"; readonly id: string } |
  { readonly kind: "replaceEntry"; readonly id: string; readonly entry: DocumentEntry } |
  { readonly kind: "selectRoot"; readonly id: string } |
  { readonly kind: "insertReference"; readonly ownerID: string; readonly reference: DocumentReference; readonly at: number } |
  { readonly kind: "removeReference"; readonly ownerID: string; readonly id: string } |
  { readonly kind: "replaceReference"; readonly ownerID: string; readonly id: string; readonly reference: DocumentReference } |
  { readonly kind: "moveReference"; readonly ownerID: string; readonly id: string; readonly to: number };
export interface CompositionPatch {
  readonly expectedRevision: Pick<DocumentRevision, "canonicalContent">;
  readonly operations: readonly CompositionEdit[];
}

/** `id` stays opaque. This helper returns only the optional namespaced editing identity. */
export function stableID(value: Pick<Plane | DocumentReference, "attributes">): string | undefined {
  return Object.hasOwn(value.attributes, "3md-id") ? value.attributes["3md-id"] : undefined;
}
function validateIdentities(values: readonly Pick<Plane | DocumentReference, "attributes">[], kind: "Plane" | "Reference",
  prefix: string, signal?: AbortSignal): void {
  const ids = new Set<string>();
  for (const [index, value] of values.entries()) {
    checkCancellation(signal);
    const id = stableID(value);
    if (id === undefined) continue;
    const path = `${prefix}[${index}].attributes[3md-id]`;
    if (!validID(id)) throw failure("invalidIdentity", `${kind} identity must be a safe nonempty ASCII ID.`, path);
    if (ids.has(id)) throw failure("duplicateIdentity", `${kind} identity is already used ${kind === "Plane" ? "in this document" : "by this owner"}.`, path);
    ids.add(id);
  }
}
function validateDocumentIdentity(document: Document, prefix = "", signal?: AbortSignal): void {
  validateIdentities(document.planes, "Plane", `${prefix}planes`, signal);
}
function validateCompositionIdentity(composition: DocumentComposition, signal?: AbortSignal): void {
  for (const [index, entry] of composition.entries.entries()) {
    validateDocumentIdentity(entry.document, `entries[${index}].document.`, signal);
    validateIdentities(entry.references, "Reference", `entries[${index}].references`, signal);
  }
}
function adoptValues<Value extends Pick<Plane | DocumentReference, "attributes">>(values: readonly Value[], prefix: string,
  signal?: AbortSignal): Value[] {
  const ids = new Set(values.map(stableID).filter((id): id is string => id !== undefined));
  let next = 1;
  return values.map((value) => {
    checkCancellation(signal);
    if (stableID(value) !== undefined) return value;
    while (ids.has(`${prefix}-${next}`)) next += 1;
    const id = `${prefix}-${next}`; ids.add(id); next += 1;
    return { ...value, attributes: { ...value.attributes, "3md-id": id } };
  });
}
export class DocumentIdentity {
  public static readonly attributeKey = "3md-id";
  public static isValid(id: string): boolean { return validID(id); }
  public static adopt(document: Document, documentLimits?: DocumentDecodeLimits, signal?: AbortSignal): Document;
  public static adopt(composition: DocumentComposition, limits?: DocumentCompositionLimits, documentLimits?: DocumentDecodeLimits,
    signal?: AbortSignal): DocumentComposition;
  public static adopt(value: Document | DocumentComposition,
    first: DocumentDecodeLimits | DocumentCompositionLimits = value instanceof DocumentComposition ? DocumentCompositionLimits.standard : DocumentDecodeLimits.standard,
    second?: AbortSignal | DocumentDecodeLimits, third?: AbortSignal): Document | DocumentComposition {
    if (value instanceof DocumentComposition) {
      checkCancellation(third);
      const limits = new DocumentCompositionLimits(first as DocumentCompositionLimits);
      const documentLimits = new DocumentDecodeLimits(second as DocumentDecodeLimits | undefined);
      validateCompositionIdentity(value, third);
      const entries = value.entries.map((entry): DocumentEntry => ({ ...entry,
        document: this.adopt(entry.document, documentLimits, third), references: adoptValues(entry.references, "reference", third) }));
      return new DocumentComposition(value.rootID, entries, limits, documentLimits, third);
    }
    const signal = second as AbortSignal | undefined;
    checkCancellation(signal);
    const limits = new DocumentDecodeLimits(first as DocumentDecodeLimits);
    DocumentStorageCodec.validate(value, limits, signal); validateDocumentIdentity(value, "", signal);
    const result = { ...value, planes: adoptValues(value.planes, "plane", signal) };
    DocumentStorageCodec.validate(result, limits, signal);
    return frozenDocument(result, signal);
  }
}

export class DocumentSnapshot {
  public readonly document: Document;
  public readonly revision: DocumentRevision;
  public constructor(document: Document, limits = DocumentDecodeLimits.standard, signal?: AbortSignal) {
    const data = DocumentStorageCodec.encode(document, DocumentStorageFormat.text, limits, signal);
    validateDocumentIdentity(document, "", signal);
    this.document = frozenDocument(document, signal); this.revision = new DocumentRevision(new TextDecoder().decode(data));
    checkCancellation(signal);
    Object.freeze(this);
  }
  public static fromJSON(value: { readonly document: Document; readonly revision: Pick<DocumentRevision, "canonicalContent"> },
    limits = DocumentDecodeLimits.standard, signal?: AbortSignal): DocumentSnapshot {
    const result = new DocumentSnapshot(value.document, limits, signal);
    if (!result.revision.equals(value.revision)) throw failure("staleRevision", "Decoded revision disagrees with its document.", "revision");
    return result;
  }
}
export class DocumentCompositionSnapshot {
  public readonly composition: DocumentComposition;
  public readonly revision: DocumentRevision;
  public constructor(composition: DocumentComposition, limits = DocumentCompositionLimits.standard,
    documentLimits = DocumentDecodeLimits.standard, signal?: AbortSignal) {
    const data = DocumentCompositionCodec.encode(composition, limits, documentLimits, signal);
    validateCompositionIdentity(composition, signal);
    this.composition = new DocumentComposition(composition.rootID, composition.entries, limits, documentLimits, signal);
    this.revision = new DocumentRevision(new TextDecoder().decode(data)); Object.freeze(this);
  }
  public static fromJSON(value: { readonly composition: { readonly rootID: string; readonly entries: readonly DocumentEntry[] };
    readonly revision: Pick<DocumentRevision, "canonicalContent"> }, limits = DocumentCompositionLimits.standard,
    documentLimits = DocumentDecodeLimits.standard, signal?: AbortSignal): DocumentCompositionSnapshot {
    const result = new DocumentCompositionSnapshot(DocumentComposition.fromJSON(value.composition, limits, documentLimits, signal),
      limits, documentLimits, signal);
    if (!result.revision.equals(value.revision)) throw failure("staleRevision", "Decoded revision disagrees with its composition.", "revision");
    return result;
  }
}

/** Every operand is charged before source serialization or staged mutation. */
class PayloadBudget {
  private used = 0;
  public constructor(private readonly maximumBytes: number, private readonly signal?: AbortSignal) {}
  public charge(text: string): void {
    let count: number;
    try { count = utf8Length(text, this.signal); }
    catch (error) {
      checkCancellation(this.signal);
      if (error instanceof InvalidUnicodeError) throw failure("invalidDocument", error.message);
      throw error;
    }
    if (count >= this.maximumBytes - this.used) throw failure("payloadLimit", "The edit payload exceeds its UTF-8 byte budget.");
    this.used += count + 1;
  }
  public attributes(values: Readonly<Record<string, string>>): void {
    if (Object.keys(values).length > Math.floor((this.maximumBytes - this.used) / 2)) throw failure("payloadLimit", "The edit attribute payload exceeds its byte budget.");
    for (const [key, value] of Object.entries(values)) { this.charge(key); this.charge(value); }
  }
  public plane(value: Plane): void {
    this.charge(value.body); if (value.label !== null) this.charge(value.label); this.attributes(value.attributes);
    const number = (value: number): string => Number.isInteger(value) && Math.abs(value) < 1e15 ? `${Object.is(value, -0) ? "-0" : String(value)}.0` : canonicalNumber(value);
    this.charge(number(value.z)); if (value.x !== null) this.charge(number(value.x)); if (value.y !== null) this.charge(number(value.y));
  }
  public header(value: DocumentHeader): void {
    this.charge(value.version); this.charge(value.axis); if (value.title !== null) this.charge(value.title);
    if (value.preamble !== null) this.charge(value.preamble); this.attributes(value.metadata);
  }
  public document(value: Document): void {
    this.header(value);
    if (value.planes.length > this.maximumBytes - this.used) throw failure("payloadLimit", "The edit plane payload exceeds its byte budget.");
    for (const plane of value.planes) this.plane(plane);
  }
  public entry(value: DocumentEntry): void {
    this.charge(value.id); this.document(value.document);
    if (value.references.length > this.maximumBytes - this.used) throw failure("payloadLimit", "Reference payload exceeds the edit byte budget.");
    for (const reference of value.references) { this.charge(reference.targetID); this.attributes(reference.attributes); }
  }
}
function targetID(id: string, path: string): void {
  if (!validID(id)) throw failure("invalidIdentity", "An edit target must be a safe nonempty ASCII ID.", path);
}
function target<Value>(id: string, values: readonly Value[], identity: (value: Value) => string | undefined,
  path: string, missing: string): number {
  targetID(id, path);
  const index = values.findIndex((value) => identity(value) === id);
  if (index < 0) throw failure("missingTarget", missing, path);
  return index;
}
function preconditions(patch: DocumentPatch | CompositionPatch, revision: DocumentRevision, limits: DocumentEditLimits,
  revisionBytes: number, graph: boolean, signal?: AbortSignal): void {
  checkCancellation(signal);
  if (patch.operations.length > limits.maximumOperations) throw failure("operationLimit", "The transaction exceeds its operation limit.", "operations");
  if (utf8Length(patch.expectedRevision.canonicalContent, signal) > revisionBytes) throw failure("payloadLimit", "The expected revision exceeds its byte limit.", "expectedRevision");
  if (revision.canonicalContent !== patch.expectedRevision.canonicalContent) {
    throw failure("staleRevision", `The ${graph ? "composition" : "document"} changed after this patch was prepared.`, "expectedRevision");
  }
}

export class DocumentEditor {
  public static apply(patch: DocumentPatch, snapshot: DocumentSnapshot, limits = DocumentEditLimits.standard,
    documentLimits = DocumentDecodeLimits.standard, signal?: AbortSignal): DocumentSnapshot {
    checkCancellation(signal);
    limits = new DocumentEditLimits(limits);
    documentLimits = new DocumentDecodeLimits(documentLimits);
    preconditions(patch, snapshot.revision, limits, documentLimits.maximumDecodedBytes, false, signal);
    const current = new DocumentSnapshot(snapshot.document, documentLimits, signal);
    if (!current.revision.equals(snapshot.revision)) throw failure("staleRevision", "Snapshot revision disagrees with its document.", "revision");
    const budget = new PayloadBudget(limits.maximumPayloadBytes, signal);
    for (const operation of patch.operations) {
      checkCancellation(signal);
      switch (operation.kind) {
        case "insert": budget.plane(operation.plane); break;
        case "replace": budget.charge(operation.id); budget.plane(operation.plane); break;
        case "remove": case "move": budget.charge(operation.id); break;
        case "replaceHeader": budget.header(operation.header); break;
      }
    }
    let header: DocumentHeader = snapshot.document;
    const planes = [...snapshot.document.planes];
    for (const [index, operation] of patch.operations.entries()) {
      checkCancellation(signal);
      const path = `operations[${index}]`;
      const locate = (id: string): number => target(id, planes, stableID, path, "The target plane identity does not exist.");
      switch (operation.kind) {
        case "replaceHeader": header = operation.header; break;
        case "insert": {
          if (!boundedInteger(operation.at, 0, planes.length)) throw failure("invalidIndex", "Insertion index is outside the source-order list.", path);
          const id = stableID(operation.plane);
          if (id === undefined) throw failure("missingIdentity", "An inserted plane needs a stable identity.", path);
          targetID(id, path);
          if (planes.some((plane) => stableID(plane) === id)) throw failure("duplicateIdentity", "An inserted plane identity is already used.", path);
          if (planes.length >= documentLimits.maximumPlanes) throw failure("payloadLimit", "The transaction exceeds the plane limit.", path);
          planes.splice(operation.at, 0, operation.plane); break;
        }
        case "remove": planes.splice(locate(operation.id), 1); break;
        case "replace": {
          const position = locate(operation.id);
          if (stableID(operation.plane) !== operation.id) throw failure("identityChanged", "Replacement must retain the target identity.", path);
          planes[position] = operation.plane; break;
        }
        case "move": {
          const position = locate(operation.id);
          if (!boundedInteger(operation.to, 0, planes.length - 1)) throw failure("invalidIndex", "Move index is outside the final source-order list.", path);
          const plane = planes.splice(position, 1)[0];
          if (plane !== undefined) planes.splice(operation.to, 0, plane); break;
        }
      }
    }
    const result: Document = { version: header.version, axis: header.axis, title: header.title, metadata: header.metadata,
      preamble: header.preamble, planes };
    const coordinates = new Set<number>();
    for (const [index, plane] of planes.entries()) {
      checkCancellation(signal);
      // NaN is unequal to itself in Swift; final storage validation diagnoses nonfinite coordinates.
      if (!Number.isNaN(plane.z)) {
        if (coordinates.has(plane.z)) throw failure("duplicatePosition", "Final plane positions must be unique.", `planes[${index}].z`);
        coordinates.add(plane.z);
      }
    }
    try { return new DocumentSnapshot(result, documentLimits, signal); }
    catch (error) {
      checkCancellation(signal); if (error instanceof DocumentEditError) throw error;
      throw failure("invalidDocument", message(error));
    }
  }
}

function graphFailure(error: DocumentCompositionError, entries: readonly DocumentEntry[]): DocumentEditError {
  let path = "entries";
  if (error.code === "missingRoot") path = "rootID";
  else if (error.code === "missingTarget") {
    const index = entries.findIndex((entry) => entry.id === error.detail);
    const reference = entries[index]?.references.findIndex((reference) => reference.targetID === error.target);
    if (index >= 0 && reference !== undefined && reference >= 0) path = `entries[${index}].references[${reference}].targetID`;
  } else if (["cycle", "invalidID", "duplicateID"].includes(error.code)) {
    const index = entries.findIndex((entry) => entry.id === error.detail); path = index < 0 ? "rootID" : `entries[${index}]`;
  }
  return failure("invalidComposition", error.message, path);
}
export class CompositionEditor {
  public static apply(patch: CompositionPatch, snapshot: DocumentCompositionSnapshot, limits = DocumentEditLimits.standard,
    compositionLimits = DocumentCompositionLimits.standard, documentLimits = DocumentDecodeLimits.standard,
    signal?: AbortSignal): DocumentCompositionSnapshot {
    checkCancellation(signal);
    limits = new DocumentEditLimits(limits);
    compositionLimits = new DocumentCompositionLimits(compositionLimits);
    documentLimits = new DocumentDecodeLimits(documentLimits);
    preconditions(patch, snapshot.revision, limits, compositionLimits.maximumProfileBytes, true, signal);
    const current = new DocumentCompositionSnapshot(snapshot.composition, compositionLimits, documentLimits, signal);
    if (!current.revision.equals(snapshot.revision)) throw failure("staleRevision", "Snapshot revision disagrees with its composition.", "revision");
    const budget = new PayloadBudget(limits.maximumPayloadBytes, signal);
    for (const operation of patch.operations) {
      checkCancellation(signal);
      switch (operation.kind) {
        case "insertEntry": budget.entry(operation.entry); break;
        case "replaceEntry": budget.charge(operation.id); budget.entry(operation.entry); break;
        case "removeEntry": case "selectRoot": budget.charge(operation.id); break;
        case "insertReference": budget.charge(operation.ownerID); budget.charge(operation.reference.targetID); budget.attributes(operation.reference.attributes); break;
        case "replaceReference": budget.charge(operation.ownerID); budget.charge(operation.id); budget.charge(operation.reference.targetID); budget.attributes(operation.reference.attributes); break;
        case "removeReference": case "moveReference": budget.charge(operation.ownerID); budget.charge(operation.id); break;
      }
    }
    let rootID = snapshot.composition.rootID;
    const entries = [...snapshot.composition.entries];
    for (const [index, operation] of patch.operations.entries()) {
      checkCancellation(signal);
      const path = `operations[${index}]`;
      const owner = (id: string): number => target(id, entries, (entry) => entry.id, path, "The owning definition does not exist.");
      switch (operation.kind) {
        case "selectRoot": targetID(operation.id, path); rootID = operation.id; break;
        case "insertEntry":
          targetID(operation.entry.id, path);
          if (entries.some((entry) => entry.id === operation.entry.id)) throw failure("duplicateIdentity", "The definition ID already exists.", path);
          if (entries.length >= compositionLimits.maximumDefinitions) throw failure("payloadLimit", "The transaction exceeds its definition limit.", path);
          entries.push(operation.entry); break;
        case "removeEntry": entries.splice(owner(operation.id), 1); break;
        case "replaceEntry": {
          const position = owner(operation.id);
          if (operation.entry.id !== operation.id) throw failure("identityChanged", "Replacement must retain its definition ID.", path);
          entries[position] = operation.entry; break;
        }
        case "insertReference": case "removeReference": case "replaceReference": case "moveReference": {
          const position = owner(operation.ownerID);
          const entry = entries[position];
          if (entry === undefined) throw failure("missingTarget", "The owning definition does not exist.", path);
          const references = [...entry.references];
          const locate = (id: string): number => target(id, references, stableID, path, "The reference identity does not exist in this owner.");
          if (operation.kind === "insertReference") {
            if (!boundedInteger(operation.at, 0, references.length)) throw failure("invalidIndex", "Reference insertion index is outside its owner list.", path);
            const id = stableID(operation.reference);
            if (id === undefined) throw failure("missingIdentity", "An inserted reference needs a stable identity.", path);
            targetID(id, path);
            if (references.some((reference) => stableID(reference) === id)) throw failure("duplicateIdentity", "The reference identity already exists in this owner.", path);
            if (references.length >= compositionLimits.maximumReferences) throw failure("payloadLimit", "The owner exceeds the reference-record limit.", path);
            references.splice(operation.at, 0, operation.reference);
          } else if (operation.kind === "removeReference") references.splice(locate(operation.id), 1);
          else if (operation.kind === "replaceReference") {
            const target = locate(operation.id);
            if (stableID(operation.reference) !== operation.id) throw failure("identityChanged", "Replacement must retain its reference identity.", path);
            references[target] = operation.reference;
          } else {
            const target = locate(operation.id);
            if (!boundedInteger(operation.to, 0, references.length - 1)) throw failure("invalidIndex", "Reference move index is outside its final owner list.", path);
            const reference = references.splice(target, 1)[0];
            if (reference !== undefined) references.splice(operation.to, 0, reference);
          }
          entries[position] = { ...entry, references }; break;
        }
      }
    }
    try {
      return new DocumentCompositionSnapshot(new DocumentComposition(rootID, entries, compositionLimits, documentLimits, signal),
        compositionLimits, documentLimits, signal);
    } catch (error) {
      checkCancellation(signal);
      if (error instanceof DocumentEditError) throw error;
      if (error instanceof DocumentCompositionError) throw graphFailure(error, entries);
      throw failure("invalidDocument", message(error), "entries");
    }
  }
}

export class DocumentDiagnostics {
  public static parseFailure(error: ParseError): DocumentDiagnostic {
    return diagnostic("parseFailure", error.message, "source", error.line ?? null);
  }
  public static inspect(source: string, limits?: DocumentEditLimits, documentLimits?: DocumentDecodeLimits, signal?: AbortSignal): DocumentDiagnosticReport;
  public static inspect(document: Document, limits?: DocumentEditLimits, documentLimits?: DocumentDecodeLimits, signal?: AbortSignal): DocumentDiagnosticReport;
  public static inspect(composition: DocumentComposition, limits?: DocumentEditLimits, compositionLimits?: DocumentCompositionLimits,
    documentLimits?: DocumentDecodeLimits, signal?: AbortSignal): DocumentDiagnosticReport;
  public static inspect(value: string | Document | DocumentComposition, limits = DocumentEditLimits.standard,
    first: DocumentDecodeLimits | DocumentCompositionLimits = value instanceof DocumentComposition ? DocumentCompositionLimits.standard : DocumentDecodeLimits.standard,
    second?: DocumentDecodeLimits | AbortSignal, third?: AbortSignal): DocumentDiagnosticReport {
    if (value instanceof DocumentComposition) return this.composition(value, limits, first as DocumentCompositionLimits,
      second as DocumentDecodeLimits | undefined ?? DocumentDecodeLimits.standard, third);
    const signal = second as AbortSignal | undefined;
    checkCancellation(signal);
    limits = new DocumentEditLimits(limits);
    const documentLimits = new DocumentDecodeLimits(first as DocumentDecodeLimits);
    if (typeof value !== "string") return this.document(value, limits, documentLimits, signal);
    if (utf8Length(value, signal) > limits.maximumDiagnosticBytes) throw failure("payloadLimit", "Diagnostic source exceeds its byte budget.", "source");
    try { return this.document(DocumentStorageCodec.decode(new TextEncoder().encode(value), documentLimits, signal), limits, documentLimits, signal); }
    catch (error) {
      checkCancellation(signal);
      if (error instanceof DocumentEditError) throw error;
      if (error instanceof DocumentStorageError) {
        if (error.code === "invalidText" && error.detail instanceof ParseError) return report([this.parseFailure(error.detail)]);
        return report([diagnostic("invalidDocument", error.message, "source")]);
      }
      throw error;
    }
  }
  private static document(document: Document, limits: DocumentEditLimits, documentLimits: DocumentDecodeLimits,
    signal?: AbortSignal): DocumentDiagnosticReport {
    checkCancellation(signal);
    limits = new DocumentEditLimits(limits);
    documentLimits = new DocumentDecodeLimits(documentLimits);
    if (document.planes.length > documentLimits.maximumPlanes) throw failure("payloadLimit", "Diagnostic plane count exceeds the document policy.", "planes");
    new PayloadBudget(limits.maximumDiagnosticBytes, signal).document(document);
    const diagnostics: DocumentDiagnostic[] = [];
    const ids = new Set<string>(); const positions = new Set<number>();
    for (const [index, plane] of document.planes.entries()) {
      checkCancellation(signal);
      if (diagnostics.length === limits.maximumDiagnostics) return report(diagnostics, true);
      const id = stableID(plane);
      if (id !== undefined) {
        const path = `planes[${index}].attributes[3md-id]`;
        if (!validID(id)) diagnostics.push(diagnostic("invalidIdentity", "Plane identity must be a safe nonempty ASCII ID.", path));
        else if (ids.has(id)) diagnostics.push(diagnostic("duplicateIdentity", "Plane identity is already used in this document.", path));
        else ids.add(id);
      }
      if (diagnostics.length === limits.maximumDiagnostics) return report(diagnostics, true);
      if (![plane.z, plane.x ?? 0, plane.y ?? 0].every(Number.isFinite)) diagnostics.push(diagnostic("invalidDocument", "Plane coordinates must be finite.", `planes[${index}]`));
      else if (positions.has(plane.z)) diagnostics.push(diagnostic("duplicatePosition", "Plane position is already used.", `planes[${index}].z`));
      else positions.add(plane.z);
    }
    if (diagnostics.length === limits.maximumDiagnostics) return report(diagnostics, true);
    try { DocumentStorageCodec.validate(document, documentLimits, signal); }
    catch (error) {
      checkCancellation(signal);
      if (!diagnostics.some((issue) => issue.code === "duplicatePosition" || issue.code === "invalidDocument")) diagnostics.push(diagnostic("invalidDocument", message(error)));
    }
    return report(diagnostics);
  }
  private static composition(composition: DocumentComposition, limits: DocumentEditLimits,
    compositionLimits: DocumentCompositionLimits, documentLimits: DocumentDecodeLimits, signal?: AbortSignal): DocumentDiagnosticReport {
    checkCancellation(signal);
    limits = new DocumentEditLimits(limits);
    compositionLimits = new DocumentCompositionLimits(compositionLimits);
    documentLimits = new DocumentDecodeLimits(documentLimits);
    if (composition.entries.length > compositionLimits.maximumDefinitions) throw new DocumentCompositionError("tooManyDefinitions");
    const budget = new PayloadBudget(limits.maximumDiagnosticBytes, signal); budget.charge(composition.rootID);
    let references = 0;
    for (const entry of composition.entries) {
      checkCancellation(signal);
      if (entry.references.length > compositionLimits.maximumReferences - references) throw new DocumentCompositionError("tooManyReferences");
      references += entry.references.length;
      if (entry.document.planes.length > documentLimits.maximumPlanes) throw new DocumentStorageError("tooManyPlanes");
      budget.entry(entry);
    }
    new DocumentComposition(composition.rootID, composition.entries, compositionLimits, documentLimits, signal);
    const diagnostics: DocumentDiagnostic[] = [];
    for (const [entryIndex, entry] of composition.entries.entries()) {
      const result = this.document(entry.document, limits, documentLimits, signal);
      for (const issue of result.diagnostics) {
        if (diagnostics.length === limits.maximumDiagnostics) return report(diagnostics, true);
        diagnostics.push(Object.freeze({ ...issue, path: `entries[${entryIndex}].document${issue.path === null ? "" : `.${issue.path}`}` }));
      }
      if (result.isTruncated) return report(diagnostics, true);
      const ids = new Set<string>();
      for (const [index, reference] of entry.references.entries()) {
        checkCancellation(signal);
        if (diagnostics.length === limits.maximumDiagnostics) return report(diagnostics, true);
        const id = stableID(reference); if (id === undefined) continue;
        const path = `entries[${entryIndex}].references[${index}].attributes[3md-id]`;
        if (!validID(id)) diagnostics.push(diagnostic("invalidIdentity", "Reference identity must be a safe nonempty ASCII ID.", path));
        else if (ids.has(id)) diagnostics.push(diagnostic("duplicateIdentity", "Reference identity is already used by this owner.", path));
        else ids.add(id);
      }
    }
    return report(diagnostics);
  }
}
