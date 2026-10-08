import Foundation

/// Bounded storage for general documents, independent of their axis or application-specific metadata.
///
/// Version 1 has a 40-byte little-endian header: magic `3mdbin\r\n` (8 bytes), version u16 (1),
/// payload kind u8 (1 = canonical UTF-8 3md, 2 = structured document), compression u8, flags u32 (0),
/// reserved u32 (0), encoded payload bytes u64, decoded payload bytes u64, and CRC-32/ISO-HDLC u32.
/// CRC covers header bytes 0..<36 followed by encoded payload; it excludes the checksum field.
/// CRC detects corruption, not authorship. This magic is distinct from Rook's older voxel-specific `3MDB` format.
public enum DocumentStorageCodec {
    /// The independently versioned binary-container version emitted and accepted by this codec.
    public static let containerVersion: UInt16 = 1
    /// The fixed version 1 binary header size in bytes.
    public static let headerByteCount = 40
    /// The payload kinds this release decodes: `canonicalText` and `structuredDocument`.
    public static let supportedPayloadKinds: Set<DocumentPayloadKind> = [.canonicalText, .structuredDocument]
    internal static let magic = Data("3mdbin\r\n".utf8)

    /// Recognizes the complete magic prefix without validating the header, payload or checksum.
    public static func isBinary(_ data: Data) -> Bool { data.prefix(magic.count).elementsEqual(magic) }

    /// Reads the 40-byte header without validating it, the payload or the checksum.
    /// - Parameter data: Complete or partial input; at most the first 40 bytes are read.
    /// - Returns: `nil` when the input does not begin with the binary magic (`isBinary` is false).
    /// - Throws: `DocumentStorageError.invalidContainer` when the magic is present but fewer than 40 bytes exist.
    public static func containerInfo(_ data: Data) throws -> DocumentContainerInfo? {
        guard isBinary(data) else { return nil }
        guard data.count >= headerByteCount else { throw DocumentStorageError.invalidContainer }
        return data.prefix(headerByteCount).withUnsafeBytes { DocumentContainerInfo(header: $0) }
    }

    /// Checks finite unique plane positions and a faithful bounded canonical-text round trip.
    /// - Throws: `DocumentStorageError` for invalid values or exceeded policies, or `CancellationError` when supported.
    public static func validate(_ document: Document, limits: DocumentDecodeLimits = .standard) throws {
        _ = try DocumentStorageValidation.canonicalData(document, limits: limits)
    }

    /// Produces canonical readable text, or the version 1 binary container with a structured document payload
    /// (payload kind 2). Use `encodeTextContainer(_:compression:limits:)` for files that ThreeMD 2.0 must read.
    /// - Throws: `DocumentStorageError` for invalid documents, limits or unavailable compression;
    ///   cancellation remains `CancellationError` on platforms supporting Swift concurrency.
    public static func encode(
        _ document: Document,
        format: DocumentStorageFormat = .text,
        limits: DocumentDecodeLimits = .standard
    ) throws -> Data {
        switch format {
        case .text:
            let source = try DocumentStorageValidation.canonicalData(document, limits: limits)
            guard source.count <= limits.maximumEncodedBytes else { throw DocumentStorageError.oversizedInput }
            return source
        case .binary(let compression):
            return try DocumentStorageStructured.encode(document, compression: compression, limits: limits)
        }
    }

    /// Writes payload kind 1, canonical text behind the binary header, byte-identical to ThreeMD 2.0 `.binary`.
    ///
    /// Use this only for files that ThreeMD 2.0.x must read. `encode(_:format:limits:)` with `.binary` writes the
    /// structured payload, which is smaller and decodes several times faster.
    /// - Parameters:
    ///   - document: The document to store.
    ///   - compression: `.none`, or `.lzfse` where the Compression framework exists.
    ///   - limits: The storage policy, applied exactly as the 2.0 binary writer applied it.
    /// - Returns: The complete container.
    /// - Throws: `DocumentStorageError` exactly as the 2.0 binary writer did, or `CancellationError` where supported.
    public static func encodeTextContainer(
        _ document: Document,
        compression: DocumentCompression = .none,
        limits: DocumentDecodeLimits = .standard
    ) throws -> Data {
        let source = try DocumentStorageValidation.canonicalData(document, limits: limits)
        guard limits.maximumEncodedBytes >= headerByteCount else { throw DocumentStorageError.oversizedInput }
        let payload = try DocumentStorageCompression.encode(
            source,
            compression: compression,
            maximumBytes: limits.maximumEncodedBytes - headerByteCount
        )
        return try container(
            kind: .canonicalText,
            compression: compression,
            payload: payload,
            decodedByteCount: source.count
        )
    }

