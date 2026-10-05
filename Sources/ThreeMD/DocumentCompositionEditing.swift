import Foundation

/// Typed library and instance edits. Reference identities are scoped to the specified owning entry.
public enum CompositionEdit: Equatable, Codable, Sendable {
    case insertEntry(DocumentEntry)
    case removeEntry(id: String)
    case replaceEntry(id: String, entry: DocumentEntry)
    case selectRoot(id: String)
    case insertReference(ownerID: String, reference: DocumentReference, at: Int)
    case removeReference(ownerID: String, id: String)
    case replaceReference(ownerID: String, id: String, reference: DocumentReference)
    case moveReference(ownerID: String, id: String, to: Int)
}

/// An atomic graph transaction against one exact canonical composition profile.
public struct CompositionPatch: Equatable, Codable, Sendable {
    /// Exact canonical profile content that must still match the current snapshot.
    public let expectedRevision: DocumentRevision
    /// Ordered edits to apply before validating the complete graph.
    public let operations: [CompositionEdit]
    /// Creates a graph patch without applying it or resolving external resources.
    public init(expectedRevision: DocumentRevision, operations: [CompositionEdit]) {
        self.expectedRevision = expectedRevision
        self.operations = operations
    }
}

/// Immutable graph state. Revisions cover root selection, definitions and ordered references with attributes.
public struct DocumentCompositionSnapshot: Equatable, Codable, Sendable {
    /// The complete self-contained validated reference graph.
    public let composition: DocumentComposition
    /// Exact canonical profile source covering all definitions and references.
    public let revision: DocumentRevision

    /// Captures a graph within the caller's policies and validates optional identities.
    public init(
        _ composition: DocumentComposition,
        limits: DocumentCompositionLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws {
        let data = try DocumentCompositionCodec.encode(composition, limits: limits, documentLimits: documentLimits)
        try DocumentIdentity.validate(composition)
        self.composition = composition
        revision = .init(canonicalContent: String(decoding: data, as: UTF8.self))
    }

    private enum CodingKeys: String, CodingKey { case composition, revision }

    /// Reconstructs a validated graph and rejects a revision that disagrees with its content.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let composition = try container.decode(DocumentComposition.self, forKey: .composition)
        let revision = try container.decode(DocumentRevision.self, forKey: .revision)
        try self.init(composition)
        guard self.revision == revision else {
            throw DecodingError.dataCorruptedError(
                forKey: .revision,
                in: container,
                debugDescription: "Revision mismatch."
            )
        }
    }
}

