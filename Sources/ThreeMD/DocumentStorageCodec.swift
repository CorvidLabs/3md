import Foundation

/// Bounded storage for general documents, independent of their axis or application-specific metadata.
///
/// Version 1 has a 40-byte little-endian header: magic `3mdbin\r\n` (8 bytes), version u16 (1),
/// payload kind u8 (1 = canonical UTF-8 3md), compression u8, flags u32 (0), reserved u32 (0),
/// encoded payload bytes u64, decoded payload bytes u64, and CRC-32/ISO-HDLC u32.
/// CRC covers header bytes 0..<36 followed by encoded payload; it excludes the checksum field.
/// CRC detects corruption, not authorship. This magic is distinct from Rook's older voxel-specific `3MDB` format.
public enum DocumentStorageCodec {
    /// The independently versioned binary-container version emitted and accepted by this codec.
    public static let containerVersion: UInt16 = 1
    /// The fixed version 1 binary header size in bytes.
    public static let headerByteCount = 40
    internal static let magic = Data("3mdbin\r\n".utf8)

    /// Recognizes the complete magic prefix without validating the header, payload or checksum.
    public static func isBinary(_ data: Data) -> Bool { data.prefix(magic.count).elementsEqual(magic) }

    /// Checks finite unique plane positions and a faithful bounded canonical-text round trip.
    /// - Throws: `DocumentStorageError` for invalid values or exceeded policies, or `CancellationError` when supported.
    public static func validate(_ document: Document, limits: DocumentDecodeLimits = .standard) throws {
        _ = try DocumentStorageValidation.canonicalData(document, limits: limits)
    }

    /// Produces canonical readable text or a checksummed binary container without changing the existing serializer.
    /// - Throws: `DocumentStorageError` for invalid documents, limits or unavailable compression;
    ///   cancellation remains `CancellationError` on platforms supporting Swift concurrency.
    public static func encode(
        _ document: Document,
        format: DocumentStorageFormat = .text,
        limits: DocumentDecodeLimits = .standard
    ) throws -> Data {
        let source = try DocumentStorageValidation.canonicalData(document, limits: limits)
        switch format {
        case .text:
            guard source.count <= limits.maximumEncodedBytes else { throw DocumentStorageError.oversizedInput }
            return source
        case .binary(let compression):
            guard limits.maximumEncodedBytes >= headerByteCount else { throw DocumentStorageError.oversizedInput }
            let payload = try DocumentStorageCompression.encode(
                source,
                compression: compression,
                maximumBytes: limits.maximumEncodedBytes - headerByteCount
            )
            var header = magic
            append(containerVersion, to: &header)
            header.append(1)
            header.append(compression.rawValue)
            append(UInt32(0), to: &header)
            append(UInt32(0), to: &header)
            append(UInt64(payload.count), to: &header)
            append(UInt64(source.count), to: &header)
            let checksum = try DocumentStorageChecksum.checksum(header: header, payload: payload)
            append(checksum, to: &header)
            header.append(payload)
            try DocumentStorageCancellation.check()
            return header
        }
    }

    /// Autodetects readable text or the binary magic, then validates resource limits, stream boundaries and integrity.
    /// - Throws: `DocumentStorageError` for malformed or oversized input;
    ///   cancellation remains `CancellationError` on platforms supporting Swift concurrency.
    public static func decode(_ data: Data, limits: DocumentDecodeLimits = .standard) throws -> Document {
        try DocumentStorageCancellation.check()
        guard data.count <= limits.maximumEncodedBytes else { throw DocumentStorageError.oversizedInput }
        guard isBinary(data) else { return try DocumentStorageValidation.parse(data, limits: limits) }
        guard data.count >= headerByteCount else { throw DocumentStorageError.invalidContainer }
        let version: UInt16 = integer(data, at: 8)
        guard version == containerVersion else { throw DocumentStorageError.unsupportedVersion(version) }
        let kind = byte(data, at: 10)
        guard kind == 1 else { throw DocumentStorageError.unsupportedPayloadKind(kind) }
        let algorithm = byte(data, at: 11)
        guard let compression = DocumentCompression(rawValue: algorithm) else {
            throw DocumentStorageError.unsupportedCompression(algorithm)
        }
        let flags: UInt32 = integer(data, at: 12)
        guard flags == 0 else { throw DocumentStorageError.unsupportedFlags(flags) }
        let reserved: UInt32 = integer(data, at: 16)
        guard reserved == 0 else { throw DocumentStorageError.nonzeroReserved }
        let encoded: UInt64 = integer(data, at: 20)
        let decoded: UInt64 = integer(data, at: 28)
        guard decoded <= UInt64(limits.maximumDecodedBytes) else { throw DocumentStorageError.oversizedOutput }
        guard encoded > 0, decoded > 0, encoded == UInt64(data.count - headerByteCount) else {
            throw DocumentStorageError.lengthMismatch
        }
        guard compression != .none || encoded == decoded else { throw DocumentStorageError.lengthMismatch }
        let payload = Data(data.dropFirst(headerByteCount))
        let declared: UInt32 = integer(data, at: 36)
        let checksum = try DocumentStorageChecksum.checksum(header: Data(data.prefix(36)), payload: payload)
        guard checksum == declared else { throw DocumentStorageError.checksumMismatch }
        let source = try DocumentStorageCompression.decode(
            payload,
            compression: compression,
            expectedBytes: Int(decoded)
        )
        return try DocumentStorageValidation.parse(source, limits: limits)
    }

    private static func append<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func byte(_ data: Data, at offset: Int) -> UInt8 {
        data[data.index(data.startIndex, offsetBy: offset)]
    }

    private static func integer<Value: FixedWidthInteger>(_ data: Data, at offset: Int) -> Value {
        (0..<MemoryLayout<Value>.size).reduce(0) { $0 | Value(byte(data, at: offset + $1)) << ($1 * 8) }
    }
}

internal enum DocumentStorageChecksum {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320 }
        return crc
    }

    /// CRC-32/ISO-HDLC: reflected polynomial 0xEDB88320, init/final xor 0xFFFFFFFF.
    /// The standard check value for ASCII `123456789` is 0xCBF43926.
    static func checksum(header: Data, payload: Data) throws -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for data in [header, payload] {
            for (index, byte) in data.enumerated() {
                if index.isMultiple(of: 65_536) { try DocumentStorageCancellation.check() }
                crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)]
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
