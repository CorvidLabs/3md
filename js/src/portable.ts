import type { Document, Plane } from "./index.js";

/** Internal helpers shared by the optional portable extension layers. */
export function checkCancellation(signal?: AbortSignal): void {
  signal?.throwIfAborted();
}

/** Foundation CharacterSet.whitespaces, pinned independently of JavaScript's trim and Unicode regex tables. */
export function isFoundationWhitespace(unit: number): boolean {
  return unit === 0x0009 || unit === 0x0020 || unit === 0x00a0 || unit === 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200b) || unit === 0x202f || unit === 0x205f || unit === 0x3000;
}

/** Linear trimming preserves the frozen Foundation whitespace behavior on every runtime. */
export function trimFoundationWhitespace(value: string, signal?: AbortSignal): string {
  let start = 0;
  let end = value.length;
  while (start < end) {
    if (start % 4096 === 0) checkCancellation(signal);
    const unit = value.charCodeAt(start);
    if (!isFoundationWhitespace(unit)) break;
    start += 1;
  }
  while (end > start) {
    if (end % 4096 === 0) checkCancellation(signal);
    const unit = value.charCodeAt(end - 1);
    if (!isFoundationWhitespace(unit)) break;
    end -= 1;
  }
  return start === 0 && end === value.length ? value : value.slice(start, end);
}

export class InvalidUnicodeError extends Error {
  public constructor() { super("Strings must contain losslessly representable Unicode scalar values."); }
}

/** Counts without allocating an encoded copy and rejects unpaired UTF-16 surrogates. */
export function utf8Length(text: string, signal?: AbortSignal): number {
  let count = 0;
  for (let index = 0; index < text.length; index += 1) {
    if (index % 4096 === 0) checkCancellation(signal);
    const unit = text.charCodeAt(index);
    if (unit < 0x80) count += 1;
    else if (unit < 0x800) count += 2;
    else if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = text.charCodeAt(index + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) throw new InvalidUnicodeError();
      count += 4;
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) throw new InvalidUnicodeError();
    else count += 3;
  }
  return count;
}

export function stringsEqual(left: Readonly<Record<string, string>>, right: Readonly<Record<string, string>>): boolean {
  const normalized = (value: Readonly<Record<string, string>>): Map<string, string> =>
    new Map(Object.entries(value).map(([key, text]) => [key.normalize("NFC"), text]));
  const first = normalized(left); const second = normalized(right);
  return first.size === second.size && [...first].every(([key, value]) => second.has(key) && second.get(key) === value);
}

/** Swift dictionaries compare Unicode-equivalent keys and retain the first key's spelling. */
export function canonicalStrings(source: Readonly<Record<string, string>>, signal?: AbortSignal): Record<string, string> {
  const result: Record<string, string> = Object.create(null);
  const spellings = new Map<string, string>();
  for (const [key, value] of Object.entries(source)) {
    checkCancellation(signal);
    const normalized = key.normalize("NFC");
    const first = spellings.get(normalized) ?? key;
    if (!spellings.has(normalized)) spellings.set(normalized, key);
    result[first] = value;
  }
  return result;
}

/** NFC scalar comparison matches Swift rather than JavaScript's UTF-16 code-unit ordering. */
export function canonicalKeys(source: Readonly<Record<string, string>>): string[] {
  const normalized = new Map(Object.keys(source).map((key) => [key, key.normalize("NFC")]));
  return Object.keys(source).sort((left, right) => {
    const first = normalized.get(left) ?? left; const second = normalized.get(right) ?? right;
    let a = 0; let b = 0;
    while (a < first.length && b < second.length) {
      const x = first.codePointAt(a) ?? 0; const y = second.codePointAt(b) ?? 0;
      if (x !== y) return x < y ? -1 : 1;
      a += x > 0xffff ? 2 : 1; b += y > 0xffff ? 2 : 1;
    }
    return a < first.length ? 1 : b < second.length ? -1 : 0;
  });
}

export function canonicalDocument(document: Document, signal?: AbortSignal): Document {
  return { ...document, metadata: canonicalStrings(document.metadata, signal),
    planes: document.planes.map((plane) => {
      checkCancellation(signal);
      return { ...plane, attributes: canonicalStrings(plane.attributes, signal) };
    }) };
}

export function documentsEqual(left: Document, right: Document): boolean {
  return left.version === right.version && left.axis === right.axis && left.title === right.title &&
    left.preamble === right.preamble && stringsEqual(left.metadata, right.metadata) &&
    left.planes.length === right.planes.length && left.planes.every((plane, index) => {
      const other = right.planes[index];
      return other !== undefined && plane.z === other.z && plane.x === other.x && plane.y === other.y &&
        plane.label === other.label && plane.body === other.body && stringsEqual(plane.attributes, other.attributes);
    });
}

export function frozenStrings(source: Readonly<Record<string, string>>, signal?: AbortSignal): Readonly<Record<string, string>> {
  return Object.freeze(canonicalStrings(source, signal));
}

export function frozenPlane(plane: Plane, signal?: AbortSignal): Plane {
  checkCancellation(signal);
  return Object.freeze({ ...plane, attributes: frozenStrings(plane.attributes, signal) });
}

export function frozenDocument(document: Document, signal?: AbortSignal): Document {
  return Object.freeze({ ...document, metadata: frozenStrings(document.metadata, signal),
    planes: Object.freeze(document.planes.map((plane) => frozenPlane(plane, signal))) });
}

export function validID(id: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(id);
}

export function boundedInteger(value: number, minimum: number, maximum: number): boolean {
  return Number.isSafeInteger(value) && value >= minimum && value <= maximum;
}
