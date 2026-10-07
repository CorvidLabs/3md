// Payload kind 2: the structured document payload of the version 1 binary container (SPEC.md 11.3, ThreeMD 2.1).
//
// Internal module. storage.ts owns the container (SPEC.md 11.1 and 11.3.2: header, steps D1 to D13, CRC) and calls
// `readStructured` for step D14 and `writeStructuredPayload` for steps W2 to W4. Nothing here is exported from the
// package index.
//
// The module has no top-level side effects, so bundles that only parse text drop it (the element bundle invariant):
// every module-level binding is a literal, a function or a class. The fatal UTF-8 decoder and the UTF-8 encoder are
// created on first use.

import { parse, ParseError, type Document, type Plane } from "./index.js";
import { canonicalNumber } from "./number.js";
import {
  canonicalKeys, checkCancellation, InvalidUnicodeError, isFoundationWhitespace, trimFoundationWhitespace, utf8Length,
} from "./portable.js";
import { DocumentStorageError, validateRecords, type DocumentDecodeLimits, type DocumentStorageErrorCode } from "./storage.js";

// MARK: - Constants

/** -2^27 and 2^27 - 1, the range of the integer number form (SPEC.md 11.3.3). */
const INTEGER_MINIMUM = -134_217_728;
const INTEGER_MAXIMUM = 134_217_727;
/** Bytes scanned or validated between two cancellation checks, and the UTF-8 chunk size (SPEC.md 11.3.13). */
const CHUNK = 65_536;
/** Positions compared per block by a key comparison, which reads two bytes or code units per position. */
const COMPARE_BLOCK = CHUNK / 2;
/** ASCII strings up to this length are built with `String.fromCharCode` instead of the decoder. */
const SHORT_ASCII = 48;
/** ASCII strings up to this length are written byte by byte instead of through `encodeInto`. */
const SHORT_WRITE = 64;
/** The largest number spelling (SPEC.md 11.3.7): the bound that decides most length checks without formatting. */
const NUMBER_BOUND = 24;
/** The work charged for the fixed cost of one plane or one map entry (object creation, property access). */
const PLANE_COST = 64;
const ENTRY_COST = 16;
/**
 * Byte classes that `StructuredReader.scanKey` records anywhere in a key or the axis, so the key rules R2, R3 and R9
 * (SPEC.md 11.3.6) never scan a key a second time: A to Z, space or tab, `:` and `=`.
 */
const KEY_UPPER = 1;
const KEY_BLANK = 2;
const KEY_COLON = 4;
const KEY_EQUALS = 8;

/** Informative `invalidDocument` details. The 2.0 storage writer's wording is kept where it has one. */
const DETAIL = {
  scalarBreak: "Scalar fields cannot contain physical line breaks.",
  finite: "Plane coordinates must be finite.",
  unique: "Plane positions must be unique.",
  version: "The version must be nonempty.",
  axis: "The axis must already be trimmed and lowercase.",
  metadataKey: "Metadata keys cannot shadow reserved fields or comments.",
  attributeKey: "Attribute keys must be lowercase and cannot shadow coordinates or labels.",
  equivalent: "Canonically equivalent dictionary keys cannot be represented faithfully.",
  preamblePlanes: "A preamble requires at least one plane.",
  unicode: "Strings must contain losslessly representable Unicode scalar values.",
  directive: "The plane directive would not parse back to the same plane.",
  emptyPreamble: "An empty preamble cannot be represented.",
  trailingCarriageReturn: "A segment cannot end with a carriage return.",
  crlf: "A segment cannot contain CRLF.",
  blankEdge: "A segment cannot begin or end with a blank line.",
  directiveLine: "A segment line outside a fence cannot start a plane directive.",
  openFence: "Only the last plane body may end inside an open fence.",
} as const;

/** Informative `invalidContainer` details. */
const CONTAINER = {
  documentFlags: "The structured payload sets an undefined document flag bit.",
  planeFlags: "The structured payload sets an undefined plane flag bit or has no z coordinate.",
  varTooLong: "A Var continues past the last byte its field allows.",
  varNotMinimal: "A Var in the structured payload is not minimal.",
  numberForm: "A number in the structured payload is not in its canonical form.",
  keyOrder: "Keys in a structured payload map must be in strictly increasing UTF-8 byte order.",
} as const;

// MARK: - Test instrumentation

/**
 * Test-only instrumentation, not part of the package API: `phaseQParses` counts the directive round trips of Phase Q
 * (SPEC.md 11.3.6.6) since the module was loaded, so a test can prove that a hostile payload is rejected before any
 * parse runs.
 */
export const structuredProbe = { phaseQParses: 0 };

// MARK: - Errors

function fail(code: DocumentStorageErrorCode, detail?: unknown): never {
  throw new DocumentStorageError(code, detail);
}

function invalid(detail: string): never {
  throw new DocumentStorageError("invalidDocument", detail);
}

// MARK: - Cancellation by work done

/**
 * Cancellation for loops over many strings, entries or planes (SPEC.md 11.3.13). Each piece of work is charged
 * before it runs: its bytes scanned, compared, decoded, normalized or copied, or a fixed cost per plane or map entry.
 * A check runs first whenever the piece would take the work since the last check past 65,536, so between two checks
 * a loop does at most 65,536 units of work in small pieces, or one larger piece on its own: a string of more than
 * 65,536 bytes whose own scan or UTF-8 decoding checks again every 65,536 bytes, or one native operation on one
 * string (a normalization, a case mapping). A piece larger than the units left also leaves the budget in debt, so the
 * next charge after a long string always checks first. Hand-written loops over long strings charge their work in
 * blocks of at most 65,536 units (key comparisons in blocks of 32,768 positions, two units each).
 */
class WorkBudget {
  private remaining = CHUNK;

  public constructor(public readonly signal: AbortSignal | undefined) {}

  /** Charges `cost` units, checking cancellation first when they do not fit the units left. */
  public spend(cost: number): void {
    if (cost > this.remaining) {
      checkCancellation(this.signal);
      this.remaining = CHUNK;
    }
    this.remaining -= cost;
  }
}

// MARK: - UTF-8

let fatalDecoder: TextDecoder | null = null;
let utf8Encoder: TextEncoder | null = null;

/** One shared fatal decoder, only ever called without `stream`, so it never holds pending bytes between strings. */
function decoder(): TextDecoder {
  if (fatalDecoder === null) fatalDecoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
  return fatalDecoder;
}

function encoder(): TextEncoder {
  if (utf8Encoder === null) utf8Encoder = new TextEncoder();
  return utf8Encoder;
}

/**
 * Str3 for a string longer than 65,536 bytes: validates `bytes[start ..< end]` as one complete, well-formed UTF-8
 * string or throws `invalidUTF8`, with a cancellation check before every 65,536 bytes (plus at most 3 bytes to complete
 * the scalar that straddles the block end), and without building any string (SPEC.md 11.3.13).
 *
 * The rules are those of Unicode Table 3-7, exactly what the fatal `TextDecoder` accepts: no lead byte C0, C1 or F5
 * to FF; no stray continuation byte; E0 needs A0 to BF and ED needs 80 to 9F (no overlong forms, no surrogates); F0
 * needs 90 to BF and F4 needs 80 to 8F (no overlong forms, nothing above U+10FFFF); every sequence complete before
 * `end`. Validating chunks with `TextDecoder` would leave every chunk's string behind as garbage, which Bun keeps
 * resident until a collection, so a long body would cost about three times its size instead of about two. Exported
 * for tests.
 */