    /// Autodetects readable text or the binary magic, then validates resource limits, stream boundaries and integrity.
    ///
    /// Payload kinds 1 and 2 are accepted; other kinds throw `unsupportedPayloadKind`.
    /// - Throws: `DocumentStorageError` for malformed or oversized input;
    ///   cancellation remains `CancellationError` on platforms supporting Swift concurrency.
    public static func decode(_ data: Data, limits: DocumentDecodeLimits = .standard) throws -> Document {
        try DocumentStorageCancellation.check()
        guard data.count <= limits.maximumEncodedBytes else { throw DocumentStorageError.oversizedInput }
        guard isBinary(data) else { return try DocumentStorageValidation.parse(data, limits: limits) }
        let header = try data.withUnsafeBytes { try checkedHeader($0, limits: limits) }
        let payload = data[(data.startIndex + headerByteCount)...]
        switch (header.kind, header.compression) {
        case (.canonicalText, .none):
            return try DocumentStorageValidation.parse(payload, limits: limits)
        case (.canonicalText, .lzfse):
            let source = try DocumentStorageCompression.decode(
                payload,
                compression: .lzfse,
                expectedBytes: header.decodedByteCount
            )
            return try DocumentStorageValidation.parse(source, limits: limits)
        case (_, .none):
            return try payload.withUnsafeBytes { try DocumentStorageStructured.decode($0, limits: limits) }
        case (_, .lzfse):
            let structured = try DocumentStorageCompression.decode(
                payload,
                compression: .lzfse,
                expectedBytes: header.decodedByteCount
            )
            return try structured.withUnsafeBytes { try DocumentStorageStructured.decode($0, limits: limits) }
        }
    }

    // MARK: - Internal Methods

    /// Writes a complete container: header, CRC and the encoded payload.
    internal static func container(
        kind: DocumentPayloadKind,
        compression: DocumentCompression,
        payload: Data,
        decodedByteCount: Int
    ) throws -> Data {
        var result = Data(capacity: headerByteCount + payload.count)
        result.append(magic)
        append(containerVersion, to: &result)
        result.append(kind.rawValue)
        result.append(compression.rawValue)
        append(UInt32(0), to: &result)
        append(UInt32(0), to: &result)
        append(UInt64(payload.count), to: &result)
        append(UInt64(decodedByteCount), to: &result)
        let checksum = try DocumentStorageChecksum.checksum(header: result, payload: payload)
        append(checksum, to: &result)
        result.append(payload)
        try DocumentStorageCancellation.check()
        return result
    }

    // MARK: - Private Methods

    /// D4 to D12 of SPEC 11.1 over the complete input; the payload itself is decoded afterwards (D13, D14).
    private static func checkedHeader(
        _ bytes: UnsafeRawBufferPointer,
        limits: DocumentDecodeLimits
    ) throws -> CheckedHeader {
        guard bytes.count >= headerByteCount else { throw DocumentStorageError.invalidContainer }
        let info = DocumentContainerInfo(header: bytes)
        guard info.containerVersion == containerVersion else {
            throw DocumentStorageError.unsupportedVersion(info.containerVersion)
        }
        let kind = info.payloadKind
        guard supportedPayloadKinds.contains(kind) else {
            throw DocumentStorageError.unsupportedPayloadKind(kind.rawValue)
        }
        guard let compression = DocumentCompression(rawValue: info.compression) else {
            throw DocumentStorageError.unsupportedCompression(info.compression)
        }
        guard info.flags == 0 else { throw DocumentStorageError.unsupportedFlags(info.flags) }
        guard info.reserved == 0 else { throw DocumentStorageError.nonzeroReserved }
        // D10: kind 2 may never decode to more than the uncompressed container can hold, nor to more than twice the
        // canonical text it stands for. The product saturates when the decoded bound is the largest `Int`.
        let bound = kind == .canonicalText ? limits.maximumDecodedBytes : limits.structuredDecodedBound
        guard info.decodedPayloadByteCount <= UInt64(bound) else { throw DocumentStorageError.oversizedOutput }
        let encoded = info.encodedPayloadByteCount
        let decoded = info.decodedPayloadByteCount
        guard encoded > 0, decoded > 0, encoded == UInt64(bytes.count - headerByteCount) else {
            throw DocumentStorageError.lengthMismatch
        }
        guard compression != .none || encoded == decoded else { throw DocumentStorageError.lengthMismatch }
        let checksum = try DocumentStorageChecksum.containerChecksum(bytes)
        guard checksum == info.checksum else { throw DocumentStorageError.checksumMismatch }
        return CheckedHeader(kind: kind, compression: compression, decodedByteCount: Int(decoded))
    }

