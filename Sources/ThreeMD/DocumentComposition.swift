import Foundation

/// A reference to a definition supplied in the same library. Attributes are opaque application data.
public struct DocumentReference: Hashable, Sendable {
    /// The case-sensitive ID of a definition in the supplied composition library.
    public let targetID: String
    /// Opaque string attributes interpreted by the application, never resolved as external resources.
    public let attributes: [String: String]

    /// Creates a reference value; the enclosing composition validates its ID and attribute bounds.
    public init(targetID: String, attributes: [String: String] = [:]) {
        self.targetID = targetID
        self.attributes = attributes
    }
}

/// A named, standalone document and its ordered application-defined references.
public struct DocumentEntry: Hashable, Sendable {
    /// The case-sensitive library ID, validated when the enclosing composition is created.
    public let id: String
    /// The standalone definition, retaining its own axis, metadata, preamble and planes.
    public let document: Document
    /// Ordered references whose application-defined attributes are retained without interpretation.
    public let references: [DocumentReference]

    /// Creates an entry value; validation of its document and references belongs to the enclosing composition.
    public init(id: String, document: Document, references: [DocumentReference] = []) {
        self.id = id
        self.document = document
        self.references = references
    }
}

/// A validated reference graph. Definitions keep their own axes and metadata; no flattening is performed.
public struct DocumentComposition: Hashable, Sendable {
    /// The case-sensitive ID of the library's designated root definition.
    public let rootID: String
    /// Definitions are ordered by their ASCII ID. Reference order within each definition is preserved.
    public let entries: [DocumentEntry]
    /// The standalone root definition, without traversing references or merging documents.
    public let rootEntry: DocumentEntry

    /// Validates every definition and reference, including unused entries, against the supplied policies.
    ///
    /// IDs contain 1–64 ASCII letters, digits, underscores or hyphens and start with a letter or digit.
    /// Graph and source limits apply to this construction; codec calls supply their own policies separately.
    /// - Throws: A composition validation error, a child document storage error, or cancellation.
    public init(
        rootID: String,
        entries: [DocumentEntry],
        limits: DocumentCompositionLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws {
        let validated = try DocumentCompositionValidation.validate(
            rootID: rootID,
            entries: entries,
            limits: limits,
            documentLimits: documentLimits
        )
        self.rootID = rootID
        self.entries = entries.sorted { $0.id < $1.id }
        rootEntry = validated.root
    }

    /// Looks up only the supplied library. An ID is never interpreted as a path or URL.
    public func entry(id: String) -> DocumentEntry? { entries.first { $0.id == id } }
}

internal enum DocumentCompositionValidation {
    internal struct Result {
        let root: DocumentEntry
        let sources: [String: Data]
    }

