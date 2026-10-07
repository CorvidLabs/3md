import Foundation

/// Synchronous storage stays usable below the deployment versions that introduced Swift concurrency.
internal enum DocumentStorageCancellation {
    /// Throws `CancellationError` when the current task is cancelled; a no-op without Swift concurrency.
    /// - Parameter site: The checkpoint's name, recorded by the debug-only test probe.
    internal static func check(_ site: StaticString = #function) throws {
        if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
            #if DEBUG
            DocumentStorageProbe.current?.reach(site)
            #endif
            try Task.checkCancellation()
        }
    }
}

#if DEBUG
/// Debug-only test instrumentation: counts cancellation checkpoints and Phase Q parses of the current task, and can
/// cancel the task at a chosen checkpoint so tests reach cancellation points deterministically.
///
/// `@unchecked Sendable` is justified: every mutable property is read and written only while holding `lock`.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal final class DocumentStorageProbe: @unchecked Sendable {
    // MARK: - Properties

    /// The probe of the current task, if a test installed one.
    @TaskLocal internal static var current: DocumentStorageProbe?

    private let lock = NSLock()
    private let target: String?
    private let occurrence: Int
    private var counts: [String: Int] = [:]
    private var parseCount = 0
    private var cancelled = false

    // MARK: - Initializers

    /// Creates a probe that cancels the current task when checkpoint `site` is reached for the `occurrence`th time.
    /// - Parameters:
    ///   - site: The checkpoint name to cancel at, or `nil` to only count.
    ///   - occurrence: The 1-based number of the matching checkpoint that cancels.
    internal init(cancellingAt site: String? = nil, occurrence: Int = 1) {
        target = site
        self.occurrence = occurrence
    }

    // MARK: - Internal Methods

    /// How many times checkpoint `site` was reached.
    internal func count(_ site: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[site] ?? 0
    }

    /// How many Phase Q parses ran.
    internal var phaseQParses: Int {
        lock.lock()
        defer { lock.unlock() }
        return parseCount
    }

    /// Whether the probe cancelled its task.
    internal var didCancel: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Records a checkpoint and cancels the current task when it is the target.
    internal func reach(_ site: StaticString) {
        let name = site.description
        lock.lock()
        let reached = (counts[name] ?? 0) + 1
        counts[name] = reached
        let cancel = !cancelled && name == target && reached == occurrence
        if cancel { cancelled = true }
        lock.unlock()
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
    }

    /// Records one Phase Q parse.
    internal func recordParse() {
        lock.lock()
        parseCount += 1
        lock.unlock()
    }
}
#endif

/// Compression identifiers for the independently versioned general-document binary container.
public enum DocumentCompression: UInt8, Sendable {
    /// Stores the payload without compression on every platform.
    case none = 0
    /// Uses Apple's LZFSE backend when the platform provides the Compression framework.
    case lzfse = 1
}

/// Text remains the portable interchange format. `.binary` writes the structured document payload (SPEC 11.3).
public enum DocumentStorageFormat: Equatable, Sendable {
    /// Canonical readable UTF-8 3md with quoted scalar values.
    case text
    /// The version 1 container with a structured document payload and the selected compression identifier.
    case binary(compression: DocumentCompression)
}

/// A payload kind in the version 1 general binary container (header byte 10).
///
/// A struct rather than an enum, so future kinds are additive and never break an exhaustive `switch`.
public struct DocumentPayloadKind: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    // MARK: - Properties

    /// The header byte at offset 10.
    public let rawValue: UInt8

    /// Canonical UTF-8 3md text behind the binary header (ThreeMD 2.0, SPEC 11.1).
    public static let canonicalText = DocumentPayloadKind(rawValue: 1)

    /// Structured document records (ThreeMD 2.1, SPEC 11.3).
    public static let structuredDocument = DocumentPayloadKind(rawValue: 2)

    /// `canonicalText`, `structuredDocument`, or `reserved(N)`.
    public var description: String {
        switch rawValue {
        case 1: return "canonicalText"
        case 2: return "structuredDocument"
        default: return "reserved(\(rawValue))"
        }
    }

    // MARK: - Initializers

    /// Creates a kind from its header byte. Every value is representable, including reserved ones.
    /// - Parameter rawValue: The header byte.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

/// The raw fixed header fields of a binary container, reported without validating them, the payload or the checksum.
public struct DocumentContainerInfo: Hashable, Sendable {
    // MARK: - Properties

    /// The independent container version; 1 for every payload kind in ThreeMD 2.1.
    public let containerVersion: UInt16
    /// The payload kind byte.
    public let payloadKind: DocumentPayloadKind
    /// The raw compression identifier; compare it with `DocumentCompression.rawValue`.
    public let compression: UInt8
    /// The raw feature flags.
    public let flags: UInt32
    /// The raw reserved field.
    public let reserved: UInt32
    /// The declared encoded payload byte count.
    public let encodedPayloadByteCount: UInt64
    /// The declared decoded (uncompressed) payload byte count.
    public let decodedPayloadByteCount: UInt64
    /// The declared CRC-32/ISO-HDLC value.
    public let checksum: UInt32

    // MARK: - Initializers

    /// Reads the fixed fields of a header whose first 40 bytes are present.
    /// - Parameter header: At least 40 bytes, starting with the magic.
    internal init(header: UnsafeRawBufferPointer) {
        containerVersion = UInt16(littleEndian: header.loadUnaligned(fromByteOffset: 8, as: UInt16.self))
        payloadKind = DocumentPayloadKind(rawValue: header[10])
        compression = header[11]
        flags = UInt32(littleEndian: header.loadUnaligned(fromByteOffset: 12, as: UInt32.self))
        reserved = UInt32(littleEndian: header.loadUnaligned(fromByteOffset: 16, as: UInt32.self))
        encodedPayloadByteCount = UInt64(littleEndian: header.loadUnaligned(fromByteOffset: 20, as: UInt64.self))
        decodedPayloadByteCount = UInt64(littleEndian: header.loadUnaligned(fromByteOffset: 28, as: UInt64.self))
        checksum = UInt32(littleEndian: header.loadUnaligned(fromByteOffset: 36, as: UInt32.self))
    }
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
    /// Canonical, decompressed or structured payload bytes exceed the decoded-output limit.
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
    /// A recognized binary container has an invalid header or structured payload encoding.
    case invalidContainer
    /// The header declares an unsupported independent container version.
    case unsupportedVersion(UInt16)
    /// The header declares a payload kind this operation does not accept.
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
        case .invalidContainer: return "The binary container or its structured payload encoding is invalid."
        case .unsupportedVersion(let version): return "Unsupported 3md binary container version \(version)."
        case .unsupportedPayloadKind(let kind):
            return "Unsupported 3md binary payload kind \(kind) for this operation."
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
