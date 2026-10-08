import Foundation

#if canImport(Compression)
import Compression
#endif
#if canImport(CLzfse)
import CLzfse
#endif

/// App-specific `.3mdb` storage, independent of readable ThreeMD documents.
///
/// Version 1 layout (all integers little endian):
/// - 0..<8: `3MDB\r\n\u{1A}\n` magic.
/// - 8..<12: UInt16 version 1, UInt8 compression 1 (LZFSE), UInt8 reserved 0.
/// - 12..<20: UInt16 width, height, depth, and printable ASCII title byte count.
/// - 20..<28: UInt32 uncompressed voxel count and compressed stream byte count.
/// - 28..<60: SHA256 of bytes 0..<28, title bytes, then uncompressed voxel bytes.
/// - 60...: title, then exactly one complete LZFSE stream with no trailing bytes.
///
/// Voxel bytes are slice-major, then row-major: `(z * height + y) * width + x`.
/// The checksum detects corruption; it does not authenticate the file's author.
public enum SculptureBinaryCodec {
    public static let maximumBytes = SculptureCodec.maximumBytes
    private static let magic: [UInt8] = [0x33, 0x4D, 0x44, 0x42, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let headerSize = 60
    private static let checksumOffset = 28
    private static let version: UInt16 = 1
    private static let compressionIdentifier: UInt8 = 1
    private static let chunkSize = 65_536
    // LZFSE_ENDOFSTREAM_BLOCK_MAGIC = 0x24787662 ("bvx$") in Apple's open-source lzfse_internal.h.
    private static let endMarker: [UInt8] = [0x62, 0x76, 0x78, 0x24]

    public static func encode(_ sculpture: Sculpture) throws -> Data {
        try Task.checkCancellation()
        let voxelCount = sculpture.width * sculpture.height * sculpture.depth
        let title = Data(sculpture.title.utf8)
        var voxels = Data(capacity: voxelCount)
        for layer in sculpture.layers {
            try Task.checkCancellation()
            voxels.append(contentsOf: layer)
        }
        let compressed = try transcode(
            voxels,
            operation: .encode,
            maximumOutput: maximumBytes - headerSize - title.count
        )
        var header = Data(magic)
        append(version, to: &header)
        header.append(compressionIdentifier)
        header.append(0)
        append(UInt16(sculpture.width), to: &header)
        append(UInt16(sculpture.height), to: &header)
        append(UInt16(sculpture.depth), to: &header)
        append(UInt16(title.count), to: &header)
        append(UInt32(voxelCount), to: &header)
        append(UInt32(compressed.count), to: &header)
        header.append(checksum(header: header, title: title, voxels: voxels))
        try Task.checkCancellation()
        header.append(title)
        header.append(compressed)
        return header
    }

    public static func decode(_ data: Data) throws -> Sculpture {
        guard data.count <= maximumBytes else { throw SculptureError.oversizedFile }
        try Task.checkCancellation()
        guard data.count >= headerSize, hasMagic(data) else { throw SculptureBinaryCodecError.invalidHeader }
        let declaredVersion = uint16(data, at: 8)
        guard declaredVersion == version else { throw SculptureBinaryCodecError.unsupportedVersion(declaredVersion) }
        let compression = byte(data, at: 10)
        guard compression == compressionIdentifier else {
            throw SculptureBinaryCodecError.unsupportedCompression(compression)
        }
        guard byte(data, at: 11) == 0 else { throw SculptureBinaryCodecError.invalidHeader }
        let width = Int(uint16(data, at: 12))
        let height = Int(uint16(data, at: 14))
        let depth = Int(uint16(data, at: 16))
        guard (1...Sculpture.maximumDimension).contains(width), (1...Sculpture.maximumDimension).contains(height),
            (1...Sculpture.maximumDimension).contains(depth)
        else { throw SculptureError.invalidDimensions }
        let titleCount = Int(uint16(data, at: 18))
        guard (1...80).contains(titleCount) else { throw SculptureError.invalidTitle }
        let voxelCount = width * height * depth
        let compressedCount = Int(uint32(data, at: 24))
        guard Int(uint32(data, at: 20)) == voxelCount, (1...maximumBytes).contains(compressedCount),
            data.count == headerSize + titleCount + compressedCount
        else { throw SculptureBinaryCodecError.invalidLength }
        let title = Data(data.dropFirst(headerSize).prefix(titleCount))
        guard title.allSatisfy({ (32...126).contains($0) }) else { throw SculptureError.invalidTitle }
        let voxels = try transcode(
            data,
            range: (headerSize + titleCount)..<data.count,
            operation: .decode,
            maximumOutput: voxelCount,
            expectedOutput: voxelCount
        )
        let expectedChecksum = Data(data.dropFirst(checksumOffset).prefix(SculptureSHA256.byteCount))
        guard checksum(header: Data(data.prefix(checksumOffset)), title: title, voxels: voxels) == expectedChecksum
        else {
            throw SculptureBinaryCodecError.checksumMismatch
        }
        try Task.checkCancellation()
        let layerSize = width * height
        let layers = try voxels.withUnsafeBytes { buffer -> [[UInt8]] in
            let bytes = buffer.bindMemory(to: UInt8.self)
            return try (0..<depth).map { z in
                try Task.checkCancellation()
                return Array(bytes[(z * layerSize)..<((z + 1) * layerSize)])
            }
        }
        let sculpture = try Sculpture(
            title: String(decoding: title, as: UTF8.self),
            width: width,
            height: height,
            layers: layers
        )
        try Task.checkCancellation()
        return sculpture
    }

    /// Reads the declared voxel dimensions from a native compact header without decompressing the volume.
    /// Returns nil unless the data starts with a complete, supported version 1 header.
    public static func dimensions(inHeader data: Data) -> (width: Int, height: Int, depth: Int)? {
        guard data.count >= headerSize, hasMagic(data), uint16(data, at: 8) == version else { return nil }
        let width = Int(uint16(data, at: 12))
        let height = Int(uint16(data, at: 14))
        let depth = Int(uint16(data, at: 16))
        guard [width, height, depth].allSatisfy({ (1...Sculpture.maximumDimension).contains($0) }) else { return nil }
        return (width, height, depth)
    }

    internal static func hasMagic(_ data: Data) -> Bool {
        data.prefix(magic.count).elementsEqual(magic)
    }

    internal static func compressedPayload(for voxels: Data) throws -> Data {
        try transcode(voxels, operation: .encode, maximumOutput: maximumBytes)
    }

    private static func checksum(header: Data, title: Data, voxels: Data) -> Data {
        var material = Data(capacity: header.count + title.count + voxels.count)
        material.append(header)
        material.append(title)
        material.append(voxels)
        return SculptureSHA256.hash(material)
    }

    private enum TranscodeOperation {
        case encode
        case decode
    }

    /// Processing stays inside both buffer lifetimes. Output is bounded before each append.
    private static func transcode(
        _ input: Data,
        range: Range<Int>? = nil,
        operation: TranscodeOperation,
        maximumOutput: Int,
        expectedOutput: Int? = nil
    ) throws -> Data {
        // Linux Data slices keep a non-zero start index. Integer ranges below are offsets from the
        // first byte, which is how Apple Data already addresses every value.
        let input = input.startIndex == 0 ? input : Data(input)
        #if canImport(Compression)
        return try appleTranscode(
            input,
            range: range,
            operation: operation,
            maximumOutput: maximumOutput,
            expectedOutput: expectedOutput
        )
        #else
        return try linuxTranscode(
            input,
            range: range,
            operation: operation,
            maximumOutput: maximumOutput,
            expectedOutput: expectedOutput
        )
        #endif
    }

    #if canImport(Compression)
    private static func appleTranscode(
        _ input: Data,
        range: Range<Int>?,
        operation: TranscodeOperation,
        maximumOutput: Int,
        expectedOutput: Int?
    ) throws -> Data {
        let streamOperation: compression_stream_operation =
            operation == .encode ? COMPRESSION_STREAM_ENCODE : COMPRESSION_STREAM_DECODE
        let range = range ?? 0..<input.count
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { destination.deallocate() }
        var stream = compression_stream(
            dst_ptr: destination,
            dst_size: 0,
            src_ptr: UnsafePointer(destination),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, streamOperation, COMPRESSION_LZFSE) == COMPRESSION_STATUS_OK else {
            throw SculptureBinaryCodecError.compressionFailed
        }
        defer { compression_stream_destroy(&stream) }
        return try input.withUnsafeBytes { source -> Data in
            let bytes = source.bindMemory(to: UInt8.self)
            guard let base = bytes.baseAddress, !range.isEmpty else {
                throw SculptureBinaryCodecError.invalidLength
            }
            let isDecoding = streamOperation == COMPRESSION_STREAM_DECODE
            let withheldCount = isDecoding ? endMarker.count : 0
            if isDecoding {
                guard range.count > withheldCount,
                    bytes[(range.upperBound - withheldCount)..<range.upperBound].elementsEqual(endMarker)
                else { throw SculptureBinaryCodecError.invalidLength }
            }
            var tailProvided = !isDecoding
            stream.src_ptr = base.advanced(by: range.lowerBound)
            stream.src_size = range.count - withheldCount
            var output = Data(capacity: min(expectedOutput ?? chunkSize, maximumOutput))
            while true {
                try Task.checkCancellation()
                stream.dst_ptr = destination
                stream.dst_size = chunkSize
                let remainingInput = stream.src_size
                let flags = tailProvided ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                let status = compression_stream_process(&stream, flags)
                let produced = chunkSize - stream.dst_size
                guard produced <= maximumOutput - output.count else { throw SculptureBinaryCodecError.invalidLength }
                output.append(destination, count: produced)
                switch status {
                case COMPRESSION_STATUS_END:
                    guard tailProvided, stream.src_size == 0, expectedOutput.map({ $0 == output.count }) ?? true else {
                        throw SculptureBinaryCodecError.invalidLength
                    }
                    try Task.checkCancellation()
                    return output
                case COMPRESSION_STATUS_OK:
                    // Apple may copy source into a read-ahead buffer. Drain its buffered output before
                    // supplying the final marker; END during this prefix rejects an earlier concatenated stream.
                    if !tailProvided, stream.src_size == 0, produced == 0 {
                        stream.src_ptr = base.advanced(by: range.upperBound - withheldCount)
                        stream.src_size = withheldCount
                        tailProvided = true
                        continue
                    }
                    guard produced > 0 || stream.src_size < remainingInput else {
                        throw SculptureBinaryCodecError.corruptPayload
                    }
                default:
                    throw streamOperation == COMPRESSION_STREAM_DECODE
                        ? SculptureBinaryCodecError.corruptPayload : SculptureBinaryCodecError.compressionFailed
                }
            }
        }
    }
    #else
    private static func linuxTranscode(
        _ input: Data,
        range: Range<Int>?,
        operation: TranscodeOperation,
        maximumOutput: Int,
        expectedOutput: Int?
    ) throws -> Data {
        let range = range ?? 0..<input.count
        guard !range.isEmpty, maximumOutput > 0 else { throw SculptureBinaryCodecError.invalidLength }
        let slice = Data(input[range])
        switch operation {
        case .encode:
            return try lzfseEncode(slice, maximumOutput: maximumOutput)
        case .decode:
            guard slice.count > endMarker.count, slice.suffix(endMarker.count).elementsEqual(endMarker) else {
                throw SculptureBinaryCodecError.invalidLength
            }
            let expected = expectedOutput ?? maximumOutput
            let decoded = try lzfseDecode(slice, expected: expected, maximumOutput: maximumOutput)
            // The declared volume can be smaller than a valid LZFSE frame. Re-encode against the
            // original frame so trailing or concatenated bytes fail closed.
            let encodeLimit = min(
                maximumBytes,
                max(slice.count, decoded.count + max(decoded.count / 8, 64) + 4096)
            )
            let again = try lzfseEncode(decoded, maximumOutput: encodeLimit)
            guard again == slice else { throw SculptureBinaryCodecError.invalidLength }
            return decoded
        }
    }

    private static func lzfseEncode(_ input: Data, maximumOutput: Int) throws -> Data {
        try Task.checkCancellation()
        guard maximumOutput > 0, !input.isEmpty else { throw SculptureBinaryCodecError.invalidLength }
        let capacity = min(maximumOutput, input.count + max(input.count / 8, 64) + 4096)
        return try input.withUnsafeBytes { raw in
            guard let source = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw SculptureBinaryCodecError.invalidLength
            }
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { destination.deallocate() }
            let written = lzfse_encode_buffer(destination, capacity, source, input.count, nil)
            guard written > 0, written <= maximumOutput else { throw SculptureBinaryCodecError.compressionFailed }
            try Task.checkCancellation()
            return Data(UnsafeBufferPointer(start: destination, count: written))
        }
    }