/// Pure transactional graph editing, without path resolution or external resource access.
public enum CompositionEditor {
    /// Defers reference existence and cycle checks until the complete final graph is available.
    public static func apply(
        _ patch: CompositionPatch,
        to snapshot: DocumentCompositionSnapshot,
        limits: DocumentEditLimits = .standard,
        compositionLimits: DocumentCompositionLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> DocumentCompositionSnapshot {
        try DocumentStorageCancellation.check()
        guard patch.operations.count <= limits.maximumOperations else {
            throw EditingFailure.make(
                .operationLimit,
                "The graph transaction exceeds its operation limit.",
                path: "operations"
            )
        }
        guard patch.expectedRevision.canonicalContent.utf8.count <= compositionLimits.maximumProfileBytes else {
            throw EditingFailure.make(
                .payloadLimit,
                "The expected graph revision exceeds its profile byte limit.",
                path: "expectedRevision"
            )
        }
        guard patch.expectedRevision == snapshot.revision else {
            throw EditingFailure.make(
                .staleRevision,
                "The composition changed after this patch was prepared.",
                path: "expectedRevision"
            )
        }
        _ = try DocumentCompositionSnapshot(
            snapshot.composition,
            limits: compositionLimits,
            documentLimits: documentLimits
        )
        try payload(patch.operations, limits: limits)
        var rootID = snapshot.composition.rootID
        var entries = snapshot.composition.entries
        for (index, operation) in patch.operations.enumerated() {
            try DocumentStorageCancellation.check()
            let path = "operations[\(index)]"
            switch operation {
            case .selectRoot(let id): try DocumentEditor.targetID(id, path: path); rootID = id
            case .insertEntry(let entry):
                try DocumentEditor.targetID(entry.id, path: path)
                guard !entries.contains(where: { $0.id == entry.id }) else {
                    throw EditingFailure.make(.duplicateIdentity, "The definition ID already exists.", path: path)
                }
                guard entries.count < compositionLimits.maximumDefinitions else {
                    throw EditingFailure.make(
                        .payloadLimit,
                        "The transaction exceeds its definition limit.",
                        path: path
                    )
                }
                entries.append(entry)
            case .removeEntry(let id): entries.remove(at: try owner(id, in: entries, path: path))
            case .replaceEntry(let id, let entry):
                let position = try owner(id, in: entries, path: path)
                guard entry.id == id else {
                    throw EditingFailure.make(
                        .identityChanged,
                        "Replacement must retain its definition ID.",
                        path: path
                    )
                }
                entries[position] = entry
            case .insertReference(let ownerID, let reference, let destination):
                let position = try owner(ownerID, in: entries, path: path)
                var references = entries[position].references
                guard (0...references.count).contains(destination) else {
                    throw EditingFailure.make(
                        .invalidIndex,
                        "Reference insertion index is outside its owner list.",
                        path: path
                    )
                }
                guard let id = reference.stableID else {
                    throw EditingFailure.make(
                        .missingIdentity,
                        "An inserted reference needs a stable identity.",
                        path: path
                    )
                }
                try DocumentEditor.targetID(id, path: path)
                guard !references.contains(where: { $0.stableID == id }) else {
                    throw EditingFailure.make(
                        .duplicateIdentity,
                        "The reference identity already exists in this owner.",
                        path: path
                    )
                }
                guard references.count < compositionLimits.maximumReferences else {
                    throw EditingFailure.make(
                        .payloadLimit,
                        "The owner exceeds the reference-record limit.",
                        path: path
                    )
                }
                references.insert(reference, at: destination)
                entries[position] = replacingReferences(references, in: entries[position])
            case .removeReference(let ownerID, let id):
                let position = try owner(ownerID, in: entries, path: path)
                var references = entries[position].references
                references.remove(at: try target(id, in: references, path: path))
                entries[position] = replacingReferences(references, in: entries[position])
            case .replaceReference(let ownerID, let id, let reference):
                let position = try owner(ownerID, in: entries, path: path)
                var references = entries[position].references
                let referenceIndex = try target(id, in: references, path: path)
                guard reference.stableID == id else {
                    throw EditingFailure.make(
                        .identityChanged,
                        "Replacement must retain its reference identity.",
                        path: path
                    )
                }
                references[referenceIndex] = reference
                entries[position] = replacingReferences(references, in: entries[position])
            case .moveReference(let ownerID, let id, let destination):
                let position = try owner(ownerID, in: entries, path: path)
                var references = entries[position].references
                let referenceIndex = try target(id, in: references, path: path)
                guard references.indices.contains(destination) else {
                    throw EditingFailure.make(
                        .invalidIndex,
                        "Reference move index is outside its final owner list.",
                        path: path
                    )
                }
                let reference = references.remove(at: referenceIndex)
                references.insert(reference, at: destination)
                entries[position] = replacingReferences(references, in: entries[position])
            }
        }
        do {
            let composition = try DocumentComposition(
                rootID: rootID,
                entries: entries,
                limits: compositionLimits,
                documentLimits: documentLimits
            )
            return try DocumentCompositionSnapshot(
                composition,
                limits: compositionLimits,
                documentLimits: documentLimits
            )
        } catch let error as DocumentEditError {
            throw error
        } catch let error as DocumentCompositionError {
            throw DocumentDiagnostics.compositionError(error, entries: entries)
        } catch {
            try EditingFailure.propagateCancellation(error)
            throw EditingFailure.document(error, path: "entries")
        }
    }

    private static func owner(_ id: String, in entries: [DocumentEntry], path: String) throws -> Int {
        try DocumentEditor.targetID(id, path: path)
        guard let position = entries.firstIndex(where: { $0.id == id }) else {
            throw EditingFailure.make(.missingTarget, "The owning definition does not exist.", path: path)
        }
        return position
    }

    private static func target(_ id: String, in references: [DocumentReference], path: String) throws -> Int {
        try DocumentEditor.targetID(id, path: path)
        guard let position = references.firstIndex(where: { $0.stableID == id }) else {
            throw EditingFailure.make(
                .missingTarget,
                "The reference identity does not exist in this owner.",
                path: path
            )
        }
        return position
    }

    private static func replacingReferences(_ references: [DocumentReference], in entry: DocumentEntry) -> DocumentEntry
    {
        .init(id: entry.id, document: entry.document, references: references)
    }

    private static func payload(_ operations: [CompositionEdit], limits: DocumentEditLimits) throws {
        var budget = EditingPayloadBudget(maximumBytes: limits.maximumPayloadBytes)
        func chargeEntry(_ entry: DocumentEntry, budget: inout EditingPayloadBudget) throws {
            try budget.charge(entry.id); try budget.document(entry.document)
            guard entry.references.count <= budget.maximumBytes - budget.used else {
                throw EditingFailure.make(.payloadLimit, "Reference payload exceeds the edit byte budget.")
            }
            for reference in entry.references {
                try budget.charge(reference.targetID); try budget.attributes(reference.attributes)
            }
        }
        for operation in operations {
            try DocumentStorageCancellation.check()
            switch operation {
            case .insertEntry(let entry): try chargeEntry(entry, budget: &budget)
            case .replaceEntry(let id, let entry): try budget.charge(id); try chargeEntry(entry, budget: &budget)
            case .removeEntry(let id), .selectRoot(let id): try budget.charge(id)
            case .insertReference(let ownerID, let reference, _):
                try budget.charge(ownerID); try budget.charge(reference.targetID);
                try budget.attributes(reference.attributes)
            case .replaceReference(let ownerID, let id, let reference):
                try budget.charge(ownerID); try budget.charge(id)
                try budget.charge(reference.targetID); try budget.attributes(reference.attributes)
            case .removeReference(let ownerID, let id), .moveReference(let ownerID, let id, _):
                try budget.charge(ownerID); try budget.charge(id)
            }
        }
    }
}
