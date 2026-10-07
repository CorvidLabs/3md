// CRC-32/ISO-HDLC for the version 1 binary container (SPEC.md 11.1), shared by payload kinds 1 and 2.
//
// Reflected polynomial 0xEDB88320, initial value 0xFFFFFFFF, final XOR 0xFFFFFFFF; check value 0xCBF43926 for ASCII
// "123456789". The loop consumes 16 bytes per step (slicing-by-16) over sixteen 256-entry tables. On little-endian
// hosts the 16 bytes are read as four aligned 32-bit words; otherwise, and for an unaligned head or a short tail, byte
// by byte. Both paths compute the same value. The tables are built lazily on first use, so the module has no top-level
// side effects and stays out of bundles that never compute a CRC.

import { checkCancellation } from "./portable.js";

/** Payload bytes processed between two cancellation checks (SPEC.md 11.3.13). */
const CANCELLATION_STRIDE = 65_536;

let tables: Int32Array | null = null;
let littleEndian = false;

/** Table `k` holds the CRC contribution of a byte followed by `k` zero bytes. */
function crcTables(): Int32Array {
  if (tables !== null) return tables;
  const table = new Int32Array(16 * 256);
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) value = (value & 1) !== 0 ? (value >>> 1) ^ 0xedb88320 : value >>> 1;
    table[index] = value;
  }
  for (let index = 0; index < 256; index += 1) {
    let value = table[index]!;
    for (let slice = 1; slice < 16; slice += 1) {
      value = (value >>> 8) ^ table[value & 0xff]!;
      table[slice * 256 + index] = value;
    }
  }
  littleEndian = new Uint8Array(new Uint32Array([1]).buffer)[0] === 1;
  tables = table;
  return table;
}

/**
 * Advances a running CRC register over `bytes[start ..< end]`. The register is the raw (not yet final-XORed) state,
 * `-1` for a fresh computation; the result is a signed 32-bit integer.
 */
export function crc32Update(crc: number, bytes: Uint8Array, start: number, end: number): number {
  const t = crcTables();
  if (!littleEndian || end - start < 64) return crc32UpdateBytes(crc, bytes, start, end);
  let value = crc | 0;
  let index = start;
  while (((bytes.byteOffset + index) & 3) !== 0) {
    value = (value >>> 8) ^ t[(value ^ bytes[index]!) & 0xff]!;
    index += 1;
  }
  const blocks = (end - index) >>> 4;
  const words = new Int32Array(bytes.buffer, bytes.byteOffset + index, blocks * 4);
  for (let word = 0; word < words.length; word += 4) {
    const a = words[word]! ^ value;
    const b = words[word + 1]!;
    const c = words[word + 2]!;
    const d = words[word + 3]!;
    value = t[3840 + (a & 0xff)]! ^ t[3584 + ((a >>> 8) & 0xff)]! ^ t[3328 + ((a >>> 16) & 0xff)]! ^ t[3072 + (a >>> 24)]! ^
      t[2816 + (b & 0xff)]! ^ t[2560 + ((b >>> 8) & 0xff)]! ^ t[2304 + ((b >>> 16) & 0xff)]! ^ t[2048 + (b >>> 24)]! ^
      t[1792 + (c & 0xff)]! ^ t[1536 + ((c >>> 8) & 0xff)]! ^ t[1280 + ((c >>> 16) & 0xff)]! ^ t[1024 + (c >>> 24)]! ^
      t[768 + (d & 0xff)]! ^ t[512 + ((d >>> 8) & 0xff)]! ^ t[256 + ((d >>> 16) & 0xff)]! ^ t[d >>> 24]!;
  }
  return crc32UpdateBytes(value, bytes, index + blocks * 16, end);
}

/** The byte-load path of `crc32Update`, for short ranges and big-endian hosts. Exported for tests. */
export function crc32UpdateBytes(crc: number, bytes: Uint8Array, start: number, end: number): number {
  const t = crcTables();
  let value = crc | 0;
  let index = start;
  for (; index + 16 <= end; index += 16) {
    const a = (bytes[index]! | (bytes[index + 1]! << 8) | (bytes[index + 2]! << 16) | (bytes[index + 3]! << 24)) ^ value;
    const b = bytes[index + 4]! | (bytes[index + 5]! << 8) | (bytes[index + 6]! << 16) | (bytes[index + 7]! << 24);
    const c = bytes[index + 8]! | (bytes[index + 9]! << 8) | (bytes[index + 10]! << 16) | (bytes[index + 11]! << 24);
    const d = bytes[index + 12]! | (bytes[index + 13]! << 8) | (bytes[index + 14]! << 16) | (bytes[index + 15]! << 24);
    value = t[3840 + (a & 0xff)]! ^ t[3584 + ((a >>> 8) & 0xff)]! ^ t[3328 + ((a >>> 16) & 0xff)]! ^ t[3072 + (a >>> 24)]! ^
      t[2816 + (b & 0xff)]! ^ t[2560 + ((b >>> 8) & 0xff)]! ^ t[2304 + ((b >>> 16) & 0xff)]! ^ t[2048 + (b >>> 24)]! ^
      t[1792 + (c & 0xff)]! ^ t[1536 + ((c >>> 8) & 0xff)]! ^ t[1280 + ((c >>> 16) & 0xff)]! ^ t[1024 + (c >>> 24)]! ^
      t[768 + (d & 0xff)]! ^ t[512 + ((d >>> 8) & 0xff)]! ^ t[256 + ((d >>> 16) & 0xff)]! ^ t[d >>> 24]!;
  }
  for (; index < end; index += 1) value = (value >>> 8) ^ t[(value ^ bytes[index]!) & 0xff]!;
  return value;
}

/**
 * The CRC-32/ISO-HDLC of a complete byte string.
 * @param bytes The input.
 * @returns The checksum as an unsigned 32-bit integer.
 */
export function crc32(bytes: Uint8Array): number {
  return (crc32Update(-1, bytes, 0, bytes.byteLength) ^ -1) >>> 0;
}

/**
 * The container checksum: header bytes `0 ..< 36`, then the encoded payload `40 ..< end`. Cancellation is checked
 * before every 65,536 payload bytes and after the last.
 *
 * With `copy`, the container is first copied into it, the header and then each 65,536-byte stride just before that
 * stride is checksummed, and the checksum is computed over the copy. The bytes checked are then exactly the bytes a
 * caller later reads from `copy`, whatever happens to `container` meanwhile (SPEC.md 11.3.16: a caller buffer is
 * copied or read once).
 * @param container The header and payload; `container.byteLength` must be at least 40.
 * @param signal Optional cancellation.
 * @param copy Optional private buffer of the container's length that receives the container's bytes.
 * @returns The checksum as an unsigned 32-bit integer.
 */
export function containerChecksum(container: Uint8Array, signal?: AbortSignal, copy?: Uint8Array): number {
  const end = container.byteLength;
  let source = container;
  if (copy !== undefined) {
    copy.set(container.subarray(0, 40));
    source = copy;
  }
  let value = crc32Update(-1, source, 0, 36);
  for (let start = 40; start < end; start += CANCELLATION_STRIDE) {
    checkCancellation(signal);
    const stop = Math.min(start + CANCELLATION_STRIDE, end);
    if (copy !== undefined) copy.set(container.subarray(start, stop), start);
    value = crc32Update(value, source, start, stop);
  }
  checkCancellation(signal);
  return (value ^ -1) >>> 0;
}
