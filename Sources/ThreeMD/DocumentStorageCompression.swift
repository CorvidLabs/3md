import Foundation

#if canImport(Compression)
import Compression
#endif

internal enum DocumentStorageCompression {
    static func encode(_ data: Data, compression: DocumentCompression, maximumBytes: Int) throws -> Data {
        try DocumentStorageCancellation.check()
        switch compression {
        case .none:
            guard data.count <= maximumBytes else { throw DocumentStorageError.oversizedInput }
            return data
        case .lzfse:
            #if canImport(Compression)
            return try transcode(data, operation: COMPRESSION_STREAM_ENCODE, maximumBytes: maximumBytes)
            #else
            throw DocumentStorageError.compressionUnavailable(.lzfse)
            #endif
        }
    }

    static func decode(_ data: Data, compression: DocumentCompression, expectedBytes: Int) throws -> Data {
        try DocumentStorageCancellation.check()
        switch compression {
        case .none:
            guard data.count == expectedBytes else { throw DocumentStorageError.lengthMismatch }
            return data
        case .lzfse:
            #if canImport(Compression)
            return try transcode(data, operation: COMPRESSION_STREAM_DECODE, maximumBytes: expectedBytes)
            #else
            throw DocumentStorageError.compressionUnavailable(.lzfse)
            #endif
        }
    }

    #if canImport(Compression)
    /// Apple LZFSE's `bvx$` end marker is withheld until buffered prefix output has drained.
    /// This detects concatenated streams even when the Compression API consumes source through read-ahead.
    /// See Apple's format definitions: https://github.com/lzfse/lzfse/blob/master/src/lzfse_internal.h.
    private static func transcode(
        _ data: Data,
        operation: compression_stream_operation,
        maximumBytes: Int
    ) throws -> Data {
        let chunkSize = 65_536
        let endMarker: [UInt8] = [0x62, 0x76, 0x78, 0x24]
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { destination.deallocate() }
        var stream = compression_stream(
            dst_ptr: destination,
            dst_size: 0,
            src_ptr: UnsafePointer(destination),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, operation, COMPRESSION_LZFSE) == COMPRESSION_STATUS_OK else {
            throw DocumentStorageError.compressionFailed
        }
        defer { compression_stream_destroy(&stream) }
        return try data.withUnsafeBytes { source in
            let bytes = source.bindMemory(to: UInt8.self)
            guard let base = bytes.baseAddress, !bytes.isEmpty else { throw DocumentStorageError.lengthMismatch }
            let decoding = operation == COMPRESSION_STREAM_DECODE
            let withheld = decoding ? endMarker.count : 0
            if decoding {
                guard bytes.count > withheld, bytes.suffix(withheld).elementsEqual(endMarker) else {
                    throw DocumentStorageError.lengthMismatch
                }
            }
            var tailProvided = !decoding
            stream.src_ptr = base
            stream.src_size = bytes.count - withheld
            var output = Data(capacity: min(chunkSize, maximumBytes))
            while true {
                try DocumentStorageCancellation.check()
                stream.dst_ptr = destination
                stream.dst_size = chunkSize
                let inputBefore = stream.src_size
                let status = compression_stream_process(
                    &stream,
                    tailProvided ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                )
                let produced = chunkSize - stream.dst_size
                guard produced <= maximumBytes - output.count else {
                    throw decoding ? DocumentStorageError.lengthMismatch : DocumentStorageError.oversizedInput
                }
                output.append(destination, count: produced)
                switch status {
                case COMPRESSION_STATUS_END:
                    guard tailProvided, stream.src_size == 0, !decoding || output.count == maximumBytes else {
                        throw DocumentStorageError.lengthMismatch
                    }
                    try DocumentStorageCancellation.check()
                    return output
                case COMPRESSION_STATUS_OK:
                    if !tailProvided, stream.src_size == 0, produced == 0 {
                        stream.src_ptr = base.advanced(by: bytes.count - withheld)
                        stream.src_size = withheld
                        tailProvided = true
                        continue
                    }
                    guard produced > 0 || stream.src_size < inputBefore else {
                        throw DocumentStorageError.lengthMismatch
                    }
                default: throw DocumentStorageError.compressionFailed
                }
            }
        }
    }
    #endif
}