    private static func lzfseDecode(_ input: Data, expected: Int, maximumOutput: Int) throws -> Data {
        try Task.checkCancellation()
        guard expected > 0, expected <= maximumOutput else { throw SculptureBinaryCodecError.invalidLength }
        return try input.withUnsafeBytes { raw in
            guard let source = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw SculptureBinaryCodecError.invalidLength
            }
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: expected)
            defer { destination.deallocate() }
            let written = lzfse_decode_buffer(destination, expected, source, input.count, nil)
            guard written == expected else { throw SculptureBinaryCodecError.invalidLength }
            try Task.checkCancellation()
            return Data(UnsafeBufferPointer(start: destination, count: written))
        }
    }
    #endif

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func byte(_ data: Data, at offset: Int) -> UInt8 {
        data[data.index(data.startIndex, offsetBy: offset)]
    }

    private static func uint16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(byte(data, at: offset)) | UInt16(byte(data, at: offset + 1)) << 8
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(byte(data, at: offset + $1)) << ($1 * 8) }
    }
}

public enum SculptureBinaryCodecError: Error, LocalizedError, Equatable, Sendable {
    case invalidHeader
    case unsupportedVersion(UInt16)
    case unsupportedCompression(UInt8)
    case invalidLength
    case corruptPayload
    case checksumMismatch
    case compressionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidHeader: "Open a valid compact .3mdb sculpture."
        case .unsupportedVersion(let version): "This compact sculpture uses unsupported version \(version)."
        case .unsupportedCompression(let compression): "Unsupported compact sculpture compression \(compression)."
        case .invalidLength: "The compact sculpture has an invalid or mismatched payload length."
        case .corruptPayload: "The compressed voxel stream is corrupt, truncated, or contains trailing bytes."
        case .checksumMismatch: "The compact sculpture checksum does not match. The file may be corrupt."
        case .compressionFailed: "The sculpture could not be compressed."
        }
    }
}
