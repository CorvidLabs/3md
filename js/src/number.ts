// Canonical number spelling shared by the parser's serializer, storage text and the structured payload metrics.
//
// A pure module with no imports and no top-level side effects, so the parser can use it without pulling the storage
// layer into a bundle that only needs `parse` (SPEC.md 11.3.7, the element bundle invariant).

/**
 * Spells a finite coordinate exactly as the Swift `Double` description does in canonical 3md text: integral values
 * below 10^15 as integers; values below 1e-4 or above 2^53 in shortest round-trip scientific notation with an explicit
 * exponent sign and at least two exponent digits; every other value in shortest round-trip decimal notation, with
 * `.0` appended to integral values.
 * @param value A finite number.
 * @returns The canonical spelling, 1 to 24 bytes.
 */
export function canonicalNumber(value: number): string {
  if (Number.isInteger(value) && Math.abs(value) < 1e15) return String(value);
  const magnitude = Math.abs(value);
  if (magnitude !== 0 && (magnitude < 1e-4 || magnitude > 9007199254740992)) {
    const [mantissa = "", exponent = "0"] = value.toExponential().split("e");
    const sign = exponent.startsWith("-") ? "-" : "+";
    const digits = exponent.replace(/^[+-]/, "").padStart(2, "0");
    return `${mantissa}e${sign}${digits}`;
  }
  const result = String(value);
  return Number.isInteger(value) ? `${result}.0` : result;
}