export function validateUTF8(bytes: Uint8Array, start: number, end: number, signal?: AbortSignal): void {
  // ASCII runs are tested four bytes at a time through an aligned word view when the bytes allow one.
  const words = (bytes.byteOffset & 3) === 0 ? new Uint32Array(bytes.buffer, bytes.byteOffset, bytes.byteLength >>> 2) : null;
  const lastWord = end >>> 2;
  let index = start;
  while (index < end) {
    checkCancellation(signal);
    const blockEnd = end - index > CHUNK ? index + CHUNK : end;
    while (index < blockEnd) {
      const byte = bytes[index]!;
      if (byte < 0x80) {
        index += 1;
        if (words !== null && (index & 3) === 0) {
          let word = index >>> 2;
          const stop = blockEnd >>> 2 < lastWord ? blockEnd >>> 2 : lastWord;
          while (word < stop && (words[word]! & 0x80808080) === 0) word += 1;
          index = word * 4;
        }
        continue;
      }
      if (byte < 0xc2 || byte > 0xf4) fail("invalidUTF8");
      if (byte < 0xe0) {
        if (index + 1 >= end || (bytes[index + 1]! & 0xc0) !== 0x80) fail("invalidUTF8");
        index += 2;
      } else if (byte < 0xf0) {
        if (index + 2 >= end) fail("invalidUTF8");
        const second = bytes[index + 1]!;
        if ((second & 0xc0) !== 0x80 || (bytes[index + 2]! & 0xc0) !== 0x80) fail("invalidUTF8");
        if ((byte === 0xe0 && second < 0xa0) || (byte === 0xed && second > 0x9f)) fail("invalidUTF8");
        index += 3;
      } else {
        if (index + 3 >= end) fail("invalidUTF8");
        const second = bytes[index + 1]!;
        if ((second & 0xc0) !== 0x80 || (bytes[index + 2]! & 0xc0) !== 0x80 || (bytes[index + 3]! & 0xc0) !== 0x80) {
          fail("invalidUTF8");
        }
        if ((byte === 0xf0 && second < 0x90) || (byte === 0xf4 && second > 0x8f)) fail("invalidUTF8");
        index += 4;
      }
    }
  }
}

/**
 * Str3 and the string itself: decodes `bytes[start ..< end]` as one complete, well-formed UTF-8 string or throws
 * `invalidUTF8`. A string of at most 65,536 bytes takes one fatal, non-streaming decoding call, which validates it. A
 * longer one is first validated by `validateUTF8` and then, after one more check, built by one such call (SPEC.md
 * 11.3.13 allows one native string construction of at most R bytes between two checks): the result is one flat
 * string, never a concatenation of chunks that the engine would copy again on first use.
 */
export function decodeUTF8(bytes: Uint8Array, start: number, end: number, signal?: AbortSignal): string {
  if (end - start > CHUNK) {
    validateUTF8(bytes, start, end, signal);
    checkCancellation(signal);
  }
  return buildUTF8(bytes, start, end);
}

/** One native decoding call over `bytes[start ..< end]`, which the caller has validated or bounded by 65,536 bytes. */
function buildUTF8(bytes: Uint8Array, start: number, end: number): string {
  try { return decoder().decode(bytes.subarray(start, end)); } catch { return fail("invalidUTF8"); }
}

/**
 * An ASCII byte range as a string; the caller has already checked that every byte is below 0x80. Up to 16 bytes go
 * through explicit `String.fromCharCode` arguments, which allocates no view and measured about twice as fast as
 * `apply` on a subarray in both runtimes.
 */
function asciiString(bytes: Uint8Array, start: number, end: number, signal?: AbortSignal): string {
  const b = bytes;
  const s = start;
  const char = String.fromCharCode;
  switch (end - start) {
    case 0: return "";
    case 1: return char(b[s]!);
    case 2: return char(b[s]!, b[s + 1]!);
    case 3: return char(b[s]!, b[s + 1]!, b[s + 2]!);
    case 4: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!);
    case 5: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!);
    case 6: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!);
    case 7: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!, b[s + 6]!);
    case 8: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!, b[s + 6]!, b[s + 7]!);
    case 9: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!, b[s + 6]!, b[s + 7]!, b[s + 8]!);
    case 10: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!, b[s + 6]!, b[s + 7]!, b[s + 8]!,
      b[s + 9]!);
    case 11: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!, b[s + 6]!, b[s + 7]!, b[s + 8]!,
      b[s + 9]!, b[s + 10]!);
    case 12: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!, b[s + 6]!, b[s + 7]!, b[s + 8]!,
      b[s + 9]!, b[s + 10]!, b[s + 11]!);
    case 13: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!, b[s + 6]!, b[s + 7]!, b[s + 8]!,
      b[s + 9]!, b[s + 10]!, b[s + 11]!, b[s + 12]!);
    case 14: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!, b[s + 6]!, b[s + 7]!, b[s + 8]!,
      b[s + 9]!, b[s + 10]!, b[s + 11]!, b[s + 12]!, b[s + 13]!);
    case 15: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!, b[s + 6]!, b[s + 7]!, b[s + 8]!,
      b[s + 9]!, b[s + 10]!, b[s + 11]!, b[s + 12]!, b[s + 13]!, b[s + 14]!);
    case 16: return char(b[s]!, b[s + 1]!, b[s + 2]!, b[s + 3]!, b[s + 4]!, b[s + 5]!, b[s + 6]!, b[s + 7]!, b[s + 8]!,
      b[s + 9]!, b[s + 10]!, b[s + 11]!, b[s + 12]!, b[s + 13]!, b[s + 14]!, b[s + 15]!);
    default:
      if (end - start > SHORT_ASCII) return decodeUTF8(bytes, start, end, signal);
      return char.apply(null, bytes.subarray(start, end) as unknown as number[]);
  }
}

// MARK: - Representability helpers (SPEC.md 11.3.6)

/**
 * Unsigned byte comparison of two ranges of the same buffer; a proper prefix sorts first. The shared prefix is
 * compared in blocks of 32,768 positions, each charged to `budget` as two units per position before it is read.
 */
function compareBytes(bytes: Uint8Array, leftStart: number, leftEnd: number, rightStart: number, rightEnd: number,
  budget: WorkBudget): number {
  const leftLength = leftEnd - leftStart;
  const rightLength = rightEnd - rightStart;
  const shared = leftLength < rightLength ? leftLength : rightLength;
  let index = 0;
  while (index < shared) {
    const blockEnd = shared - index > COMPARE_BLOCK ? index + COMPARE_BLOCK : shared;
    budget.spend(2 * (blockEnd - index));
    for (; index < blockEnd; index += 1) {
      const left = bytes[leftStart + index]!;
      const right = bytes[rightStart + index]!;
      if (left !== right) return left < right ? -1 : 1;
    }
  }
  return leftLength - rightLength;
}

/**
 * Unicode code point order of two strings, which equals the raw UTF-8 byte order of well-formed strings. JavaScript
 * `<` compares UTF-16 code units and puts U+10000 and above before U+E000 to U+FFFF, so it is never used for keys.
 */
export function compareCodePoints(left: string, right: string): number {
  return compareEntries(left, right, null);
}

/**
 * `compareCodePoints` for the writer's sort: one unit for the comparison, then the shared prefix in blocks of 32,768
 * positions, each charged to `budget` as two units per position before it is read. The function name is the
 * cancellation checkpoint the writer sort reports (`spend compareEntries`).
 */
function compareEntries(left: string, right: string, budget: WorkBudget | null): number {
  const shared = left.length < right.length ? left.length : right.length;
  let index = 0;
  let cost = 1;
  do {
    const blockEnd = shared - index > COMPARE_BLOCK ? index + COMPARE_BLOCK : shared;
    budget?.spend(cost + 2 * (blockEnd - index));
    cost = 0;
    for (; index < blockEnd; index += 1) {
      let first = left.charCodeAt(index);
      let second = right.charCodeAt(index);
      if (first !== second) {
        // Surrogates (U+D800 to U+DFFF) stand for code points above U+FFFF, so they sort after U+E000 to U+FFFF.
        if (first >= 0xd800) first = first >= 0xe000 ? first - 0x800 : first + 0x2000;
        if (second >= 0xd800) second = second >= 0xe000 ? second - 0x800 : second + 0x2000;
        return first < second ? -1 : 1;
      }
    }
  } while (index < shared);
  return left.length - right.length;
}

