import Foundation

/// A structured issue that can be presented without parsing a localized error message.
public struct DocumentDiagnostic: Equatable, Codable, Sendable {
    /// Stable codes for identity, transaction and document validation failures.
    public enum Code: String, Codable, Sendable {
        case invalidIdentity, duplicateIdentity, missingIdentity, missingTarget, identityChanged
        case staleRevision, invalidIndex, duplicatePosition, invalidDocument
        case invalidComposition, operationLimit, payloadLimit, invalidLimits
        case parseFailure
    }

    /// Whether an issue prevents an operation or only describes legacy content.
    public enum Severity: String, Codable, Sendable { case error, warning }

    /// The stable issue category for programmatic handling.
    public let code: Code
    /// An explanation suitable for presenting next to the affected content.
    public let message: String
    /// Whether the issue prevents an operation.
    public let severity: Severity
    /// Actual parser line evidence only. Value-only diagnostics never invent a source line.
    public let sourceLine: Int?
    /// An exact structural path, such as `planes[2].attributes[3md-id]`.
    public let path: String?

    /// Creates a diagnostic from evidence actually available to its producer.
    public init(
        code: Code,
        message: String,
        severity: Severity = .error,
        sourceLine: Int? = nil,
        path: String? = nil
    ) {
        self.code = code
        self.message = message
        self.severity = severity
        self.sourceLine = sourceLine
        self.path = path
    }
}

/// A failed transaction publishes no partially edited value. Cancellation stays `CancellationError`.
public struct DocumentEditError: Error, Equatable, Sendable, LocalizedError {
    /// The structured explanation of the rejected transaction.
    public let diagnostic: DocumentDiagnostic
    /// The explanation suitable for ordinary error presentation.
    public var errorDescription: String? { diagnostic.message }
    /// Creates an error without changing its structured evidence.
    public init(_ diagnostic: DocumentDiagnostic) { self.diagnostic = diagnostic }
}

/// Exact canonical expected content, not a hash, counter, signature or authorization claim.
public struct DocumentRevision: Equatable, Hashable, Codable, Sendable {
    /// The complete canonical readable document or composition profile source.
    public let canonicalContent: String
    /// Creates an expected-content precondition. Callers normally use a snapshot's revision.
    public init(canonicalContent: String) { self.canonicalContent = canonicalContent }

    /// Swift String equality normalizes Unicode; revision preconditions compare the actual UTF-8 bytes.
    public static func == (lhs: DocumentRevision, rhs: DocumentRevision) -> Bool {
        lhs.canonicalContent.utf8.elementsEqual(rhs.canonicalContent.utf8)
    }

    /// Hashes exact bytes consistently with revision equality; the hash is never used for revision matching.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(canonicalContent.utf8.count)
        for byte in canonicalContent.utf8 { hasher.combine(byte) }
    }
}

/// Independent ceilings for transaction payloads and bounded diagnostic collection.
public struct DocumentEditLimits: Equatable, Sendable {
    /// Maximum operations in a single atomic patch.
    public let maximumOperations: Int
    /// Maximum charged UTF-8 operand payload, excluding the separately bounded expected revision.
    public let maximumPayloadBytes: Int
    /// Maximum collected issues before inspection reports an uninspected remainder.
    public let maximumDiagnostics: Int
    /// Maximum charged document or source bytes examined by diagnostic collection.
    public let maximumDiagnosticBytes: Int
    /// Default limits for interactive editing and inspection.
    public static let standard = DocumentEditLimits(defaults: ())

    /// Limits can be lowered but cannot exceed 4,096 operations, 64 MiB or 1,024 diagnostics.
    public init(
        maximumOperations: Int = 1_024,
        maximumPayloadBytes: Int = 16 * 1_024 * 1_024,
        maximumDiagnostics: Int = 256,
        maximumDiagnosticBytes: Int = 64 * 1_024 * 1_024
    ) throws {
        guard (0...4_096).contains(maximumOperations), (1...64 * 1_024 * 1_024).contains(maximumPayloadBytes),
            (1...1_024).contains(maximumDiagnostics), (1...64 * 1_024 * 1_024).contains(maximumDiagnosticBytes)
        else { throw EditingFailure.make(.invalidLimits, "Editing limits exceed their supported bounds.") }
        self.maximumOperations = maximumOperations
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumDiagnostics = maximumDiagnostics
        self.maximumDiagnosticBytes = maximumDiagnosticBytes
    }

