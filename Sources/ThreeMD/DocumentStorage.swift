import Foundation

/// Synchronous storage stays usable below the deployment versions that introduced Swift concurrency.
internal enum DocumentStorageCancellation {
    internal static func check() throws {
        if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) { try Task.checkCancellation() }
    }
}

/// Compression identifiers for the independently versioned general-document binary container.
public enum DocumentCompression: UInt8, Sendable {
    /// Stores the canonical UTF-8 payload without compression on every platform.
    case none = 0
    /// Uses Apple's LZFSE backend when the platform provides the Compression framework.
    case lzfse = 1
}

/// Text remains the portable interchange format. Binary payloads contain canonical UTF-8 3md text.
public enum DocumentStorageFormat: Equatable, Sendable {
    /// Canonical readable UTF-8 3md with quoted scalar values.
    case text
    /// The versioned general-document container with the selected compression identifier.
    case binary(compression: DocumentCompression)
}

/// Explicit resource policy. Callers may lower bounds or raise the record bound up to the absolute 64 MiB ceiling.
public struct DocumentDecodeLimits: Equatable, Sendable {
    /// Maximum input or encoded output bytes, including any binary header.
    public let maximumEncodedBytes: Int
    /// Maximum decompressed or canonical readable payload bytes.
    public let maximumDecodedBytes: Int
    /// Maximum physical lines, including the empty final line after a trailing newline.
    public let maximumLines: Int
    /// Maximum parsed or directly supplied planes.
    public let maximumPlanes: Int
    /// Maximum UTF-8 bytes in a physical line, scalar field, preamble or complete plane body.
    public let maximumRecordBytes: Int

    /// Uses 64 MiB input/output, 100,000 lines, 65,536 planes and 8 MiB records.
    public static let standard = Self(unchecked: ())

    /// Creates a policy with positive limits no higher than 64 MiB, 100,000 lines or 65,536 planes.
    /// - Throws: `DocumentStorageError.invalidLimits` when any limit is outside its absolute bounds.
    public init(
        maximumEncodedBytes: Int = 64 * 1_024 * 1_024,
        maximumDecodedBytes: Int = 64 * 1_024 * 1_024,
        maximumLines: Int = 100_000,
        maximumPlanes: Int = 65_536,
        maximumRecordBytes: Int = 8 * 1_024 * 1_024
    ) throws {
        let bytes = 64 * 1_024 * 1_024
        guard (1...bytes).contains(maximumEncodedBytes), (1...bytes).contains(maximumDecodedBytes),
            (1...100_000).contains(maximumLines), (1...65_536).contains(maximumPlanes),
            (1...bytes).contains(maximumRecordBytes)
        else { throw DocumentStorageError.invalidLimits }
        self.maximumEncodedBytes = maximumEncodedBytes
        self.maximumDecodedBytes = maximumDecodedBytes
        self.maximumLines = maximumLines
        self.maximumPlanes = maximumPlanes
        self.maximumRecordBytes = maximumRecordBytes
    }

    private init(unchecked: Void) {
        maximumEncodedBytes = 64 * 1_024 * 1_024
        maximumDecodedBytes = 64 * 1_024 * 1_024
        maximumLines = 100_000
        maximumPlanes = 65_536
        maximumRecordBytes = 8 * 1_024 * 1_024
    }
}

/// A storage-policy, document-fidelity or binary-container failure. Cancellation remains `CancellationError`.
public enum DocumentStorageError: Error, LocalizedError, Equatable, Sendable {
    /// A caller-supplied resource limit is nonpositive or exceeds an absolute ceiling.
    case invalidLimits
    /// Encoded bytes exceed the input or encoded-output limit.
    case oversizedInput
    /// Canonical or decompressed payload bytes exceed the decoded-output limit.
    case oversizedOutput
    /// Physical lines exceed the line limit.
    case tooManyLines
    /// Parsed or supplied planes exceed the plane limit.
    case tooManyPlanes
    /// A physical line, scalar, preamble or plane body exceeds the record limit.
    case oversizedRecord
    /// The readable payload contains invalid UTF-8.
    case invalidUTF8
    /// The existing text parser rejected the payload with the supplied parse error.
    case invalidText(ParseError)
    /// A directly supplied document cannot survive faithful text serialization.
    case invalidDocument(String)
    /// A recognized binary container has an invalid header.
    case invalidContainer
    /// The header declares an unsupported independent container version.
    case unsupportedVersion(UInt16)
    /// The header declares a payload kind other than canonical UTF-8 3md.
    case unsupportedPayloadKind(UInt8)
    /// The header declares an unknown compression identifier.
    case unsupportedCompression(UInt8)
    /// The header declares nonzero unsupported feature flags.
    case unsupportedFlags(UInt32)
    /// A reserved header field is nonzero.
    case nonzeroReserved
    /// Declared lengths or compression boundaries are truncated, trailing or inconsistent.
    case lengthMismatch
    /// The CRC32 corruption checksum does not match the header and payload.
    case checksumMismatch
    /// The platform does not provide the requested compression backend.
    case compressionUnavailable(DocumentCompression)
    /// The native compression backend could not process the stream.
    case compressionFailed

    /// A localized explanation suitable for presenting a failed storage operation.
    public var errorDescription: String? {
        switch self {
        case .invalidLimits: return "Use positive storage limits within the documented absolute bounds."
        case .oversizedInput: return "The encoded document exceeds the input byte limit."
        case .oversizedOutput: return "The decoded document exceeds the output byte limit."
        case .tooManyLines: return "The document exceeds the physical line limit."
        case .tooManyPlanes: return "The document exceeds the plane limit."
        case .oversizedRecord: return "A line, scalar, preamble or plane body exceeds the record byte limit."
        case .invalidUTF8: return "The document payload is not valid UTF-8."
        case .invalidText(let error): return error.errorDescription
        case .invalidDocument(let detail): return "The document cannot be serialized faithfully: \(detail)"
        case .invalidContainer: return "The general 3md binary container header is invalid."
        case .unsupportedVersion(let version): return "Unsupported 3md binary container version \(version)."
        case .unsupportedPayloadKind(let kind): return "Unsupported 3md binary payload kind \(kind)."
        case .unsupportedCompression(let algorithm): return "Unsupported 3md compression identifier \(algorithm)."
        case .unsupportedFlags(let flags): return "Unsupported 3md binary flags \(flags)."
        case .nonzeroReserved: return "Reserved 3md binary header fields must be zero."
        case .lengthMismatch: return "The payload length or compression stream is truncated, trailing or inconsistent."
        case .checksumMismatch: return "The 3md container corruption checksum does not match."
        case .compressionUnavailable(let algorithm):
            return "Compression \(algorithm.rawValue) is unavailable on this platform."
        case .compressionFailed: return "The document compression stream could not be processed."
        }
    }
}