/** Whether every code unit of `text` is below 0x80, read in blocks of 65,536 units charged to `budget` first. */
function isASCII(text: string, budget: WorkBudget): boolean {
  const length = text.length;
  let index = 0;
  while (index < length) {
    const blockEnd = length - index > CHUNK ? index + CHUNK : length;
    budget.spend(blockEnd - index);
    for (; index < blockEnd; index += 1) if (text.charCodeAt(index) >= 0x80) return false;
  }
  return true;
}

/**
 * R2: the axis equals the 2.0 TypeScript normalization `trimFoundationWhitespace(axis).toLowerCase()`. An ASCII axis
 * is decided by its `scanKey` flags and its two ends; a non-ASCII one by one native case mapping, charged first.
 */
function axisIsNormalized(axis: string, ascii: boolean, flags: number, budget: WorkBudget): boolean {
  if (!ascii) {
    budget.spend(axis.length);
    return trimFoundationWhitespace(axis, budget.signal).toLowerCase() === axis;
  }
  const length = axis.length;
  if (length === 0) return true;
  const first = axis.charCodeAt(0);
  const last = axis.charCodeAt(length - 1);
  return first !== 0x20 && first !== 0x09 && last !== 0x20 && last !== 0x09 && (flags & KEY_UPPER) === 0;
}

/** Case-insensitive ASCII equality of `bytes[start ..< start + length]` with a lowercase ASCII literal. */
function asciiBytesCaseEqual(bytes: Uint8Array, start: number, length: number, lower: string): boolean {
  if (length !== lower.length) return false;
  for (let index = 0; index < length; index += 1) {
    let byte = bytes[start + index]!;
    if (byte >= 0x41 && byte <= 0x5a) byte += 0x20;
    if (byte !== lower.charCodeAt(index)) return false;
  }
  return true;
}

/**
 * R3: a metadata key that the canonical text writer and parser keep exactly. The empty key is valid. The key's
 * `scanKey` flags decide the colon test, so only the key's ends are read: `bytes[start ..< end]` for an ASCII key,
 * or the decoded `key` when it is not ASCII (a reserved field name is ASCII and never matches one).
 */
function metadataKeyIsValid(bytes: Uint8Array, start: number, end: number, key: string | null, flags: number): boolean {
  const length = end - start;
  if (length === 0) return true;
  if ((flags & KEY_COLON) !== 0) return false;
  if (key !== null) {
    const first = key.charCodeAt(0);
    return first !== 0x23 && !isFoundationWhitespace(first) && !isFoundationWhitespace(key.charCodeAt(key.length - 1));
  }
  // The only W scalars in ASCII are space and tab.
  const first = bytes[start]!;
  const last = bytes[end - 1]!;
  if (first === 0x23 || first === 0x20 || first === 0x09 || last === 0x20 || last === 0x09) return false;
  return !(length >= 3 && length <= 5 && (asciiBytesCaseEqual(bytes, start, length, "3md") ||
    asciiBytesCaseEqual(bytes, start, length, "axis") || asciiBytesCaseEqual(bytes, start, length, "title")));
}

/**
 * R9: an attribute key of a plane whose keys hold no quote character. The key's `scanKey` flags decide the space,
 * tab, `=` and (for ASCII) uppercase tests; a non-ASCII key also needs W-free ends and one native case mapping,
 * charged first. Reserved names (z, x, y, label) are ASCII.
 */
function attributeKeyIsValid(bytes: Uint8Array, start: number, end: number, key: string | null, flags: number,
  budget: WorkBudget): boolean {
  const length = end - start;
  if (length === 0 || (flags & (KEY_BLANK | KEY_EQUALS)) !== 0) return false;
  if (key !== null) {
    if (isFoundationWhitespace(key.charCodeAt(0)) || isFoundationWhitespace(key.charCodeAt(key.length - 1))) return false;
    budget.spend(key.length);
    return key.toLowerCase() === key;
  }
  if ((flags & KEY_UPPER) !== 0) return false;
  if (length === 1) {
    const byte = bytes[start]!;
    return byte !== 0x7a && byte !== 0x78 && byte !== 0x79; // z, x, y
  }
  return !(length === 5 && bytes[start] === 0x6c && bytes[start + 1] === 0x61 && bytes[start + 2] === 0x62 &&
    bytes[start + 3] === 0x65 && bytes[start + 4] === 0x6c); // label
}

/** The number of bytes of the canonical spelling of an integer-form value (SPEC.md 11.3.7). */
function integerLength(value: number): number {
  const magnitude = value < 0 ? -value : value;
  const digits = magnitude < 10 ? 1 : magnitude < 100 ? 2 : magnitude < 1e3 ? 3 : magnitude < 1e4 ? 4 :
    magnitude < 1e5 ? 5 : magnitude < 1e6 ? 6 : magnitude < 1e7 ? 7 : magnitude < 1e8 ? 8 : 9;
  return value < 0 ? digits + 1 : digits;
}

/** Skips the leading W scalars of `text[index ..< end]`, checking cancellation at least every 65,536 units. */
function skipWhitespace(text: string, index: number, end: number, signal?: AbortSignal): number {
  let next = index + CHUNK;
  while (index < end) {
    const unit = text.charCodeAt(index);
    if (unit !== 0x20 && unit !== 0x09 && (unit < 0xa0 || !isFoundationWhitespace(unit))) break;
    index += 1;
    if (index >= next) { checkCancellation(signal); next = index + CHUNK; }
  }
  return index;
}

/**
 * The segment rules G1 to G6 (SPEC.md 11.3.6.4) over a decoded preamble or body, evaluated in one pass. The segment's
 * length is charged to `budget` first; the pass itself checks again every 65,536 code units.
 * @returns LF(segment), the number of line feeds, for the line count of SPEC.md 11.3.7.
 */
function checkSegment(text: string, preamble: boolean, final: boolean, budget: WorkBudget): number {
  const length = text.length;
  const signal = budget.signal;
  budget.spend(length);
  if (length === 0) {
    if (preamble) invalid(DETAIL.emptyPreamble); // G1
    return 0;
  }
  if (text.charCodeAt(length - 1) === 0x0d) invalid(DETAIL.trailingCarriageReturn); // G2
  let fence = 0;
  let lineFeeds = 0;
  let start = 0;
  let next = CHUNK;
  for (;;) {
    let end = text.indexOf("\n", start);
    if (end < 0) end = length;
    if (start === 0 && skipWhitespace(text, 0, end, signal) === end) invalid(DETAIL.blankEdge); // G4, first line
    if (end < length && end > 0 && text.charCodeAt(end - 1) === 0x0d) invalid(DETAIL.crlf); // G3
    if (start < end) {
      const first = text.charCodeAt(start);
      // Only a line that starts with W, a fence character or `@` can change the fence or start a directive.
      if (first === 0x60 || first === 0x7e || first === 0x40 || first === 0x20 || first === 0x09 ||
        (first >= 0xa0 && isFoundationWhitespace(first))) {
        const trimmed = first === 0x60 || first === 0x7e || first === 0x40 ? start : skipWhitespace(text, start, end, signal);
        if (fence !== 0) {
          // G5: only three copies of the opening character close a fence.
          if (end - trimmed >= 3 && text.charCodeAt(trimmed) === fence && text.charCodeAt(trimmed + 1) === fence &&
            text.charCodeAt(trimmed + 2) === fence) fence = 0;
        } else if (text.startsWith("```", trimmed)) fence = 0x60;
        else if (text.startsWith("~~~", trimmed)) fence = 0x7e;
        else if (first === 0x40 && text.startsWith("@plane", start) &&
          (end - start === 6 || text.charCodeAt(start + 6) === 0x20 || text.charCodeAt(start + 6) === 0x09)) {
          invalid(DETAIL.directiveLine); // G5
        }
      }
    }
    if (end === length) {
      if (skipWhitespace(text, start, end, signal) === end) invalid(DETAIL.blankEdge); // G4, last line
      break;
    }
    lineFeeds += 1;
    start = end + 1;
    if (start >= next) { checkCancellation(signal); next = start + CHUNK; }
  }
  if (!final && fence !== 0) invalid(DETAIL.openFence); // G6
  return lineFeeds;
}

