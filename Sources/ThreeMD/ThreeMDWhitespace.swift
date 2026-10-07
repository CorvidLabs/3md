// MARK: - ThreeMDWhitespace

/// The frozen whitespace set W of SPEC 11.3.6 and scalar-wise trimming.
///
/// W holds exactly 19 scalars: U+0009, U+0020, U+00A0, U+1680, the 12 scalars U+2000 to U+200B, U+202F, U+205F and
/// U+3000. Text parsing, validation and serialization trim and test blank lines with W instead of the platform's
/// `CharacterSet.whitespaces`, so their results never depend on Foundation's character tables. On Darwin the two
/// sets are equal; non-Darwin Foundation builds can differ (for example at U+200B).
internal enum ThreeMDWhitespace {
    // MARK: - Membership

    /// Returns whether a scalar value belongs to W.
    /// - Parameter value: A Unicode scalar value.
    /// - Returns: `true` for the 19 scalars of W.
    @inline(__always)
    internal static func contains(_ value: UInt32) -> Bool {
        switch value {
        case 0x09, 0x20, 0xA0, 0x1680, 0x2000...0x200B, 0x202F, 0x205F, 0x3000: return true
        default: return false
        }
    }

    /// Returns whether a scalar belongs to W.
    /// - Parameter scalar: A Unicode scalar.
    /// - Returns: `true` for the 19 scalars of W.
    @inline(__always)
    internal static func contains(_ scalar: Unicode.Scalar) -> Bool {
        contains(scalar.value)
    }

    // MARK: - Trimming

    /// Removes leading and trailing W scalars, one scalar at a time.
    /// - Parameter value: The text to trim.
    /// - Returns: `value` without W at either end; `value` itself when nothing is trimmed.
    internal static func trimmed(_ value: String) -> String {
        let scalars = value.unicodeScalars
        let range = trimmedRange(of: scalars)
        guard range.lowerBound != scalars.startIndex || range.upperBound != scalars.endIndex else { return value }
        return String(scalars[range])
    }

    /// Removes leading and trailing W scalars, one scalar at a time.
    /// - Parameter value: The text to trim.
    /// - Returns: A new string without W at either end.
    internal static func trimmed(_ value: Substring) -> String {
        let scalars = value.unicodeScalars
        return String(scalars[trimmedRange(of: scalars)])
    }

    /// Returns whether every scalar of a line is in W. The empty line is blank.
    /// - Parameter value: The line to test.
    /// - Returns: `true` when the line holds only W scalars.
    internal static func isBlank(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { contains($0) }
    }

    /// Returns whether every scalar of a line is in W. The empty line is blank.
    /// - Parameter value: The line to test.
    /// - Returns: `true` when the line holds only W scalars.
    internal static func isBlank(_ value: Substring) -> Bool {
        value.unicodeScalars.allSatisfy { contains($0) }
    }

    // MARK: - UTF-8

    /// Returns the byte length of the W scalar that starts at `offset`, or 0 when none does.
    ///
    /// The bytes must be well-formed UTF-8, so a lead byte always starts a scalar.
    /// - Parameters:
    ///   - bytes: The UTF-8 bytes.
    ///   - offset: The scalar start to test.
    ///   - end: The exclusive end of the readable bytes.
    /// - Returns: 1, 2 or 3 for a W scalar, otherwise 0.
    @inline(__always)
    internal static func leadingLength(_ bytes: UnsafePointer<UInt8>, at offset: Int, end: Int) -> Int {
        let first = bytes[offset]
        if first == 0x09 || first == 0x20 { return 1 }
        if first == 0xC2 { return offset + 1 < end && bytes[offset + 1] == 0xA0 ? 2 : 0 }
        guard first >= 0xE1, first <= 0xE3, offset + 2 < end else { return 0 }
        return isThreeByteMember(first, bytes[offset + 1], bytes[offset + 2]) ? 3 : 0
    }

    /// Returns the byte length of the W scalar that ends just before `end`, or 0 when none does.
    ///
    /// The bytes must be well-formed UTF-8, so the trailing bytes of a W encoding always form the last scalar.
    /// - Parameters:
    ///   - bytes: The UTF-8 bytes.
    ///   - start: The inclusive start of the readable bytes.
    ///   - end: The exclusive end of the scalar to test.
    /// - Returns: 1, 2 or 3 for a W scalar, otherwise 0.
    @inline(__always)
    internal static func trailingLength(_ bytes: UnsafePointer<UInt8>, start: Int, end: Int) -> Int {
        guard end > start else { return 0 }
        let last = bytes[end - 1]
        if last == 0x09 || last == 0x20 { return 1 }
        if last == 0xA0, end - 2 >= start, bytes[end - 2] == 0xC2 { return 2 }
        guard end - 3 >= start else { return 0 }
        return isThreeByteMember(bytes[end - 3], bytes[end - 2], last) ? 3 : 0
    }

    // MARK: - Private Methods

    @inline(__always)
    private static func isThreeByteMember(_ first: UInt8, _ second: UInt8, _ third: UInt8) -> Bool {
        switch (first, second) {
        case (0xE1, 0x9A): return third == 0x80
        case (0xE2, 0x80): return (0x80...0x8B).contains(third) || third == 0xAF
        case (0xE2, 0x81): return third == 0x9F
        case (0xE3, 0x80): return third == 0x80
        default: return false
        }
    }

    private static func trimmedRange<Scalars: BidirectionalCollection>(
        of scalars: Scalars
    ) -> Range<Scalars.Index> where Scalars.Element == Unicode.Scalar {
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, contains(scalars[start]) { start = scalars.index(after: start) }
        while start < end {
            let previous = scalars.index(before: end)
            guard contains(scalars[previous]) else { break }
            end = previous
        }
        return start..<end
    }
}