    private init(defaults: Void) {
        maximumOperations = 1_024
        maximumPayloadBytes = 16 * 1_024 * 1_024
        maximumDiagnostics = 256
        maximumDiagnosticBytes = 64 * 1_024 * 1_024
    }
}

/// Non-plane fields replaced together, preserving the existing document value model.
public struct DocumentHeader: Hashable, Codable, Sendable {
    /// The preserved format version.
    public let version: String
    /// The preserved axis meaning.
    public let axis: Axis
    /// The optional document title.
    public let title: String?
    /// Opaque nonreserved frontmatter fields.
    public let metadata: [String: String]
    /// Optional Markdown before the first plane.
    public let preamble: String?

    /// Creates fields to replace together without rebuilding individual planes.
    public init(
        version: String,
        axis: Axis,
        title: String? = nil,
        metadata: [String: String] = [:],
        preamble: String? = nil
    ) {
        self.version = version
        self.axis = axis
        self.title = title
        self.metadata = metadata
        self.preamble = preamble
    }

    /// Captures the existing non-plane fields unchanged.
    public init(_ document: Document) {
        self.init(
            version: document.version,
            axis: document.axis,
            title: document.title,
            metadata: document.metadata,
            preamble: document.preamble
        )
    }

    internal func document(planes: [Plane]) -> Document {
        Document(
            version: version,
            axis: axis,
            title: title,
            metadata: metadata,
            preamble: preamble,
            planes: planes
        )
    }
}

/// Source-order edits, targeting namespaced stable IDs rather than positions or coordinates.
public enum DocumentEdit: Equatable, Codable, Sendable {
    case insert(plane: Plane, at: Int)
    case remove(id: String)
    case replace(id: String, plane: Plane)
    case move(id: String, to: Int)
    case replaceHeader(DocumentHeader)
}

/// A transaction against one exact expected canonical document.
public struct DocumentPatch: Equatable, Codable, Sendable {
    /// Exact canonical content that must still match the current snapshot.
    public let expectedRevision: DocumentRevision
    /// Ordered operations whose final result must validate as one document.
    public let operations: [DocumentEdit]
    /// Creates a patch without applying it or mutating a document.
    public init(expectedRevision: DocumentRevision, operations: [DocumentEdit]) {
        self.expectedRevision = expectedRevision
        self.operations = operations
    }
}

internal enum EditingFailure {
    static func propagateCancellation(_ error: any Error) throws {
        if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *), error is CancellationError { throw error }
    }

    static func make(_ code: DocumentDiagnostic.Code, _ message: String, path: String? = nil) -> DocumentEditError {
        DocumentEditError(.init(code: code, message: message, path: path))
    }

    static func document(_ error: any Error, path: String? = nil) -> DocumentEditError {
        make(.invalidDocument, error.localizedDescription, path: path)
    }
}

/// Charges before serialization or repeated mutation. All strings count UTF-8 bytes plus a record separator.
internal struct EditingPayloadBudget {
    let maximumBytes: Int
    var used = 0

    mutating func charge(_ text: String) throws {
        try DocumentStorageCancellation.check()
        let bytes = text.utf8.count
        guard bytes < maximumBytes - used else {
            throw EditingFailure.make(.payloadLimit, "The edit payload exceeds its UTF-8 byte budget.")
        }
        used += bytes + 1
    }

    mutating func attributes(_ attributes: [String: String]) throws {
        guard attributes.count <= (maximumBytes - used) / 2 else {
            throw EditingFailure.make(.payloadLimit, "The edit attribute payload exceeds its byte budget.")
        }
        for (key, value) in attributes { try charge(key); try charge(value) }
    }

    mutating func plane(_ plane: Plane) throws {
        try charge(plane.body)
        if let label = plane.label { try charge(label) }
        try attributes(plane.attributes)
        try charge(String(plane.z))
        if let x = plane.x { try charge(String(x)) }
        if let y = plane.y { try charge(String(y)) }
    }

    mutating func header(_ header: DocumentHeader) throws {
        try charge(header.version); try charge(header.axis.rawValue)
        if let title = header.title { try charge(title) }
        if let preamble = header.preamble { try charge(preamble) }
        try attributes(header.metadata)
    }

    mutating func document(_ document: Document) throws {
        try header(DocumentHeader(document))
        guard document.planes.count <= maximumBytes - used else {
            throw EditingFailure.make(.payloadLimit, "The edit plane payload exceeds its byte budget.")
        }
        for plane in document.planes { try self.plane(plane) }
    }
}