/** `q(s)` of SPEC.md 11.3.6.6: double quotes, with every `"` and `\` escaped. */
function quoted(text: string): string {
  return `"${text.replace(/[\\"]/g, "\\$&")}"`;
}

/**
 * Phase Q (SPEC.md 11.3.6.6): builds the plane's canonical directive line as the 2.0 TypeScript storage writer does
 * (attributes in `canonicalKeys` order) and parses it with the 2.0 parser. The plane is representable exactly when the
 * parse returns the stored z, x, y and label and byte-equal attributes.
 */
function directiveRoundTrip(z: number, x: number | null, y: number | null, label: string | null,
  keys: readonly string[], values: readonly string[], from: number, to: number): void {
  structuredProbe.phaseQParses += 1;
  const attributes: Record<string, string> = Object.create(null);
  for (let index = from; index < to; index += 1) attributes[keys[index]!] = values[index]!;
  let line = `@plane z=${canonicalNumber(z)}`;
  if (label !== null) line += ` label=${quoted(label)}`;
  if (x !== null) line += ` x=${canonicalNumber(x)}`;
  if (y !== null) line += ` y=${canonicalNumber(y)}`;
  for (const key of canonicalKeys(attributes)) line += ` ${key}=${quoted(attributes[key] ?? "")}`;
  let parsed: Document;
  try { parsed = parse(`---\n3md: "1"\naxis: "a"\n---\n\n${line}\n`); } catch (error) {
    if (error instanceof ParseError) invalid(DETAIL.directive);
    throw error;
  }
  const plane = parsed.planes[0];
  if (parsed.planes.length !== 1 || plane === undefined || !Object.is(plane.z, z) || !Object.is(plane.x, x) ||
    !Object.is(plane.y, y) || plane.label !== label || Object.keys(plane.attributes).length !== to - from) {
    invalid(DETAIL.directive);
  }
  for (let index = from; index < to; index += 1) {
    const key = keys[index]!;
    if (!Object.hasOwn(plane.attributes, key) || plane.attributes[key] !== values[index]) invalid(DETAIL.directive);
  }
}

/** L0 (R7): no two planes share a z. Planes are usually stored in increasing z order, which needs no copy. */
function checkUniquePositions(positions: Float64Array): void {
  let increasing = true;
  for (let index = 1; index < positions.length; index += 1) {
    if (!(positions[index - 1]! < positions[index]!)) { increasing = false; break; }
  }
  if (increasing) return;
  // Every stored z is finite and never -0, so equal values are equal bit patterns.
  const sorted = positions.slice().sort();
  for (let index = 1; index < sorted.length; index += 1) {
    if (sorted[index - 1] === sorted[index]) invalid(DETAIL.unique);
  }
}

// MARK: - Reader (SPEC.md 11.3.3, 11.3.5, 11.3.8)

/** A forward cursor over one payload `bytes[start ..< end]` that applies the primitive rules of SPEC.md 11.3.3. */
class StructuredReader {
  public position: number;
  /** Start, byte length, ASCII flag, escape count and quote flag of the last string read. */
  public stringStart = 0;
  public stringLength = 0;
  public ascii = true;
  public escapes = 0;
  public quote = false;
  /** The KEY_* byte classes of the last string read by `scanKey`. */
  public keyFlags = 0;
  /** The decode's one work budget, shared with the equivalence checks, Phase Q and the result walk. */
  public readonly budget: WorkBudget;
  private view: DataView | null = null;
  /** The payload offset up to which bytes have been charged to the budget. */
  private charged: number;

  public constructor(public readonly bytes: Uint8Array, start: number, public readonly end: number,
    private readonly validate: boolean, public readonly signal: AbortSignal | undefined) {
    this.position = start;
    this.budget = new WorkBudget(signal);
    this.charged = start;
  }

  /** u8. */
  public u8(): number {
    if (this.position >= this.end) fail("lengthMismatch");
    return this.bytes[this.position++]!;
  }

  /**
   * Var: unsigned LEB128, minimal (V1 to V3). A length or count uses 1 to 10 bytes. A coordinate passes 4 so form 1
   * stays inside -2^27 ... 2^27 - 1. Arithmetic is multiply and divide because a JavaScript shift is 32 bits.
   */
  public varint(maximumBytes = 10): number {
    const bytes = this.bytes;
    const end = this.end;
    let position = this.position;
    if (position >= end) fail("lengthMismatch"); // V1
    let byte = bytes[position++]!;
    if (byte < 0x80) {
      this.position = position;
      return byte;
    }
    let value = byte & 0x7f;
    for (let index = 1; index < maximumBytes; index += 1) {
      if (position >= end) fail("lengthMismatch"); // V1
      byte = bytes[position++]!;
      if (index === maximumBytes - 1 && byte >= 0x80) fail("invalidContainer", CONTAINER.varTooLong); // V2
      const bits = byte & 0x7f;
      const scale = 2 ** (7 * index);
      if (bits !== 0 && (scale > Number.MAX_SAFE_INTEGER || value > Number.MAX_SAFE_INTEGER - bits * scale)) {
        fail("oversizedOutput");
      }
      value += bits * scale;
      if (byte < 0x80) {
        if (byte === 0) fail("invalidContainer", CONTAINER.varNotMinimal); // V3
        this.position = position;
        return value;
      }
    }
    return fail("invalidContainer", CONTAINER.varTooLong);
  }

  /** Count(min): `k > floor(remaining / min)` is `lengthMismatch`, with remaining measured after the Var. */
  public count(minimum: number): number {
    const value = this.varint();
    if (value > Math.floor((this.end - this.position) / minimum)) fail("lengthMismatch");
    return value;
  }

  /** Number(form) for forms 1 to 3; the caller handles form 0. */
  public number(form: number): number {
    if (form === 1) {
      const zigzag = this.varint(4);
      return (zigzag >>> 1) ^ -(zigzag & 1);
    }
    this.view ??= new DataView(this.bytes.buffer, this.bytes.byteOffset, this.bytes.byteLength);
    if (form === 2) {
      if (this.end - this.position < 4) fail("lengthMismatch");
      const value = this.view.getFloat32(this.position, true);
      this.position += 4;
      if (!Number.isFinite(value)) invalid(DETAIL.finite);
      if (Number.isInteger(value) && value >= INTEGER_MINIMUM && value <= INTEGER_MAXIMUM) {
        fail("invalidContainer", CONTAINER.numberForm);
      }
      return value;
    }
    if (this.end - this.position < 8) fail("lengthMismatch");
    const value = this.view.getFloat64(this.position, true);
    this.position += 8;
    if (!Number.isFinite(value)) invalid(DETAIL.finite);
    if ((Number.isInteger(value) && value >= INTEGER_MINIMUM && value <= INTEGER_MAXIMUM) || Math.fround(value) === value) {
      fail("invalidContainer", CONTAINER.numberForm);
    }
    return value;
  }

  /**
   * Str1 and Str2: the length against remaining, then against the limit. The payload bytes up to the end of the
   * string are charged to the budget before the string is scanned, so between two checks Phase S reads at most
   * 65,536 bytes, or one longer string (whose scan and decoding check again every 65,536 bytes). Decoding a scanned
   * string, comparing keys and the segment rules charge their own work.
   */
  public frame(limit: number): void {
    const length = this.varint();
    if (length > this.end - this.position) fail("lengthMismatch"); // Str1
    if (length > limit) fail("oversizedRecord"); // Str2
    const start = this.position;
    this.budget.spend(start + length - this.charged);
    this.charged = start + length;
    this.stringStart = start;
    this.stringLength = length;
    this.position = start + length;
  }