    internal static func validate(
        rootID: String,
        entries: [DocumentEntry],
        limits: DocumentCompositionLimits,
        documentLimits: DocumentDecodeLimits
    ) throws -> Result {
        try DocumentStorageCancellation.check()
        guard validID(rootID) else { throw DocumentCompositionError.invalidID(rootID) }
        guard entries.count <= limits.maximumDefinitions else { throw DocumentCompositionError.tooManyDefinitions }
        var indices: [String: Int] = [:]
        var sources: [String: Data] = [:]
        var referenceCount = 0
        var sourceBytes = 0
        for (index, entry) in entries.enumerated() {
            try DocumentStorageCancellation.check()
            guard validID(entry.id) else { throw DocumentCompositionError.invalidID(entry.id) }
            guard indices.updateValue(index, forKey: entry.id) == nil else {
                throw DocumentCompositionError.duplicateID(entry.id)
            }
            guard entry.references.count <= limits.maximumReferences - referenceCount else {
                throw DocumentCompositionError.tooManyReferences
            }
            referenceCount += entry.references.count
            for reference in entry.references {
                try DocumentStorageCancellation.check()
                guard validID(reference.targetID) else { throw DocumentCompositionError.invalidID(reference.targetID) }
                guard reference.attributes.count <= limits.maximumReferenceAttributes else {
                    throw DocumentCompositionError.referenceAttributesExceeded
                }
                var attributeBytes = 0
                for (key, value) in reference.attributes {
                    for text in [key, value] {
                        guard text.utf8.count <= limits.maximumReferenceAttributeBytes - attributeBytes else {
                            throw DocumentCompositionError.referenceAttributesExceeded
                        }
                        attributeBytes += text.utf8.count
                    }
                }
            }
            // The storage writer validates direct values and preserves arbitrary serializable axes/metadata.
            let remaining = limits.maximumDefinitionBytes - sourceBytes
            guard remaining > 0 else { throw DocumentCompositionError.definitionBytesExceeded }
            let childLimits = try DocumentDecodeLimits(
                maximumEncodedBytes: min(documentLimits.maximumEncodedBytes, remaining),
                maximumDecodedBytes: min(documentLimits.maximumDecodedBytes, remaining),
                maximumLines: documentLimits.maximumLines,
                maximumPlanes: documentLimits.maximumPlanes,
                maximumRecordBytes: min(documentLimits.maximumRecordBytes, remaining)
            )
            let source: Data
            do {
                source = try DocumentStorageCodec.encode(entry.document, format: .text, limits: childLimits)
            } catch let error as DocumentStorageError {
                switch error {
                case .oversizedInput where remaining <= documentLimits.maximumEncodedBytes,
                    .oversizedOutput where remaining <= documentLimits.maximumDecodedBytes,
                    .oversizedRecord where remaining <= documentLimits.maximumRecordBytes:
                    throw DocumentCompositionError.definitionBytesExceeded
                default: throw error
                }
            }
            guard source.count <= limits.maximumDefinitionBytes - sourceBytes else {
                throw DocumentCompositionError.definitionBytesExceeded
            }
            sourceBytes += source.count
            sources[entry.id] = source
        }
        guard let rootIndex = indices[rootID] else { throw DocumentCompositionError.missingRoot(rootID) }
        for entry in entries {
            for reference in entry.references {
                try DocumentStorageCancellation.check()
                guard indices[reference.targetID] != nil else {
                    throw DocumentCompositionError.missingTarget(from: entry.id, target: reference.targetID)
                }
            }
        }
        var graph = Graph(entries: entries, indices: indices, limits: limits)
        // Include unused definitions: hiding a bad graph behind a different root never makes it valid.
        for index in entries.indices { try graph.visit(index, activeDepth: 0) }
        return Result(root: entries[rootIndex], sources: sources)
    }

    internal static func validID(_ id: String) -> Bool {
        let bytes = id.utf8
        guard (1...64).contains(bytes.count), let first = bytes.first, alphanumeric(first) else { return false }
        return bytes.allSatisfy { alphanumeric($0) || $0 == 45 || $0 == 95 }
    }

    private static func alphanumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }

    private struct Graph {
        let entries: [DocumentEntry]
        let indices: [String: Int]
        let limits: DocumentCompositionLimits
        var states: [UInt8]
        var depths: [Int]
        var occurrences: [Int]

        init(entries: [DocumentEntry], indices: [String: Int], limits: DocumentCompositionLimits) {
            self.entries = entries
            self.indices = indices
            self.limits = limits
            states = .init(repeating: 0, count: entries.count)
            depths = .init(repeating: 0, count: entries.count)
            occurrences = .init(repeating: 0, count: entries.count)
        }

        mutating func visit(_ index: Int, activeDepth: Int) throws {
            try DocumentStorageCancellation.check()
            if states[index] == 1 { throw DocumentCompositionError.cycle(entries[index].id) }
            if states[index] == 2 { return }
            guard activeDepth < limits.maximumDepth else { throw DocumentCompositionError.depthExceeded }
            states[index] = 1
            var depth = 1
            var count = 1
            for reference in entries[index].references {
                guard let target = indices[reference.targetID] else {
                    throw DocumentCompositionError.missingTarget(from: entries[index].id, target: reference.targetID)
                }
                try visit(target, activeDepth: activeDepth + 1)
                depth = max(depth, depths[target] + 1)
                guard depth <= limits.maximumDepth else { throw DocumentCompositionError.depthExceeded }
                let (nextCount, overflow) = count.addingReportingOverflow(occurrences[target])
                guard !overflow, nextCount <= limits.maximumTraversalOccurrences else {
                    throw DocumentCompositionError.traversalOccurrencesExceeded
                }
                count = nextCount
            }
            states[index] = 2
            depths[index] = depth
            occurrences[index] = count
        }
    }
}
