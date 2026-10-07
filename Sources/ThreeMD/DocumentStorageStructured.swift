import Foundation

// MARK: - DocumentStorageStructured

/// Payload kind 2 of the version 1 container: the structured document payload of SPEC 11.3.
///
/// The reader runs Phase S (structure and fields), Phase L (limits from the exact canonical text metrics) and Phase Q
/// (the directive round trip for keys that contain quotes) over one forward cursor, and builds the `Document` only
/// after all three passed. The writer emits the canonical encoding and then runs the same reader over its own bytes.
internal enum DocumentStorageStructured {
    // MARK: - Properties

    /// The smallest integer-form coordinate, -2^27.
    internal static let integerMinimum: Double = -134_217_728
    /// The largest integer-form coordinate, 2^27 - 1.
    internal static let integerMaximum: Double = 134_217_727
    /// Bytes scanned or validated between two cancellation checks (SPEC 11.3.13).
    internal static let block = 65_536

    // MARK: - Internal Methods

    /// Step D14 for kind 2: decodes a complete uncompressed payload after the container checks passed.
    /// - Parameters:
    ///   - payload: The uncompressed payload bytes `P[0 ..< n]`.
    ///   - limits: The caller's storage policy.
    /// - Returns: The decoded document, equal to the bounded text decode of its canonical text.
    /// - Throws: `DocumentStorageError` in the precedence of SPEC 11.3.8, or `CancellationError` where supported.
    internal static func decode(_ payload: UnsafeRawBufferPointer, limits: DocumentDecodeLimits) throws -> Document {
        try DocumentStorageCancellation.check()
        var reader = try StructuredReader(payload, limits: limits, decoding: true)
        guard let document = try reader.read() else { throw DocumentStorageError.invalidContainer }
        try DocumentStorageCancellation.check()
        return document
    }