  /**
   * Str(scalar): Str1 to Str4, recording the escape count and the quote and ASCII flags of the bytes.
   *
   * A non-ASCII string is decoded, which validates it (Str3), when the reader validates or `decode` is true, and the
   * decoded string is returned; otherwise the result is null and the caller reads the ASCII bytes itself. The writer's
   * self-check does not re-validate values, whose bytes `TextEncoder` produced from well-formed strings (SPEC.md
   * 11.3.9, W4).
   */
  public scan(limit: number, decode: boolean): string | null {
    this.frame(limit);
    const bytes = this.bytes;
    const end = this.position;
    let high = false;
    let lineBreak = false;
    let escapes = 0;
    let quote = false;
    let index = this.stringStart;
    for (;;) {
      const blockEnd = end - index > CHUNK ? index + CHUNK : end;
      for (; index < blockEnd; index += 1) {
        const byte = bytes[index]!;
        if (byte < 0x28) {
          if (byte === 0x22) { escapes += 1; quote = true; } else if (byte === 0x27) quote = true;
          else if (byte === 0x0a || byte === 0x0d) lineBreak = true;
        } else if (byte >= 0x80) high = true;
        else if (byte === 0x5c) escapes += 1;
      }
      if (index >= end) break;
      checkCancellation(this.signal);
    }
    return this.finish(high, lineBreak, escapes, quote, decode);
  }

  /**
   * Str(scalar) for a key or the axis: `scan`, also recording in `keyFlags` the bytes that the key rules R2, R3 and
   * R9 look for anywhere in the string (A to Z, space or tab, `:` and `=`), so no rule reads the key again. A
   * non-ASCII key is always decoded and returned.
   */
  public scanKey(limit: number): string | null {
    this.frame(limit);
    const bytes = this.bytes;
    const end = this.position;
    let high = false;
    let lineBreak = false;
    let escapes = 0;
    let quote = false;
    let flags = 0;
    let index = this.stringStart;
    for (;;) {
      const blockEnd = end - index > CHUNK ? index + CHUNK : end;
      for (; index < blockEnd; index += 1) {
        const byte = bytes[index]!;
        if (byte < 0x41) {
          if (byte < 0x28) {
            if (byte === 0x22) { escapes += 1; quote = true; } else if (byte === 0x27) quote = true;
            else if (byte === 0x0a || byte === 0x0d) lineBreak = true;
            else if (byte === 0x20 || byte === 0x09) flags |= KEY_BLANK;
          } else if (byte === 0x3a) flags |= KEY_COLON;
          else if (byte === 0x3d) flags |= KEY_EQUALS;
        } else if (byte >= 0x80) high = true;
        else if (byte <= 0x5a) flags |= KEY_UPPER;
        else if (byte === 0x5c) escapes += 1;
      }
      if (index >= end) break;
      checkCancellation(this.signal);
    }
    this.keyFlags = flags;
    return this.finish(high, lineBreak, escapes, quote, true);
  }

  /** Str(scalar) for the axis: `scanKey`, then the string itself, an ASCII one built after its bytes are charged. */
  public axisText(limit: number): string {
    const text = this.scanKey(limit);
    if (text !== null) return text;
    this.budget.spend(this.stringLength);
    return asciiString(this.bytes, this.stringStart, this.position, this.signal);
  }

  /**
   * The end of `scan` and `scanKey`: records the flags, then Str3 (charged to the budget first) and Str4. A string
   * that is validated but not returned is decoded and dropped, chunk by chunk when it is long.
   */
  private finish(high: boolean, lineBreak: boolean, escapes: number, quote: boolean, decode: boolean): string | null {
    this.ascii = !high;
    this.escapes = escapes;
    this.quote = quote;
    let text: string | null = null;
    if (high && (decode || this.validate)) { // Str3
      this.budget.spend(this.stringLength);
      if (decode) text = decodeUTF8(this.bytes, this.stringStart, this.position, this.signal);
      else if (this.stringLength > CHUNK) validateUTF8(this.bytes, this.stringStart, this.position, this.signal);
      else buildUTF8(this.bytes, this.stringStart, this.position);
    }
    if (lineBreak) invalid(DETAIL.scalarBreak); // Str4
    return text;
  }

  /** Str(segment): Str1 to Str3. The caller applies the segment rules (Str4) to the decoded string. */
  public segment(limit: number): string {
    this.frame(limit);
    return this.stringLength === 0 ? "" : decodeUTF8(this.bytes, this.stringStart, this.position, this.signal);
  }
}

/**
 * Reads strings that the reader has already validated, for the result, the equivalence check and Phase Q. Every
 * string is charged to the decode's work budget, its Var included, before it is built by one native call: a string
 * longer than 65,536 bytes is then one native string construction of at most R bytes between two checks (SPEC.md
 * 11.3.13), and its charge leaves the budget in debt so the next string checks first.
 */
class StringWalker {
  public constructor(private readonly bytes: Uint8Array, public position: number, public readonly budget: WorkBudget) {}

  private length(): number {
    const bytes = this.bytes;
    let value = 0;
    let index = 0;
    let byte: number;
    do {
      byte = bytes[this.position++]!;
      value += (byte & 0x7f) * 2 ** (7 * index);
      index += 1;
    } while (byte >= 0x80);
    return value;
  }

  public next(): string {
    const from = this.position;
    const length = this.length();
    const start = this.position;
    const end = start + length;
    this.position = end;
    this.budget.spend(end - from);
    if (length <= SHORT_ASCII) {
      const bytes = this.bytes;
      let index = start;
      while (index < end && bytes[index]! < 0x80) index += 1;
      if (index === end) return asciiString(bytes, start, end);
    }
    return buildUTF8(this.bytes, start, end);
  }

  public skip(): void {
    const from = this.position;
    const length = this.length(); // advances past the Var first
    this.budget.spend(this.position - from);
    this.position += length;
  }
}

/**
 * S6b and P7a: two keys of one map with equal NFC forms (and different bytes) are `invalidDocument`. Each key is
 * charged twice to the decode's budget, once for its decoding and once for its normalization.
 */
function checkEquivalence(bytes: Uint8Array, position: number, count: number, budget: WorkBudget): void {
  const walker = new StringWalker(bytes, position, budget);
  const seen = new Set<string>();
  for (let index = 0; index < count; index += 1) {
    const from = walker.position;
    const key = walker.next();
    budget.spend(walker.position - from);
    const normal = key.normalize("NFC");
    walker.skip();
    if (seen.has(normal)) invalid(DETAIL.equivalent);
    seen.add(normal);
  }
}

/** Exact canonical text metrics (SPEC.md 11.3.7); `readStructured` fills them for tests when asked. */
export interface StructuredMetrics {
  textLength: number;
  lines: number;
  longestFrontmatterLine: number;
  directiveLengths: number[];
}

/**
 * Step D14 for payload kind 2: Phases S, L and Q over the DocumentRecord in `bytes[start ..< end]` (SPEC.md 11.3.8),
 * reporting the first failing check in that order.
 *
 * Phase S keeps keys and values as byte ranges and decodes only what a rule needs (non-ASCII keys, segments), so its
 * allocation stays a small constant factor of the payload. With `materialize` true (decoding) the result, the
 * plain-object shape of the 2.0 bounded decoder, is built by a second walk after Phases L and Q have passed. With
 * `materialize` false (the writer's self-check, W4) the same checks run without building a result or re-validating the
 * UTF-8 of values, and the result is null. `metrics`, for tests, receives the exact canonical text metrics.
 */