    private static func append<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    /// The header fields that steps D13 and D14 need after D4 to D12 passed.
    private struct CheckedHeader {
        fileprivate let kind: DocumentPayloadKind
        fileprivate let compression: DocumentCompression
        fileprivate let decodedByteCount: Int
    }
}

/// CRC-32/ISO-HDLC: reflected polynomial 0xEDB88320, init/final xor 0xFFFFFFFF.
///
/// Slicing-by-8: each step folds eight bytes through eight 256-entry tables, read over raw buffers without copying.
/// Cancellation is checked before every 65,536 bytes and after the last byte.
internal enum DocumentStorageChecksum {
    /// Bytes processed between two cancellation checks.
    private static let block = 65_536

    /// Table `k` (entries `256 * k ..< 256 * (k + 1)`) maps a byte to its CRC contribution `k` bytes ahead.
    private static let tables: [UInt32] = {
        var tables = [UInt32](repeating: 0, count: 8 * 256)
        for value in 0..<256 {
            var crc = UInt32(value)
            for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320 }
            tables[value] = crc
        }
        for table in 1..<8 {
            for value in 0..<256 {
                let previous = tables[(table - 1) * 256 + value]
                tables[table * 256 + value] = (previous >> 8) ^ tables[Int(previous & 0xFF)]
            }
        }
        return tables
    }()

    /// CRC-32/ISO-HDLC of `header` followed by `payload`.
    /// The standard check value for ASCII `123456789` is 0xCBF43926.
    internal static func checksum(header: Data, payload: Data) throws -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        crc = try header.withUnsafeBytes { try update(crc, $0) }
        crc = try payload.withUnsafeBytes { try update(crc, $0) }
        return crc ^ 0xFFFF_FFFF
    }

    /// The CRC of a complete container: header bytes `0..<36`, then the payload from byte 40.
    internal static func containerChecksum(_ container: UnsafeRawBufferPointer) throws -> UInt32 {
        var crc = try update(0xFFFF_FFFF, UnsafeRawBufferPointer(rebasing: container[0..<36]))
        crc = try update(crc, UnsafeRawBufferPointer(rebasing: container[40...]))
        try DocumentStorageCancellation.check()
        return crc ^ 0xFFFF_FFFF
    }

    /// Folds `bytes` into a running (pre-inverted) CRC, checking cancellation before every 65,536 bytes.
    internal static func update(_ crc: UInt32, _ bytes: UnsafeRawBufferPointer) throws -> UInt32 {
        guard let base = bytes.baseAddress, !bytes.isEmpty else {
            try DocumentStorageCancellation.check()
            return crc
        }
        return try tables.withUnsafeBufferPointer { buffer in
            guard let table = buffer.baseAddress else { return crc }
            var crc = crc
            var offset = 0
            while offset < bytes.count {
                try DocumentStorageCancellation.check("checksum")
                let count = min(block, bytes.count - offset)
                crc = fold(crc, base + offset, count, table)
                offset += count
            }
            return crc
        }
    }

    @inline(__always)
    private static func fold(
        _ start: UInt32,
        _ base: UnsafeRawPointer,
        _ count: Int,
        _ table: UnsafePointer<UInt32>
    ) -> UInt32 {
        var crc = start
        var offset = 0
        while count - offset >= 8 {
            let word = UInt64(littleEndian: base.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            let low = UInt32(truncatingIfNeeded: word) ^ crc
            let high = UInt32(truncatingIfNeeded: word &>> 32)
            var next = table[0x700 | Int(low & 0xFF)] ^ table[0x600 | Int((low &>> 8) & 0xFF)]
            next ^= table[0x500 | Int((low &>> 16) & 0xFF)] ^ table[0x400 | Int(low &>> 24)]
            next ^= table[0x300 | Int(high & 0xFF)] ^ table[0x200 | Int((high &>> 8) & 0xFF)]
            next ^= table[0x100 | Int((high &>> 16) & 0xFF)] ^ table[Int(high &>> 24)]
            crc = next
            offset += 8
        }
        while offset < count {
            let byte = base.load(fromByteOffset: offset, as: UInt8.self)
            crc = (crc &>> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)]
            offset += 1
        }
        return crc
    }
}