    /// Writes `.binary(compression:)`: steps W1 to W6 of SPEC 11.3.9.
    /// - Parameters:
    ///   - document: The document to store.
    ///   - compression: The container compression identifier.
    ///   - limits: The storage policy; the uncompressed container must fit `maximumEncodedBytes`.
    /// - Returns: The complete kind-2 container.
    /// - Throws: `DocumentStorageError` (the reader's codes from the self-check), or `CancellationError`.
    internal static func encode(
        _ document: Document,
        compression: DocumentCompression,
        limits: DocumentDecodeLimits
    ) throws -> Data {
        try DocumentStorageCancellation.check()
        let header = DocumentStorageCodec.headerByteCount
        guard limits.maximumEncodedBytes >= header else { throw DocumentStorageError.oversizedInput }
        var writer = StructuredWriter(capacity: limits.maximumEncodedBytes, estimate: estimate(document))
        try writer.emit(document)
        var bytes = writer.bytes
        try bytes.withUnsafeBytes { raw in
            var reader = try StructuredReader(
                UnsafeRawBufferPointer(rebasing: raw[header...]),
                limits: limits,
                decoding: false
            )
            _ = try reader.read()
        }
        let payloadCount = bytes.count - header
        switch compression {
        case .none:
            var fields = DocumentStorageCodec.magic
            // Container version 1, payload kind 2, compression 0, flags 0, reserved 0.
            let kind = DocumentPayloadKind.structuredDocument.rawValue
            fields.append(contentsOf: [1, 0, kind, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            withUnsafeBytes(of: UInt64(payloadCount).littleEndian) { fields.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt64(payloadCount).littleEndian) { fields.append(contentsOf: $0) }
            bytes.replaceSubrange(0..<36, with: fields)
            let checksum = try bytes.withUnsafeBytes { try DocumentStorageChecksum.containerChecksum($0) }
            withUnsafeBytes(of: checksum.littleEndian) { bytes.replaceSubrange(36..<40, with: $0) }
            try DocumentStorageCancellation.check()
            return Data(bytes)
        case .lzfse:
            let compressed = try DocumentStorageCompression.encode(
                Data(bytes[header...]),
                compression: .lzfse,
                maximumBytes: limits.maximumEncodedBytes - header
            )
            return try DocumentStorageCodec.container(
                kind: .structuredDocument,
                compression: .lzfse,
                payload: compressed,
                decodedByteCount: payloadCount
            )
        }
    }

    /// Reads a Var (unsigned LEB128, 1 to 4 bytes, minimal) at `position` and moves past it (V1 to V3).
    /// - Parameters:
    ///   - bytes: The payload.
    ///   - position: The cursor; advanced past every byte read.
    ///   - end: The payload length.
    /// - Returns: A value in `0 ..< 2^28`.
    /// - Throws: `lengthMismatch` when no byte remains (V1), `invalidContainer` for a 4th byte with `0x80` (V2) or a
    ///   final zero byte in a multi-byte Var (V3).
    @inline(__always)
    internal static func readVariable(_ bytes: UnsafePointer<UInt8>, _ position: inout Int, _ end: Int) throws -> Int {
        guard position < end else { throw DocumentStorageError.lengthMismatch }
        var current = bytes[position]
        position += 1
        if current < 0x80 { return Int(current) }
        var value = Int(current & 0x7F)
        var shift = 7
        for index in 1...3 {
            guard position < end else { throw DocumentStorageError.lengthMismatch }
            current = bytes[position]
            position += 1
            if index == 3, current & 0x80 != 0 { throw DocumentStorageError.invalidContainer }
            value |= Int(current & 0x7F) << shift
            if current & 0x80 == 0 {
                guard current != 0 else { throw DocumentStorageError.invalidContainer }
                return value
            }
            shift += 7
        }
        throw DocumentStorageError.invalidContainer
    }

    /// Appends the minimal Var of `value`; the caller keeps `value` below 2^28.
    internal static func appendVariable(_ value: Int, to bytes: inout [UInt8]) {
        var rest = value
        while rest >= 0x80 {
            bytes.append(UInt8(truncatingIfNeeded: rest & 0x7F) | 0x80)
            rest >>= 7
        }
        bytes.append(UInt8(truncatingIfNeeded: rest))
    }

    /// The byte length of the minimal Var of `value`.
    internal static func variableLength(_ value: Int) -> Int {
        var length = 1
        var rest = value
        while rest >= 0x80 {
            rest >>= 7
            length += 1
        }
        return length
    }

    /// The number form of SPEC 11.3.3 that a writer picks: 1 integer, 2 binary32, 3 binary64.
    /// - Parameter value: A coordinate, with -0 already normalized to +0.
    /// - Returns: The first form whose condition holds; non-finite values get form 2 (infinities) or 3 (NaN).
    internal static func form(of value: Double) -> Int {
        if isIntegerForm(value) { return 1 }
        return Double(Float(value)) == value ? 2 : 3
    }

    /// Whether a value is integral and inside the integer form's range (including -0, which no form stores).
    @inline(__always)
    internal static func isIntegerForm(_ value: Double) -> Bool {
        value.rounded(.towardZero) == value && value >= integerMinimum && value <= integerMaximum
    }

    /// The byte length of the canonical spelling of an integer-form value: its digits plus a leading `-`.
    @inline(__always)
    internal static func integerLength(_ value: Int) -> Int {
        var length = value < 0 ? 2 : 1
        var rest = value.magnitude
        while rest >= 10 {
            rest /= 10
            length += 1
        }
        return length
    }

    /// The quoted form `q(s)` of SPEC 11.3.6.6: `"`, then `s` with `"` and `\` escaped, then `"`.
    internal static func quoted(_ value: String) -> String {
        var bytes: [UInt8] = [0x22]
        bytes.reserveCapacity(value.utf8.count + 2)
        for byte in value.utf8 {
            if byte == 0x22 || byte == 0x5C { bytes.append(0x5C) }
            bytes.append(byte)
        }
        bytes.append(0x22)
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Private Methods

    /// A capacity hint for the writer; the writer never grows past its cap whatever this returns.
    private static func estimate(_ document: Document) -> Int {
        var total = DocumentStorageCodec.headerByteCount + 16 + document.version.utf8.count
        total += document.axis.rawValue.utf8.count + (document.title?.utf8.count ?? 0)
        total += document.preamble?.utf8.count ?? 0
        for (key, value) in document.metadata { total += 8 + key.utf8.count + value.utf8.count }
        for plane in document.planes {
            total += 32 + plane.body.utf8.count + (plane.label?.utf8.count ?? 0)
            for (key, value) in plane.attributes { total += 8 + key.utf8.count + value.utf8.count }
        }
        return total
    }
}

// MARK: - StructuredReader

/// One forward cursor over a kind-2 payload: Phases S, L and Q of SPEC 11.3.8.
///
/// Phase S keeps no strings and no map entries. It records the numbers of each plane and the spans of its strings,
/// and it reads each map again from its first entry when a later step needs the keys, because the entries of one map
/// are contiguous in the payload. In decoding mode every string is validated as UTF-8 (`String(decoding:)` plus
/// byte equality, chunked, after an ASCII prefix) and the validating strings are discarded. The document is built
/// from the spans only after Phases L and Q passed (SPEC 11.3.2), so the reader's own memory before that point is a
/// few words per plane and one word per non-ASCII key of the map being checked. The writer's self-check runs the same
/// routine without validating UTF-8 that it produced from Swift strings (SPEC 11.3.9, W4).
///
/// Cancellation is checked before each plane, within every scan of a long string, and whenever the bytes read since
/// the last check pass 65,536, so runs of short strings cannot postpone a check (SPEC 11.3.13).
internal struct StructuredReader {
    // MARK: - Types

    /// The role of a segment string (SPEC 11.3.6.4).
    private enum SegmentRole {
        case preamble
        case body
    }

    /// Byte classes of one string field, accumulated over every byte.
    private struct ByteClass {
        fileprivate static let high: UInt8 = 0x01
        fileprivate static let lineBreak: UInt8 = 0x02
        fileprivate static let escape: UInt8 = 0x04
        fileprivate static let quote: UInt8 = 0x08
        fileprivate static let colon: UInt8 = 0x10
        fileprivate static let equals: UInt8 = 0x20
        fileprivate static let blank: UInt8 = 0x40
        fileprivate static let upper: UInt8 = 0x80

        /// The class bits of every byte value.
        fileprivate static let table: [UInt8] = (0..<256).map { value -> UInt8 in
            switch value {
            case 0x80...0xFF: return high
            case 0x0A, 0x0D: return lineBreak
            case 0x22: return escape | quote
            case 0x5C: return escape
            case 0x27: return quote
            case 0x3A: return colon
            case 0x3D: return equals
            case 0x09, 0x20: return blank
            case 0x41...0x5A: return upper
            default: return 0
            }
        }
    }

    /// The span and byte classes of the last string field read.
    private struct Field {
        fileprivate var start = 0
        fileprivate var length = 0
        fileprivate var classes: UInt8 = 0
        fileprivate var escapes = 0

        fileprivate var isASCII: Bool { classes & ByteClass.high == 0 }
        /// `Q(s) = len(s) + 2 + esc(s)` of SPEC 11.3.7.
        fileprivate var quotedLength: Int { length + 2 + escapes }
        fileprivate var span: Span {
            Span(start: Int32(truncatingIfNeeded: start), length: Int32(truncatingIfNeeded: length))
        }
    }

    /// The offset and length of a string in the payload; payloads are below 2^31 bytes (D10, W3).
    private struct Span {
        fileprivate var start: Int32
        fileprivate var length: Int32

        fileprivate var range: Range<Int> { Int(start)..<(Int(start) + Int(length)) }
    }

    /// One plane after Phase S: its numbers, the spans of its strings, and where its attribute map starts.
    private struct PlaneRecord {
        fileprivate var z: Double
        fileprivate var x: Double?
        fileprivate var y: Double?
        fileprivate var label: Span?
        fileprivate var body: Span
        /// The payload offset of the first attribute entry; the entries of a map follow one another.
        fileprivate var attributes: Int32
        fileprivate var attributeCount: Int32
        /// Whether a key holds a quote character, so that Phase Q checks the plane (P7b).
        fileprivate var marked: Bool
    }

    /// A directive whose length the bound `1 <= Nn <= 24` cannot decide against R.
    private struct DeferredDirective {
        fileprivate var base: Int
        fileprivate var floats: Range<Int>
    }

    // MARK: - Properties

    private let bytes: UnsafePointer<UInt8>
    private let end: Int
    private let decoding: Bool
    private let recordLimit: Int
    private let decodedLimit: Int
    private let lineLimit: Int
    private let planeLimit: Int
    private var position = 0
    private var field = Field()
    /// Bytes read or compared since the last cancellation check.
    private var scanned = 0

    // MARK: - Initializers

    /// Creates a reader over a complete uncompressed payload.
    /// - Parameters:
    ///   - payload: The payload bytes.
    ///   - limits: The caller's storage policy.
    ///   - decoding: `true` to validate UTF-8 and build the document; `false` for the writer's self-check.
    /// - Throws: `lengthMismatch` for an empty payload (S1 finds no byte).
    internal init(_ payload: UnsafeRawBufferPointer, limits: DocumentDecodeLimits, decoding: Bool) throws {
        let buffer = payload.bindMemory(to: UInt8.self)
        guard let base = buffer.baseAddress, !buffer.isEmpty else { throw DocumentStorageError.lengthMismatch }
        // Spans are stored as Int32; D10 and the writer's cap keep every payload far below this.
        guard buffer.count < Int(Int32.max) else { throw DocumentStorageError.oversizedOutput }
        bytes = base
        end = buffer.count
        self.decoding = decoding
        recordLimit = limits.maximumRecordBytes
        decodedLimit = limits.maximumDecodedBytes
        lineLimit = limits.maximumLines
        planeLimit = limits.maximumPlanes
    }

    // MARK: - Reading

    /// Runs Phases S, L and Q, then builds the document when decoding.
    /// - Returns: The document when decoding, otherwise `nil`.
    /// - Throws: The first failing check in the order of SPEC 11.3.8, or `CancellationError`.
    internal mutating func read() throws -> Document? {
        let record = recordLimit
        // S1
        let documentFlags = try byte()
        guard documentFlags & 0xFC == 0 else { throw DocumentStorageError.invalidContainer }
        let hasTitle = documentFlags & 1 != 0
        let hasPreamble = documentFlags & 2 != 0
        // S2
        try scalar(record)
        guard field.length > 0 else { throw Self.invalid("The version must be nonempty.") }
        let version = field.span
        let versionQuoted = field.quotedLength
        // S3
        try scalar(record)
        let axis = field.span
        let axisQuoted = field.quotedLength
        try checkAxis()
        // S4
        var title: Span?
        var titleQuoted = 0
        if hasTitle {
            try scalar(record)
            title = field.span
            titleQuoted = field.quotedLength
        }
        var total = 4 + (6 + versionQuoted) + (7 + axisQuoted) + 4
        var lines = 5
        var frontmatter = max(5 + versionQuoted, 6 + axisQuoted)
        if hasTitle {
            total += 8 + titleQuoted
            lines += 1
            frontmatter = max(frontmatter, 7 + titleQuoted)
        }
        // S5, S6
        let metadataCount = try count(2)
        let metadataStart = position
        lines += metadataCount
        var previous = Field()
        var nonASCIIKeys = 0
        for index in 0..<metadataCount {
            try scalar(record)
            let key = field
            if index > 0 { try checkOrder(previous, key) }
            try checkMetadataKey(key)
            try scalar(record)
            let valueQuoted = field.quotedLength
            frontmatter = max(frontmatter, key.length + 2 + valueQuoted)
            total += 3 + key.length + valueQuoted
            if !key.isASCII { nonASCIIKeys += 1 }
            previous = key
        }
        // S6b
        if nonASCIIKeys > 0 { try checkEquivalence(from: metadataStart, count: metadataCount, nonASCII: nonASCIIKeys) }
        // S7
        var preamble: Span?
        if hasPreamble {
            let lineFeeds = try segment(record - 1, role: .preamble, final: false)
            preamble = field.span
            total += 2 + field.length
            lines += 2 + lineFeeds
        }
        // S8
        let planeCount = try count(4)
        guard planeCount <= planeLimit else { throw DocumentStorageError.tooManyPlanes }
        guard !hasPreamble || planeCount > 0 else { throw Self.invalid("A preamble requires at least one plane.") }
        // S9: a plane record per plane (at most Pmax of them); no string and no map entry is kept.
        var planes: [PlaneRecord] = []
        planes.reserveCapacity(planeCount)
        var increasing = true
        var anyMarked = false
        var floats: [Double] = []
        // Directives over R even at one byte per float, and directives the bound 1 <= Nn <= 24 cannot decide.
        var directiveOverflow = false
        var deferred: [DeferredDirective] = []
        for index in 0..<planeCount {
            try DocumentStorageCancellation.check("plane")
            // P1
            let planeFlags = try byte()
            let zForm = Int(planeFlags & 3)
            let xForm = Int((planeFlags >> 2) & 3)
            let yForm = Int((planeFlags >> 4) & 3)
            guard planeFlags & 0x80 == 0, zForm != 0 else { throw DocumentStorageError.invalidContainer }
            var directive = 9
            let floatStart = floats.count
            // P2 to P4
            let z = try coordinate(zForm, directive: &directive, floats: &floats)
            if let last = planes.last, !(z > last.z) { increasing = false }
            var x: Double?
            if xForm != 0 {
                directive += 3
                x = try coordinate(xForm, directive: &directive, floats: &floats)
            }
            var y: Double?
            if yForm != 0 {
                directive += 3
                y = try coordinate(yForm, directive: &directive, floats: &floats)
            }
            // P5
            var label: Span?
            if planeFlags & 0x40 != 0 {
                try scalar(record)
                label = field.span
                directive += 7 + field.quotedLength
            }
            // P6, P7: R9 is evaluated per key here but reported only after P7a, and only without quotes (P7b).
            let attributeCount = try count(3)
            let attributeStart = position
            var hasQuote = false
            var nonASCII = 0
            var keyRuleHolds = true
            for entry in 0..<attributeCount {
                try scalar(record)
                let key = field
                if key.classes & ByteClass.quote != 0 { hasQuote = true }
                if entry > 0 { try checkOrder(previous, key) }
                if keyRuleHolds { keyRuleHolds = try isValidAttributeKey(key) }
                if !key.isASCII { nonASCII += 1 }
                try scalar(record)
                directive += 2 + key.length + field.quotedLength
                previous = key
            }
            // P7a
            if nonASCII > 0 { try checkEquivalence(from: attributeStart, count: attributeCount, nonASCII: nonASCII) }
            // P7b
            if hasQuote {
                anyMarked = true
            } else if !keyRuleHolds {
                throw Self.invalid("Attribute keys must be lowercase and cannot shadow coordinates or labels.")
            }
            // P8
            let lineFeeds = try segment(record, role: .body, final: index + 1 == planeCount)
            let floatCount = floats.count - floatStart
            if directive + floatCount > record {
                directiveOverflow = true
            } else if directive + 24 * floatCount > record {
                deferred.append(DeferredDirective(base: directive, floats: floatStart..<floats.count))
            }
            total += 2 + directive + (field.length > 0 ? field.length + 1 : 0)
            lines += field.length > 0 ? 3 + lineFeeds : 2
            planes.append(
                PlaneRecord(
                    z: z,
                    x: x,
                    y: y,
                    label: label,
                    body: field.span,
                    attributes: Int32(truncatingIfNeeded: attributeStart),
                    attributeCount: Int32(truncatingIfNeeded: attributeCount),
                    marked: hasQuote
                )
            )
        }
        // S10
        guard position == end else { throw DocumentStorageError.lengthMismatch }
        try checkLimits(
            planes: planes,
            increasing: increasing,
            frontmatter: frontmatter,
            directiveOverflow: directiveOverflow,
            deferred: deferred,
            total: total,
            floats: floats,
            lines: lines
        )
        // Phase Q
        if anyMarked {
            for plane in planes where plane.marked {
                try DocumentStorageCancellation.check("phaseQ.before")
                try roundTrip(plane)
                try DocumentStorageCancellation.check("phaseQ.after")
            }
        }
        guard decoding else { return nil }
        // Every string below was validated in Phase S, so the values are built from their spans without validation.
        var metadata: [String: String] = [:]
        metadata.reserveCapacity(metadataCount)
        var cursor = metadataStart
        for _ in 0..<metadataCount {
            let (key, value) = entry(at: &cursor)
            try charge(key.count + value.count + 2)
            metadata[text(of: key)] = text(of: value)
        }
        var result: [Plane] = []
        result.reserveCapacity(planes.count)
        for plane in planes {
            try DocumentStorageCancellation.check("materialize")
            var attributes: [String: String] = [:]
            attributes.reserveCapacity(Int(plane.attributeCount))
            cursor = Int(plane.attributes)
            for _ in 0..<Int(plane.attributeCount) {
                let (key, value) = entry(at: &cursor)
                try charge(key.count + value.count + 2)
                attributes[text(of: key)] = text(of: value)
            }
            try charge(Int(plane.body.length) + Int(plane.label?.length ?? 0))
            result.append(
                Plane(
                    z: plane.z,
                    label: plane.label.map { text(of: $0.range) },
                    x: plane.x,
                    y: plane.y,
                    attributes: attributes,
                    body: text(of: plane.body.range)
                )
            )
        }
        return Document(
            version: text(of: version.range),
            axis: Axis(rawValue: text(of: axis.range)),
            title: title.map { text(of: $0.range) },
            metadata: metadata,
            preamble: preamble.map { text(of: $0.range) },
            planes: result
        )
    }

    // MARK: - Primitives

    /// u8 (SPEC 11.3.3).
    @inline(__always)
    private mutating func byte() throws -> UInt8 {
        guard position < end else { throw DocumentStorageError.lengthMismatch }
        let value = bytes[position]
        position += 1
        return value
    }

    /// Var: minimal unsigned LEB128 of 1 to 4 bytes (V1 to V3).
    @inline(__always)
    private mutating func variable() throws -> Int {
        try DocumentStorageStructured.readVariable(bytes, &position, end)
    }

    /// Count(min): a Var no greater than `floor(remaining / min)`, divided rather than multiplied.
    @inline(__always)
    private mutating func count(_ minimum: Int) throws -> Int {
        let value = try variable()
        guard value <= (end - position) / minimum else { throw DocumentStorageError.lengthMismatch }
        return value
    }

    /// Charges `count` bytes of reading or comparison, checking cancellation before the total passes 65,536.
    @inline(__always)
    private mutating func charge(_ count: Int) throws {
        if count > DocumentStorageStructured.block - scanned {
            try DocumentStorageCancellation.check("budget")
            scanned = 0
        }
        scanned += min(count, DocumentStorageStructured.block)
    }

    /// Number(form) for a coordinate, adding an integer spelling to `directive` or recording a float for Phase L.
    private mutating func coordinate(_ form: Int, directive: inout Int, floats: inout [Double]) throws -> Double {
        switch form {
        case 1:
            let encoded = UInt32(try variable())
            let integer = Int32(bitPattern: (encoded >> 1) ^ (0 &- (encoded & 1)))
            directive += DocumentStorageStructured.integerLength(Int(integer))
            return Double(integer)
        case 2:
            guard end - position >= 4 else { throw DocumentStorageError.lengthMismatch }
            let bits = UInt32(littleEndian: UnsafeRawPointer(bytes + position).loadUnaligned(as: UInt32.self))
            position += 4
            let value = Double(Float(bitPattern: bits))
            guard value.isFinite else { throw Self.invalid("Plane coordinates must be finite.") }
            guard !DocumentStorageStructured.isIntegerForm(value) else { throw DocumentStorageError.invalidContainer }
            floats.append(value)
            return value
        default:
            guard end - position >= 8 else { throw DocumentStorageError.lengthMismatch }
            let bits = UInt64(littleEndian: UnsafeRawPointer(bytes + position).loadUnaligned(as: UInt64.self))
            position += 8
            let value = Double(bitPattern: bits)
            guard value.isFinite else { throw Self.invalid("Plane coordinates must be finite.") }
            guard !DocumentStorageStructured.isIntegerForm(value), Double(Float(value)) != value else {
                throw DocumentStorageError.invalidContainer
            }
            floats.append(value)
            return value
        }
    }

    /// Str(scalar, limit): Str1 to Str4, recording the span and byte classes in `field`.
    private mutating func scalar(_ limit: Int) throws {
        let start = try stringSpan(limit)
        let length = field.length
        var classes: UInt8 = 0
        var escapes = 0
        try ByteClass.table.withUnsafeBufferPointer { table in
            guard let table = table.baseAddress else { return }
            var offset = start
            let stop = start + length
            while offset < stop {
                if offset != start { try DocumentStorageCancellation.check("scalarScan") }
                let chunkEnd = min(stop, offset + DocumentStorageStructured.block)
                while offset < chunkEnd {
                    let entry = table[Int(bytes[offset])]
                    classes |= entry
                    escapes &+= Int((entry &>> 2) & 1)
                    offset += 1
                }
            }
        }
        field.classes = classes
        field.escapes = escapes
        if decoding, classes & ByteClass.high != 0 { try validate(start, length) }
        guard classes & ByteClass.lineBreak == 0 else {
            throw Self.invalid("Scalar fields cannot contain physical line breaks.")
        }
    }

    /// Str(segment, limit): Str1 to Str3, then the segment rules G1 to G6 (Str4); returns `LF(S)`.
    private mutating func segment(_ limit: Int, role: SegmentRole, final: Bool) throws -> Int {
        let start = try stringSpan(limit)
        let length = field.length
        field.classes = 0
        field.escapes = 0
        if decoding {
            let first = try firstNonASCII(start, start + length)
            if first < start + length { try validate(first, start + length - first) }
        }
        return try scanSegment(start, start + length, role: role, final: final)
    }

    /// Str1 and Str2: reads the length and moves the cursor past the string.
    @inline(__always)
    private mutating func stringSpan(_ limit: Int) throws -> Int {
        let framed = position
        let length = try variable()
        guard length <= end - position else { throw DocumentStorageError.lengthMismatch }
        guard length <= limit else { throw DocumentStorageError.oversizedRecord }
        let start = position
        position += length
        field.start = start
        field.length = length
        try charge(position - framed)
        return start
    }

    /// The key and value spans of the map entry at `cursor`, which Phase S already read; moves past the entry.
    @inline(__always)
    private func entry(at cursor: inout Int) -> (key: Range<Int>, value: Range<Int>) {
        let keyLength = (try? DocumentStorageStructured.readVariable(bytes, &cursor, end)) ?? 0
        let key = cursor..<(cursor + keyLength)
        cursor += keyLength
        let valueLength = (try? DocumentStorageStructured.readVariable(bytes, &cursor, end)) ?? 0
        let value = cursor..<(cursor + valueLength)
        cursor += valueLength
        return (key, value)
    }

    // MARK: - Strings

    /// Str3: `String(decoding:)` plus byte equality, in chunks of at most 65,536 bytes split at scalar boundaries.
    /// The strings are discarded; values are built after Phase Q.
    private func validate(_ start: Int, _ length: Int) throws {
        let base = bytes + start
        var offset = 0
        while offset < length {
            if offset > 0 { try DocumentStorageCancellation.check("utf8") }
            var cut = min(offset + DocumentStorageStructured.block, length)
            var stepped = 0
            while cut < length, stepped < 3, base[cut] & 0xC0 == 0x80 {
                cut -= 1
                stepped += 1
            }
            try Self.validateChunk(base + offset, cut - offset)
            offset = cut
        }
    }

    /// One complete UTF-8 chunk: ill-formed input is exactly input whose repaired decoding differs byte for byte.
    @inline(__always)
    private static func validateChunk(_ base: UnsafePointer<UInt8>, _ length: Int) throws {
        var text = String(decoding: UnsafeBufferPointer(start: base, count: length), as: UTF8.self)
        let same = text.withUTF8 { utf8 -> Bool in
            guard utf8.count == length else { return false }
            guard let address = utf8.baseAddress, length > 0 else { return true }
            return memcmp(address, base, length) == 0
        }
        guard same else { throw DocumentStorageError.invalidUTF8 }
    }

    /// The offset of the first byte at or above 0x80 in `start ..< stop`, or `stop`; eight bytes at a time.
    private func firstNonASCII(_ start: Int, _ stop: Int) throws -> Int {
        var offset = start
        var checkpoint = start + DocumentStorageStructured.block
        while stop - offset >= 8 {
            let word = UnsafeRawPointer(bytes + offset).loadUnaligned(as: UInt64.self)
            if word & 0x8080_8080_8080_8080 != 0 { break }
            offset += 8
            if offset >= checkpoint {
                try DocumentStorageCancellation.check("utf8")
                checkpoint = offset + DocumentStorageStructured.block
            }
        }
        while offset < stop, bytes[offset] < 0x80 { offset += 1 }
        return offset
    }

    /// Whether every byte of a span is ASCII.
    @inline(__always)
    private func isASCII(_ span: Range<Int>) -> Bool {
        var bits: UInt8 = 0
        var offset = span.lowerBound
        while offset < span.upperBound {
            bits |= bytes[offset]
            offset += 1
        }
        return bits < 0x80
    }

    /// The text of a span the reader validated earlier, or that the writer produced, without validating it again.
    private func text(of span: Range<Int>) -> String {
        String(decoding: UnsafeBufferPointer(start: bytes + span.lowerBound, count: span.count), as: UTF8.self)
    }

    // MARK: - Field Rules

    /// R2: the axis equals its own 2.0 normalization (trim W, lowercase), compared byte for byte.
    private func checkAxis() throws {
        if field.isASCII {
            guard field.classes & ByteClass.upper == 0 else { throw Self.invalid("The axis must be normalized.") }
            if field.length > 0 {
                let first = bytes[field.start]
                let last = bytes[field.start + field.length - 1]
                guard first != 0x20, first != 0x09, last != 0x20, last != 0x09 else {
                    throw Self.invalid("The axis must be normalized.")
                }
            }
            return
        }
        let text = self.text(of: field.start..<(field.start + field.length))
        guard Axis(rawValue: text).rawValue.utf8.elementsEqual(text.utf8) else {
            throw Self.invalid("The axis must be normalized.")
        }
    }

    /// R3: a metadata key holds no `:`, has no W at either end, does not start with `#` and is not reserved.
    private func checkMetadataKey(_ key: Field) throws {
        guard key.length > 0 else { return }
        let start = key.start
        let stop = key.start + key.length
        guard key.classes & ByteClass.colon == 0,
            ThreeMDWhitespace.leadingLength(bytes, at: start, end: stop) == 0,
            ThreeMDWhitespace.trailingLength(bytes, start: start, end: stop) == 0,
            bytes[start] != 0x23
        else { throw Self.invalid("Metadata keys cannot shadow reserved fields or comments.") }
        guard key.isASCII, (3...5).contains(key.length) else { return }
        var lowered: [UInt8] = []
        lowered.reserveCapacity(key.length)
        for offset in start..<stop {
            let value = bytes[offset]
            lowered.append((0x41...0x5A).contains(value) ? value + 32 : value)
        }
        for reserved in ["3md", "axis", "title"] where lowered.elementsEqual(reserved.utf8) {
            throw Self.invalid("Metadata keys cannot shadow reserved fields or comments.")
        }
    }

    /// R9: an attribute key of a plane without quote characters is a valid, lowercase, unreserved token.
    /// - Parameter key: The key field, already validated as UTF-8 when decoding.
    /// - Returns: Whether the key satisfies R9.
    /// - Throws: `CancellationError` while comparing a long key.
    private mutating func isValidAttributeKey(_ key: Field) throws -> Bool {
        let start = key.start
        let stop = key.start + key.length
        guard key.length > 0, key.classes & (ByteClass.blank | ByteClass.equals) == 0 else { return false }
        if key.isASCII {
            guard key.classes & ByteClass.upper == 0 else { return false }
            let first = bytes[start]
            let reserved =
                (key.length == 1 && (first == 0x7A || first == 0x78 || first == 0x79))
                || (key.length == 5 && first == 0x6C && bytes[start + 1] == 0x61 && bytes[start + 2] == 0x62
                    && bytes[start + 3] == 0x65 && bytes[start + 4] == 0x6C)
            return !reserved
        }
        guard ThreeMDWhitespace.leadingLength(bytes, at: start, end: stop) == 0,
            ThreeMDWhitespace.trailingLength(bytes, start: start, end: stop) == 0
        else { return false }
        return try isLowercase(start..<stop)
    }

    /// Whether a key equals its own `lowercased()`. `String.lowercased()` maps each scalar on its own, so a key longer
    /// than 65,536 bytes is compared in chunks split at scalar boundaries, with a cancellation check between chunks.
    private func isLowercase(_ span: Range<Int>) throws -> Bool {
        var offset = span.lowerBound
        while offset < span.upperBound {
            if offset != span.lowerBound { try DocumentStorageCancellation.check("keyScan") }
            var cut = min(offset + DocumentStorageStructured.block, span.upperBound)
            var stepped = 0
            while cut < span.upperBound, stepped < 3, bytes[cut] & 0xC0 == 0x80 {
                cut -= 1
                stepped += 1
            }
            let text = self.text(of: offset..<cut)
            guard text.lowercased().utf8.elementsEqual(text.utf8) else { return false }
            offset = cut
        }
        return true
    }

    /// Key order: strictly increasing raw UTF-8 bytes, a proper prefix first (S6, P7).
    @inline(__always)
    private func checkOrder(_ previous: Field, _ key: Field) throws {
        let common = min(previous.length, key.length)
        let order = common == 0 ? 0 : memcmp(bytes + previous.start, bytes + key.start, common)
        guard order < 0 || (order == 0 && previous.length < key.length) else {
            throw DocumentStorageError.invalidContainer
        }
    }

    /// S6b and P7a after the last entry of a map with a non-ASCII key: no two keys are canonically equivalent.
    ///
    /// Distinct keys can be equivalent only when one of them is not ASCII, and Swift hashes a string through its NFC
    /// form, so equivalent keys hash alike. Each non-ASCII key contributes one word, the low bits of its hash above
    /// its entry's payload offset. The words are sorted; non-ASCII keys whose hash bits meet, and each ASCII key whose
    /// hash bits meet a non-ASCII key's, are compared as strings, whose `==` is canonical equivalence. The check holds
    /// one word per non-ASCII key and no string beyond the comparison it serves.
    /// - Parameters:
    ///   - start: The payload offset of the map's first entry.
    ///   - count: The number of entries.
    ///   - nonASCII: How many keys are not ASCII (at least one).
    private mutating func checkEquivalence(from start: Int, count: Int, nonASCII: Int) throws {
        let shift = UInt64.bitWidth - UInt64(end).leadingZeroBitCount
        let offsetMask: UInt64 = (1 << shift) - 1
        var words: [UInt64] = []
        words.reserveCapacity(nonASCII)
        var cursor = start
        for _ in 0..<count {
            let entryStart = cursor
            let key = entry(at: &cursor).key
            try charge(key.count + 2)
            guard !isASCII(key) else { continue }
            words.append(Self.hashBits(text(of: key), shift: shift) | UInt64(entryStart))
        }
        try DocumentStorageCancellation.check("equivalence")
        words.sort()
        try DocumentStorageCancellation.check("equivalence")
        var group = 0
        while group < words.count {
            var next = group + 1
            while next < words.count, words[next] & ~offsetMask == words[group] & ~offsetMask { next += 1 }
            if next - group > 1 {
                for first in group..<next {
                    let left = try keyText(atEntry: Int(words[first] & offsetMask))
                    for second in (first + 1)..<next {
                        guard try keyText(atEntry: Int(words[second] & offsetMask)) != left else {
                            throw Self.equivalentKeys
                        }
                    }
                }
            }
            group = next
        }
        guard words.count < count else { return }
        cursor = start
        for _ in 0..<count {
            let key = entry(at: &cursor).key
            try charge(key.count + 2)
            guard isASCII(key) else { continue }
            let text = text(of: key)
            let bits = Self.hashBits(text, shift: shift)
            var index = Self.lowerBound(of: bits, in: words)
            while index < words.count, words[index] & ~offsetMask == bits {
                guard try keyText(atEntry: Int(words[index] & offsetMask)) != text else { throw Self.equivalentKeys }
                index += 1
            }
        }
    }

    /// The key text of the map entry at `offset`, charged to the cancellation budget.
    private mutating func keyText(atEntry offset: Int) throws -> String {
        var cursor = offset
        let key = entry(at: &cursor).key
        try charge(key.count + 2)
        return text(of: key)
    }

    /// A key's hash in the bits above `shift`; equivalent keys give equal words.
    @inline(__always)
    private static func hashBits(_ text: String, shift: Int) -> UInt64 {
        UInt64(truncatingIfNeeded: UInt(bitPattern: text.hashValue)) << shift
    }

    /// The first index of a sorted array whose element is not below `value`.
    private static func lowerBound(of value: UInt64, in words: [UInt64]) -> Int {
        var low = 0
        var high = words.count
        while low < high {
            let middle = low + (high - low) / 2
            if words[middle] < value { low = middle + 1 } else { high = middle }
        }
        return low
    }

    // MARK: - Segment Rules

    /// G1 to G6 of SPEC 11.3.6.4 over the bytes `start ..< stop`; returns `LF(S)`.
    private func scanSegment(_ start: Int, _ stop: Int, role: SegmentRole, final: Bool) throws -> Int {
        guard start < stop else {
            guard role == .body else { throw Self.invalid("A preamble cannot be empty.") }
            return 0
        }
        guard bytes[stop - 1] != 0x0D else { throw Self.invalid("Segments cannot end with a carriage return.") }
        var checkpoint = start + DocumentStorageStructured.block
        var fence: UInt8 = 0
        var lineFeeds = 0
        var lineStart = start
        while true {
            let lineEnd = try nextLineFeed(from: lineStart, stop: stop, checkpoint: &checkpoint)
            if lineEnd < stop, lineEnd > lineStart, bytes[lineEnd - 1] == 0x0D {
                throw Self.invalid("Segments cannot contain CRLF.")
            }
            if lineStart == start, try skipWhitespace(lineStart, lineEnd) == lineEnd {
                throw Self.invalid("Segments cannot start with a blank line.")
            }
            if lineStart < lineEnd {
                let first = bytes[lineStart]
                if first == 0x09 || first == 0x20 || first == 0xC2 || (0xE1...0xE3).contains(first) || first == 0x60
                    || first == 0x7E || first == 0x40
                {
                    let trimmed = try skipWhitespace(lineStart, lineEnd)
                    let remaining = lineEnd - trimmed
                    if fence != 0 {
                        if remaining >= 3, bytes[trimmed] == fence, bytes[trimmed + 1] == fence,
                            bytes[trimmed + 2] == fence
                        {
                            fence = 0
                        }
                    } else if remaining >= 3, bytes[trimmed] == 0x60, bytes[trimmed + 1] == 0x60,
                        bytes[trimmed + 2] == 0x60
                    {
                        fence = 0x60
                    } else if remaining >= 3, bytes[trimmed] == 0x7E, bytes[trimmed + 1] == 0x7E,
                        bytes[trimmed + 2] == 0x7E
                    {
                        fence = 0x7E
                    } else if first == 0x40, isPlaneDirective(lineStart, lineEnd) {
                        throw Self.invalid("Segments cannot contain a line that starts a plane.")
                    }
                }
            }
            if lineEnd == stop {
                guard try skipWhitespace(lineStart, lineEnd) != lineEnd else {
                    throw Self.invalid("Segments cannot end with a blank line.")
                }
                break
            }
            lineFeeds += 1
            lineStart = lineEnd + 1
        }
        guard final || fence == 0 else { throw Self.invalid("An open fence would swallow the next directive.") }
        return lineFeeds
    }

    /// The next LF at or after `from`, or `stop`; memchr runs in windows that end at cancellation checkpoints.
    private func nextLineFeed(from: Int, stop: Int, checkpoint: inout Int) throws -> Int {
        var cursor = from
        while cursor < stop {
            let windowEnd = min(stop, checkpoint)
            if cursor < windowEnd, let found = memchr(bytes + cursor, 0x0A, windowEnd - cursor) {
                return UnsafeRawPointer(bytes).distance(to: UnsafeRawPointer(found))
            }
            cursor = windowEnd
            if cursor >= checkpoint {
                try DocumentStorageCancellation.check("segmentScan")
                checkpoint += DocumentStorageStructured.block
            }
        }
        return stop
    }

    /// The first offset in `start ..< stop` that does not begin a W scalar.
    private func skipWhitespace(_ start: Int, _ stop: Int) throws -> Int {
        var cursor = start
        var checkpoint = start + DocumentStorageStructured.block
        while cursor < stop {
            let length = ThreeMDWhitespace.leadingLength(bytes, at: cursor, end: stop)
            guard length > 0 else { return cursor }
            cursor += length
            if cursor >= checkpoint {
                try DocumentStorageCancellation.check("segmentScan")
                checkpoint = cursor + DocumentStorageStructured.block
            }
        }
        return cursor
    }

    /// Whether a line equals `@plane` or starts with `@plane` and a space or tab (G5).
    @inline(__always)
    private func isPlaneDirective(_ start: Int, _ stop: Int) -> Bool {
        let length = stop - start
        guard length >= 6, bytes[start] == 0x40, bytes[start + 1] == 0x70, bytes[start + 2] == 0x6C,
            bytes[start + 3] == 0x61, bytes[start + 4] == 0x6E, bytes[start + 5] == 0x65
        else { return false }
        return length == 6 || bytes[start + 6] == 0x20 || bytes[start + 6] == 0x09
    }

    // MARK: - Phase L

    /// L0 to L5 of SPEC 11.3.8, in order.
    private mutating func checkLimits(
        planes: [PlaneRecord],
        increasing: Bool,
        frontmatter: Int,
        directiveOverflow: Bool,
        deferred: [DeferredDirective],
        total: Int,
        floats: [Double],
        lines: Int
    ) throws {
        try DocumentStorageCancellation.check("phaseL")
        // L0: strictly increasing positions are unique; otherwise compare bit patterns (no -0 or NaN is stored).
        if !increasing {
            var seen = Set<UInt64>(minimumCapacity: planes.count)
            for plane in planes where !seen.insert(plane.z.bitPattern).inserted {
                throw Self.invalid("Plane positions must be unique.")
            }
        }
        // L1, L2
        guard recordLimit >= 3, frontmatter <= recordLimit else { throw DocumentStorageError.oversizedRecord }
        // L3: a float spells in 1 to 24 bytes, so only directives the bound cannot decide are formatted.
        guard !directiveOverflow else { throw DocumentStorageError.oversizedRecord }
        for directive in deferred {
            var exact = directive.base
            for index in directive.floats {
                try charge(24)
                exact += floats[index].formatted3MD().utf8.count
            }
            guard exact <= recordLimit else { throw DocumentStorageError.oversizedRecord }
        }
        // L4
        if total + 24 * floats.count > decodedLimit {
            guard total + floats.count <= decodedLimit else { throw DocumentStorageError.oversizedOutput }
            var exact = total
            for value in floats {
                try charge(24)
                exact += value.formatted3MD().utf8.count
            }
            guard exact <= decodedLimit else { throw DocumentStorageError.oversizedOutput }
        }
        // L5
        guard lines <= lineLimit else { throw DocumentStorageError.tooManyLines }
    }

    // MARK: - Phase Q

    /// The directive round trip of SPEC 11.3.6.6 through the 2.0 parser, compared byte for byte. The plane's strings
    /// are built here, after Phase L, and released when the check returns.
    private mutating func roundTrip(_ plane: PlaneRecord) throws {
        let label = plane.label.map { text(of: $0.range) }
        var keys: [String] = []
        var values: [String] = []
        keys.reserveCapacity(Int(plane.attributeCount))
        values.reserveCapacity(Int(plane.attributeCount))
        var cursor = Int(plane.attributes)
        for _ in 0..<Int(plane.attributeCount) {
            let (key, value) = entry(at: &cursor)
            try charge(key.count + value.count + 2)
            keys.append(text(of: key))
            values.append(text(of: value))
        }
        var line = "@plane z=" + plane.z.formatted3MD()
        if let label { line += " label=" + DocumentStorageStructured.quoted(label) }
        if let x = plane.x { line += " x=" + x.formatted3MD() }
        if let y = plane.y { line += " y=" + y.formatted3MD() }
        let order = keys.indices.sorted { keys[$0] < keys[$1] }
        for index in order {
            line += " " + keys[index] + "=" + DocumentStorageStructured.quoted(values[index])
        }
        #if DEBUG
        if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) { DocumentStorageProbe.current?.recordParse() }
        #endif
        let parsed: Document
        do {
            parsed = try Parser().parse("---\n3md: \"1\"\naxis: \"a\"\n---\n\n" + line + "\n")
        } catch {
            throw Self.invalid("The plane directive would not parse back: \(error.localizedDescription)")
        }
        guard parsed.planes.count == 1, let result = parsed.planes.first, result.z == plane.z,
            result.x == plane.x, result.y == plane.y,
            Self.sameBytes(result.label, label),
            result.attributes.count == keys.count
        else { throw Self.invalid("The plane directive would not parse back to the same plane.") }
        for (key, value) in zip(keys, values) {
            guard let index = result.attributes.index(forKey: key),
                result.attributes[index].key.utf8.elementsEqual(key.utf8),
                result.attributes[index].value.utf8.elementsEqual(value.utf8)
            else { throw Self.invalid("The plane directive would not parse back to the same attributes.") }
        }
    }

    /// Byte equality of optional strings; `String ==` would treat canonically equivalent spellings as equal.
    private static func sameBytes(_ first: String?, _ second: String?) -> Bool {
        switch (first, second) {
        case (nil, nil): return true
        case (let first?, let second?): return first.utf8.elementsEqual(second.utf8)
        default: return false
        }
    }

    // MARK: - Errors

    private static var equivalentKeys: DocumentStorageError {
        invalid("Canonically equivalent dictionary keys cannot be represented faithfully.")
    }

    private static func invalid(_ detail: String) -> DocumentStorageError {
        .invalidDocument(detail)
    }
}

// MARK: - StructuredWriter

/// Emits the canonical kind-2 payload (W2, W3) into a buffer capped at `maximumEncodedBytes` including the header.
internal struct StructuredWriter {
    // MARK: - Properties

    /// The header placeholder (40 zero bytes) followed by the emitted payload.
    internal private(set) var bytes: [UInt8]
    private let capacity: Int
    /// The buffer length at which emission next checks cancellation, so a plane with many strings is not emitted
    /// without a check.
    private var checkpoint: Int

    // MARK: - Initializers

    /// Creates a writer whose container may hold at most `capacity` bytes, the 40-byte header included.
    /// - Parameters:
    ///   - capacity: `maximumEncodedBytes`, at least 40.
    ///   - estimate: A capacity hint; the buffer never reserves past `capacity`.
    internal init(capacity: Int, estimate: Int) {
        self.capacity = capacity
        checkpoint = DocumentStorageCodec.headerByteCount + DocumentStorageStructured.block
        bytes = []
        bytes.reserveCapacity(min(max(estimate, DocumentStorageCodec.headerByteCount), capacity))
        bytes.append(contentsOf: repeatElement(0, count: DocumentStorageCodec.headerByteCount))
    }

    // MARK: - Emission

    /// Emits every field of SPEC 11.3.5 in order, normalizing as the 2.0 text writer does (W2).
    /// - Parameter document: The document to emit; nothing is rejected here except the cap.
    /// - Throws: `oversizedInput` when the payload would pass `maximumEncodedBytes - 40`, or `CancellationError`.
    internal mutating func emit(_ document: Document) throws {
        try append(UInt8((document.title != nil ? 1 : 0) | (document.preamble != nil ? 2 : 0)))
        try append(document.version)
        try append(document.axis.rawValue)
        if let title = document.title { try append(title) }
        let metadata = document.metadata.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
        try appendCount(metadata.count, minimumElementBytes: 2)
        for (key, value) in metadata {
            try append(key)
            try append(value)
        }
        if let preamble = document.preamble { try append(preamble) }
        try appendCount(document.planes.count, minimumElementBytes: 4)
        for plane in document.planes {
            try DocumentStorageCancellation.check("emission")
            let z = plane.z == 0 ? 0 : plane.z
            let x = plane.x.map { $0 == 0 ? 0 : $0 }
            let y = plane.y.map { $0 == 0 ? 0 : $0 }
            let zForm = DocumentStorageStructured.form(of: z)
            let xForm = x.map { DocumentStorageStructured.form(of: $0) } ?? 0
            let yForm = y.map { DocumentStorageStructured.form(of: $0) } ?? 0
            try append(UInt8(zForm | xForm << 2 | yForm << 4 | (plane.label != nil ? 0x40 : 0)))
            try appendNumber(z, form: zForm)
            if let x { try appendNumber(x, form: xForm) }
            if let y { try appendNumber(y, form: yForm) }
            if let label = plane.label { try append(label) }
            let attributes = plane.attributes.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            try appendCount(attributes.count, minimumElementBytes: 2)
            for (key, value) in attributes {
                try append(key)
                try append(value)
            }
            try append(plane.body)
        }
    }

    // MARK: - Private Methods

    private var available: Int { capacity - bytes.count }

    private mutating func append(_ value: UInt8) throws {
        guard available >= 1 else { throw DocumentStorageError.oversizedInput }
        bytes.append(value)
    }

    /// Str: a minimal Var length, then the UTF-8 bytes verbatim.
    private mutating func append(_ text: String) throws {
        let length = text.utf8.count
        guard length < available, Self.variableLength(length) <= available - length else {
            throw DocumentStorageError.oversizedInput
        }
        appendVariable(length)
        if text.utf8.withContiguousStorageIfAvailable({ bytes.append(contentsOf: $0) }) == nil {
            bytes.append(contentsOf: text.utf8)
        }
        if bytes.count >= checkpoint {
            try DocumentStorageCancellation.check("emissionBytes")
            checkpoint = bytes.count + DocumentStorageStructured.block
        }
    }

    /// A count whose elements each emit at least `minimumElementBytes`, so a count that cannot fit is refused first.
    private mutating func appendCount(_ count: Int, minimumElementBytes: Int) throws {
        guard count <= available / minimumElementBytes else { throw DocumentStorageError.oversizedInput }
        let length = Self.variableLength(count)
        guard length <= available else { throw DocumentStorageError.oversizedInput }
        appendVariable(count)
    }

    private mutating func appendNumber(_ value: Double, form: Int) throws {
        switch form {
        case 1:
            let integer = Int32(value)
            let encoded = Int(UInt32(bitPattern: (integer << 1) ^ (integer >> 31)))
            guard Self.variableLength(encoded) <= available else { throw DocumentStorageError.oversizedInput }
            appendVariable(encoded)
        case 2:
            guard available >= 4 else { throw DocumentStorageError.oversizedInput }
            withUnsafeBytes(of: Float(value).bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        default:
            guard available >= 8 else { throw DocumentStorageError.oversizedInput }
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        }
    }

    /// Appends a minimal unsigned LEB128 value; callers have checked its length against the cap.
    private mutating func appendVariable(_ value: Int) {
        DocumentStorageStructured.appendVariable(value, to: &bytes)
    }

    private static func variableLength(_ value: Int) -> Int {
        DocumentStorageStructured.variableLength(value)
    }
}