export function readStructured(bytes: Uint8Array, start: number, end: number, limits: DocumentDecodeLimits,
  materialize: boolean, signal?: AbortSignal, metrics?: StructuredMetrics): Document | null {
  const record = limits.maximumRecordBytes;
  const reader = new StructuredReader(bytes, start, end, materialize, signal);

  // MARK: Phase S, DocumentRecord (SPEC.md 11.3.5.1)
  const flags = reader.u8(); // S1
  if ((flags & 0xfc) !== 0) fail("invalidContainer", CONTAINER.documentFlags);
  const versionAt = reader.position; // S2
  reader.scan(record, false);
  if (reader.stringLength === 0) invalid(DETAIL.version);
  const versionQuoted = reader.stringLength + 2 + reader.escapes;
  const axis = reader.axisText(record); // S3
  const axisQuoted = reader.stringLength + 2 + reader.escapes;
  if (!axisIsNormalized(axis, reader.ascii, reader.keyFlags, reader.budget)) invalid(DETAIL.axis);
  const titleAt = (flags & 1) !== 0 ? reader.position : -1; // S4
  let titleQuoted = 0;
  if (titleAt >= 0) {
    reader.scan(record, false);
    titleQuoted = reader.stringLength + 2 + reader.escapes;
  }
  // Canonical text metrics (SPEC.md 11.3.7): T, Lines and the longest frontmatter line (L2 has a single code).
  let textLength = 4 + (6 + versionQuoted) + (7 + axisQuoted) + (titleAt >= 0 ? 8 + titleQuoted : 0) + 4;
  let lines = 5 + (titleAt >= 0 ? 1 : 0);
  let longestFrontmatter = Math.max(5 + versionQuoted, 6 + axisQuoted, titleAt >= 0 ? 7 + titleQuoted : 0);

  const metadataCount = reader.count(2); // S5
  const metadataAt = reader.position;
  lines += metadataCount;
  let nonASCIIKeys = false;
  let previousStart = 0;
  let previousEnd = 0;
  for (let index = 0; index < metadataCount; index += 1) { // S6
    const key = reader.scanKey(record);
    const keyStart = reader.stringStart;
    const keyEnd = reader.position;
    const keyLength = reader.stringLength;
    if (index > 0 && compareBytes(bytes, previousStart, previousEnd, keyStart, keyEnd, reader.budget) >= 0) {
      fail("invalidContainer", CONTAINER.keyOrder);
    }
    if (!metadataKeyIsValid(bytes, keyStart, keyEnd, key, reader.keyFlags)) invalid(DETAIL.metadataKey); // R3
    if (key !== null) nonASCIIKeys = true;
    reader.scan(record, false);
    const line = keyLength + 2 + reader.stringLength + 2 + reader.escapes;
    if (line > longestFrontmatter) longestFrontmatter = line;
    textLength += line + 1;
    previousStart = keyStart;
    previousEnd = keyEnd;
  }
  if (nonASCIIKeys) checkEquivalence(bytes, metadataAt, metadataCount, reader.budget); // S6b

  let preamble: string | null = null; // S7
  if ((flags & 2) !== 0) {
    preamble = reader.segment(record - 1);
    const preambleLength = reader.stringLength;
    const lineFeeds = checkSegment(preamble, true, false, reader.budget);
    textLength += 2 + preambleLength;
    lines += 2 + lineFeeds;
  }

  const planeCount = reader.count(4); // S8
  if (planeCount > limits.maximumPlanes) fail("tooManyPlanes");
  if ((flags & 2) !== 0 && planeCount === 0) invalid(DETAIL.preamblePlanes);

  // Count(4) and Pmax bound every allocation below; nothing is allocated per key or value.
  const zs = new Float64Array(planeCount);
  const xs = new Float64Array(planeCount); // NaN for an absent x; every stored coordinate is finite
  const ys = new Float64Array(planeCount);
  const directiveFixed = new Float64Array(planeCount); // DirLen without the form-2 and form-3 spellings
  const floatMask = new Uint8Array(planeCount); // bit 0: z, bit 1: x, bit 2: y in form 2 or 3
  const labelAt = new Int32Array(planeCount); // the label's Var, or -1
  const attributesAt = new Int32Array(planeCount); // the first attribute key's Var
  const attributeCounts = new Int32Array(planeCount);
  const bodies: string[] = [];
  const marked: number[] = [];
  let floatCount = 0;
  let directiveBound = 0; // the largest DirLen bound, with 24 bytes per form-2 or form-3 spelling

  // MARK: Phase S, PlaneRecord (SPEC.md 11.3.5.2)
  for (let index = 0; index < planeCount; index += 1) { // S9
    checkCancellation(signal);
    const planeFlags = reader.u8(); // P1
    const zForm = planeFlags & 3;
    const xForm = (planeFlags >>> 2) & 3;
    const yForm = (planeFlags >>> 4) & 3;
    if ((planeFlags & 0x80) !== 0 || zForm === 0) fail("invalidContainer", CONTAINER.planeFlags);
    let directive = 9;
    let mask = 0;
    const z = reader.number(zForm); // P2
    zs[index] = z;
    if (zForm === 1) directive += integerLength(z); else mask = 1;
    if (xForm !== 0) { // P3
      const x = reader.number(xForm);
      xs[index] = x;
      directive += 3;
      if (xForm === 1) directive += integerLength(x); else mask |= 2;
    } else xs[index] = NaN;
    if (yForm !== 0) { // P4
      const y = reader.number(yForm);
      ys[index] = y;
      directive += 3;
      if (yForm === 1) directive += integerLength(y); else mask |= 4;
    } else ys[index] = NaN;
    if ((planeFlags & 0x40) !== 0) { // P5
      labelAt[index] = reader.position;
      reader.scan(record, false);
      directive += 7 + reader.stringLength + 2 + reader.escapes;
    } else labelAt[index] = -1;
    const attributeCount = reader.count(3); // P6
    attributesAt[index] = reader.position;
    attributeCounts[index] = attributeCount;
    let anyQuote = false;
    let nonASCII = false;
    let keysValid = true; // R9 for every key, used only when no key holds a quote (P7b)
    for (let entry = 0; entry < attributeCount; entry += 1) { // P7
      const key = reader.scanKey(record);
      const keyStart = reader.stringStart;
      const keyEnd = reader.position;
      const keyLength = reader.stringLength;
      if (reader.quote) anyQuote = true;
      if (entry > 0 && compareBytes(bytes, previousStart, previousEnd, keyStart, keyEnd, reader.budget) >= 0) {
        fail("invalidContainer", CONTAINER.keyOrder);
      }
      if (key !== null) nonASCII = true;
      if (keysValid && !attributeKeyIsValid(bytes, keyStart, keyEnd, key, reader.keyFlags, reader.budget)) {
        keysValid = false;
      }
      reader.scan(record, false);
      directive += 2 + keyLength + reader.stringLength + 2 + reader.escapes;
      previousStart = keyStart;
      previousEnd = keyEnd;
    }
    if (nonASCII) checkEquivalence(bytes, attributesAt[index]!, attributeCount, reader.budget); // P7a
    if (anyQuote) marked.push(index); // P7b: Phase Q decides the plane
    else if (!keysValid) invalid(DETAIL.attributeKey);
    const body = reader.segment(record); // P8
    const bodyLength = reader.stringLength;
    const lineFeeds = checkSegment(body, false, index + 1 === planeCount, reader.budget);
    textLength += 2 + directive + (bodyLength > 0 ? bodyLength + 1 : 0);
    lines += bodyLength > 0 ? 3 + lineFeeds : 2;
    directiveFixed[index] = directive;
    floatMask[index] = mask;
    const floats = (mask & 1) + ((mask >>> 1) & 1) + ((mask >>> 2) & 1);
    floatCount += floats;
    const bound = directive + NUMBER_BOUND * floats;
    if (bound > directiveBound) directiveBound = bound;
    if (materialize) bodies.push(body);
  }
  if (reader.position !== end) fail("lengthMismatch"); // S10

  // MARK: Phase L (SPEC.md 11.3.8)
  checkCancellation(signal);
  const spelled = (index: number): number => {
    const mask = floatMask[index]!;
    let length = 0;
    if ((mask & 1) !== 0) length += canonicalNumber(zs[index]!).length;
    if ((mask & 2) !== 0) length += canonicalNumber(xs[index]!).length;
    if ((mask & 4) !== 0) length += canonicalNumber(ys[index]!).length;
    return length;
  };
  if (planeCount > 1) checkUniquePositions(zs); // L0
  if (record < 3 || longestFrontmatter > record) fail("oversizedRecord"); // L1, L2
  if (directiveBound > record) { // L3, formatting numbers only where the bound cannot decide
    for (let index = 0; index < planeCount; index += 1) {
      if ((index & 0x3ff) === 0x3ff) checkCancellation(signal);
      const fixed = directiveFixed[index]!;
      if (fixed > record) fail("oversizedRecord");
      if (floatMask[index] !== 0 && fixed + NUMBER_BOUND * 3 > record && fixed + spelled(index) > record) {
        fail("oversizedRecord");
      }
    }
  }
  const decodedLimit = limits.maximumDecodedBytes;
  if (textLength + NUMBER_BOUND * floatCount > decodedLimit) { // L4
    if (textLength + floatCount > decodedLimit) fail("oversizedOutput");
    checkCancellation(signal);
    let exact = textLength;
    for (let index = 0; index < planeCount; index += 1) {
      if ((index & 0x3ff) === 0x3ff) checkCancellation(signal);
      if (floatMask[index] !== 0) exact += spelled(index);
    }
    if (exact > decodedLimit) fail("oversizedOutput");
  }
  if (lines > limits.maximumLines) fail("tooManyLines"); // L5
  if (metrics !== undefined) {
    metrics.directiveLengths = Array.from(directiveFixed, (fixed, index) => fixed + spelled(index));
    metrics.textLength = metrics.directiveLengths.reduce((sum, length, index) => sum + length - directiveFixed[index]!,
      textLength);
    metrics.lines = lines;
    metrics.longestFrontmatterLine = longestFrontmatter;
  }

  // MARK: Phase Q (SPEC.md 11.3.6.6)
  const walker = new StringWalker(bytes, 0, reader.budget);
  const attributeKeys: string[] = [];
  const attributeValues: string[] = [];
  for (let slot = 0; slot < marked.length; slot += 1) {
    const index = marked[slot]!;
    // The plane's strings are charged to the decode's budget; a check runs right before and right after the parse.
    let label: string | null = null;
    if (labelAt[index]! >= 0) {
      walker.position = labelAt[index]!;
      label = walker.next();
    }
    walker.position = attributesAt[index]!;
    const count = attributeCounts[index]!;
    attributeKeys.length = 0;
    attributeValues.length = 0;
    for (let entry = 0; entry < count; entry += 1) {
      attributeKeys.push(walker.next());
      attributeValues.push(walker.next());
    }
    const x = xs[index]!;
    const y = ys[index]!;
    checkCancellation(signal);
    directiveRoundTrip(zs[index]!, Number.isNaN(x) ? null : x, Number.isNaN(y) ? null : y, label, attributeKeys,
      attributeValues, 0, count);
    checkCancellation(signal);
  }
  if (!materialize) return null;

  // MARK: Result, built by a second walk once every check has passed. Every string and every plane is charged to the
  // decode's budget, so a map of any size or a run of planes without strings still reaches a check.
  walker.position = versionAt;
  const version = walker.next();
  let title: string | null = null;
  if (titleAt >= 0) {
    walker.position = titleAt;
    title = walker.next();
  }
  const metadata: Record<string, string> = Object.create(null);
  walker.position = metadataAt;
  for (let index = 0; index < metadataCount; index += 1) {
    const key = walker.next();
    metadata[key] = walker.next();
  }
  const planes: Plane[] = [];
  for (let index = 0; index < planeCount; index += 1) {
    reader.budget.spend(PLANE_COST);
    let label: string | null = null;
    if (labelAt[index]! >= 0) {
      walker.position = labelAt[index]!;
      label = walker.next();
    }
    const attributes: Record<string, string> = Object.create(null);
    walker.position = attributesAt[index]!;
    for (let entry = attributeCounts[index]!; entry > 0; entry -= 1) {
      const key = walker.next();
      attributes[key] = walker.next();
    }
    const x = xs[index]!;
    const y = ys[index]!;
    planes.push({ z: zs[index]!, label, x: Number.isNaN(x) ? null : x, y: Number.isNaN(y) ? null : y, attributes,
      body: bodies[index]! });
  }
  checkCancellation(signal);
  return { version, axis, title, metadata, preamble, planes };
}


// MARK: - Writer (SPEC.md 11.3.9)

/** The canonical number form of SPEC.md 11.3.3: 1 integer, 2 binary32, 3 binary64. NaN takes 3 and infinities 2. */
export function numberForm(value: number): number {
  if (Number.isInteger(value) && value >= INTEGER_MINIMUM && value <= INTEGER_MAXIMUM) return 1;
  return Math.fround(value) === value ? 2 : 3;
}

/** Bytes of a minimal Var. Any safe integer fits in at most 8 bytes. */
function varByteCount(value: number): number {
  let count = 1;
  let rest = value;
  while (rest >= 0x80) {
    rest = Math.floor(rest / 128);
    count += 1;
  }
  return count;
}

/**
 * Whether a map holds two canonically equivalent keys. All-ASCII maps never do. Each key costs one entry, its ASCII
 * test is charged in blocks, and its normalization as one native piece.
 */
function hasEquivalentKeys(entries: readonly [string, string][], budget: WorkBudget): boolean {
  let nonASCII = false;
  for (let index = 0; index < entries.length && !nonASCII; index += 1) {
    budget.spend(ENTRY_COST);
    nonASCII = !isASCII(entries[index]![0], budget);
  }
  if (!nonASCII) return false;
  const seen = new Set<string>();
  for (const [key] of entries) {
    budget.spend(ENTRY_COST + key.length);
    const normal = key.normalize("NFC");
    if (seen.has(normal)) return true;
    seen.add(normal);
  }
  return false;
}

/** W2 (TypeScript): merges equivalent keys as the 2.0 `canonicalStrings` does, first spelling and last value. */
function mergedEntries(entries: readonly [string, string][], budget: WorkBudget): [string, string][] {
  const values = new Map<string, string>();
  const spellings = new Map<string, string>();
  for (const [key, value] of entries) {
    budget.spend(ENTRY_COST + key.length);
    const normal = key.normalize("NFC");
    const spelling = spellings.get(normal) ?? key;
    if (!spellings.has(normal)) spellings.set(normal, key);
    values.set(spelling, value);
  }
  return [...values.entries()];
}

/**
 * Sorts entries by key in code point order. Each comparison charges one unit, then the shared prefix of the two keys
 * (the most it can read) in blocks, so a sort of any size, or of any key length, reaches a cancellation check; a
 * cancelled sort only leaves this function's own array in an unspecified order.
 */
function sortEntries(entries: [string, string][], budget: WorkBudget): [string, string][] {
  return entries.sort((left, right) => compareEntries(left[0], right[0], budget));
}

/**
 * A map's entries in `Object.entries` order; `Object.keys` measured several times faster on null-prototype maps. The
 * single `Object.keys` call is native and proportional to the caller's map; the copy is charged per entry.
 */
function entriesOf(map: Readonly<Record<string, string>>, budget: WorkBudget): [string, string][] {
  const keys = Object.keys(map);
  const entries = new Array<[string, string]>(keys.length);
  for (let index = 0; index < keys.length; index += 1) {
    budget.spend(ENTRY_COST);
    const key = keys[index]!;
    entries[index] = [key, map[key]!];
  }
  return entries;
}

let nonASCIIPattern: RegExp | null = null;

/**
 * The strings of a payload in emission order with their UTF-8 lengths, and the running payload size. Every string
 * is charged to the plan's work budget before it is scanned.
 */
class PayloadPlan extends WorkBudget {
  /** Each Str as its string, or as its UTF-8 bytes when the plan already encoded it. */
  public readonly strings: (string | Uint8Array)[] = [];
  public readonly lengths: number[] = [];
  public size = 0;

  /**
   * Adds one Str; a lone surrogate is `invalidDocument`, never a U+FFFD substitution. An all-ASCII string (checked by
   * the engine's regular expression scan) has its own length in bytes. Any other string is checked with
   * `isWellFormed` and encoded once by `TextEncoder`, or, where `isWellFormed` is missing, measured by the portable
   * `utf8Length` scan, which also rejects lone surrogates.
   */
  public string(text: string): void {
    if (typeof text !== "string") throw new TypeError("Document strings must be strings.");
    nonASCIIPattern ??= /[^\u0000-\u007f]/;
    let item: string | Uint8Array = text;
    let length = text.length;
    this.spend(ENTRY_COST + length);
    if (nonASCIIPattern.test(text)) {
      // Two more passes: the well-formedness check and the encoding.
      this.spend(2 * length);
      if (typeof text.isWellFormed === "function") {
        if (!text.isWellFormed()) invalid(DETAIL.unicode);
        item = encoder().encode(text);
        length = item.byteLength;
      } else {
        try { length = utf8Length(text, this.signal); } catch (error) {
          if (error instanceof InvalidUnicodeError) invalid(DETAIL.unicode);
          throw error;
        }
      }
    }
    this.strings.push(item);
    this.lengths.push(length);
    this.size += varByteCount(length) + length;
  }
}

/**
 * Steps W2 to W4 of `encode(document, .binary(compression), limits)` (SPEC.md 11.3.9): normalizes the document as the
 * 2.0 TypeScript text writer does, emits its DocumentRecord after a 40-byte gap for the header, and runs the reader's
 * Phases S, L and Q over the emitted payload. The caller has already validated the limits (W1) and checked
 * `maximumEncodedBytes >= 40` (W1b); it writes the header and the checksum (W6).
 * @returns The container buffer: bytes `0 ..< 40` are zero, the payload fills the rest.
 */
export function writeStructuredPayload(document: Document, limits: DocumentDecodeLimits, signal?: AbortSignal): Uint8Array {
  // W2: read the document once into a plan, so the emitted bytes match the computed sizes exactly. The plan's work
  // budget also covers the merge test of every map, the sorts and the emission (SPEC.md 11.3.13).
  const plan = new PayloadPlan(signal);
  const planes = [...document.planes];
  const metadataSource = entriesOf(document.metadata, plan);
  const metadataMerges = hasEquivalentKeys(metadataSource, plan);
  const attributeSources = new Array<[string, string][]>(planes.length);
  const attributeMerges = new Array<boolean>(planes.length);
  let anyMerges = metadataMerges;
  for (let index = 0; index < planes.length; index += 1) {
    plan.spend(PLANE_COST);
    const entries = entriesOf(planes[index]!.attributes, plan);
    const merges = hasEquivalentKeys(entries, plan);
    attributeSources[index] = entries;
    attributeMerges[index] = merges;
    if (merges) anyMerges = true;
  }
  if (anyMerges) {
    // The 2.0 validateRecords check on the unmerged input, so that lone surrogates and record limits in the
    // spellings and values the merge drops still fail as they do in the 2.0 validate.
    try { validateRecords(document, limits, signal); } catch (error) {
      if (error instanceof InvalidUnicodeError) invalid(DETAIL.unicode);
      throw error;
    }
  }
  const order = (entries: [string, string][], merges: boolean): [string, string][] => {
    const result = merges ? mergedEntries(entries, plan) : entries;
    return result.length > 1 ? sortEntries(result, plan) : result;
  };

  const title = document.title;
  const preamble = document.preamble;
  const documentFlags = (title !== null ? 1 : 0) | (preamble !== null ? 2 : 0);
  plan.size += 1;
  plan.string(document.version);
  plan.string(document.axis);
  if (title !== null) plan.string(title);
  const metadata = order(metadataSource, metadataMerges);
  plan.size += varByteCount(metadata.length);
  for (const [key, value] of metadata) { plan.string(key); plan.string(value); }
  if (preamble !== null) plan.string(preamble);
  const planeCount = planes.length;
  plan.size += varByteCount(planeCount);
  const coordinates = new Float64Array(3 * planeCount);
  const planeFlags = new Uint8Array(planeCount);
  const attributeCounts = new Uint32Array(planeCount);
  for (let index = 0; index < planeCount; index += 1) {
    checkCancellation(signal);
    const plane = planes[index]!;
    // -0 becomes +0; non-finite values are emitted with the same form tests and rejected by the self-check (W4).
    const z = plane.z === 0 ? 0 : plane.z;
    const x = plane.x === null ? null : plane.x === 0 ? 0 : plane.x;
    const y = plane.y === null ? null : plane.y === 0 ? 0 : plane.y;
    const label = plane.label;
    const zForm = numberForm(z);
    const xForm = x === null ? 0 : numberForm(x);
    const yForm = y === null ? 0 : numberForm(y);
    planeFlags[index] = zForm | (xForm << 2) | (yForm << 4) | (label !== null ? 0x40 : 0);
    coordinates[3 * index] = z;
    plan.size += 1 + (zForm === 1 ? varByteCount(zigzag(z)) : zForm === 2 ? 4 : 8);
    if (x !== null) {
      coordinates[3 * index + 1] = x;
      plan.size += xForm === 1 ? varByteCount(zigzag(x)) : xForm === 2 ? 4 : 8;
    }
    if (y !== null) {
      coordinates[3 * index + 2] = y;
      plan.size += yForm === 1 ? varByteCount(zigzag(y)) : yForm === 2 ? 4 : 8;
    }
    if (label !== null) plan.string(label);
    const attributes = order(attributeSources[index]!, attributeMerges[index]!);
    attributeCounts[index] = attributes.length;
    plan.size += varByteCount(attributes.length);
    for (const [key, value] of attributes) { plan.string(key); plan.string(value); }
    plan.string(plane.body);
  }

  // W3: the payload is capped at Emax - 40 bytes; nothing is allocated past the cap.
  const capacity = limits.maximumEncodedBytes - 40;
  if (plan.size > capacity) fail("oversizedInput");
  const output = new Uint8Array(40 + plan.size);
  const view = new DataView(output.buffer);
  const strings = plan.strings;
  const lengths = plan.lengths;
  let position = 40;
  let next = 0;
  const writeVar = (value: number): void => {
    let rest = value;
    while (rest >= 0x80) {
      output[position++] = (rest % 128) + 128;
      rest = Math.floor(rest / 128);
    }
    output[position++] = rest;
  };
  const writeString = (): void => {
    const item = strings[next]!;
    const length = lengths[next]!;
    next += 1;
    plan.spend(ENTRY_COST + length);
    writeVar(length);
    if (typeof item !== "string") output.set(item, position);
    else if (length === item.length && length <= SHORT_WRITE) { // ASCII
      for (let index = 0; index < length; index += 1) output[position + index] = item.charCodeAt(index);
    } else {
      // Exactly `length` bytes: an ASCII string, or a well-formed one that utf8Length measured.
      encoder().encodeInto(item, output.subarray(position, position + length));
    }
    position += length;
  };
  const writeNumber = (value: number, form: number): void => {
    if (form === 1) writeVar(zigzag(value));
    else if (form === 2) { view.setFloat32(position, value, true); position += 4; } else {
      view.setFloat64(position, value, true);
      position += 8;
    }
  };
  output[position++] = documentFlags;
  writeString();
  writeString();
  if (title !== null) writeString();
  writeVar(metadata.length);
  for (let index = 0; index < metadata.length; index += 1) { writeString(); writeString(); }
  if (preamble !== null) writeString();
  writeVar(planeCount);
  for (let index = 0; index < planeCount; index += 1) {
    checkCancellation(signal);
    const flags = planeFlags[index]!;
    output[position++] = flags;
    writeNumber(coordinates[3 * index]!, flags & 3);
    if ((flags & 0x0c) !== 0) writeNumber(coordinates[3 * index + 1]!, (flags >>> 2) & 3);
    if ((flags & 0x30) !== 0) writeNumber(coordinates[3 * index + 2]!, (flags >>> 4) & 3);
    if ((flags & 0x40) !== 0) writeString();
    const count = attributeCounts[index]!;
    writeVar(count);
    for (let entry = 0; entry < count; entry += 1) { writeString(); writeString(); }
    writeString();
  }

  // W4: the reader's own Phases S, L and Q over the emitted payload, under the same limits. The check separates the
  // emission's work budget from the reader's.
  checkCancellation(signal);
  readStructured(output, 40, output.byteLength, limits, false, signal);
  return output;
}

/** The zigzag encoding of an integer-form value. */
function zigzag(value: number): number {
  return ((value << 1) ^ (value >> 31)) >>> 0;
}
