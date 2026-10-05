import Foundation

/// A faithfully serializable immutable document and its exact canonical revision.
public struct DocumentSnapshot: Equatable, Codable, Sendable {
    /// The faithfully serializable document value.
    public let document: Document
    /// Exact canonical content for detecting subsequent edits.
    public let revision: DocumentRevision

    /// Missing identities are allowed, but any supplied identity must be safe and unique.
    public init(_ document: Document, limits: DocumentDecodeLimits = .standard) throws {
        let data = try DocumentStorageCodec.encode(document, limits: limits)
        try DocumentIdentity.validate(document)
        self.document = document
        revision = .init(canonicalContent: String(decoding: data, as: UTF8.self))
    }

    private enum CodingKeys: String, CodingKey { case document, revision }

    /// Decoded snapshots cannot carry a revision that disagrees with their document.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let document = try container.decode(Document.self, forKey: .document)
        let revision = try container.decode(DocumentRevision.self, forKey: .revision)
        try self.init(document)
        guard self.revision == revision else {
            throw DecodingError.dataCorruptedError(
                forKey: .revision,
                in: container,
                debugDescription: "Revision mismatch."
            )
        }
    }
}

/// Applies typed edits to local values only. The original snapshot is never mutated.
public enum DocumentEditor {
    /// Validates the revision before applying operations and validates the complete final document once.
    /// Intermediate duplicate coordinates are allowed so coordinate swaps can be atomic.
    public static func apply(
        _ patch: DocumentPatch,
        to snapshot: DocumentSnapshot,
        limits: DocumentEditLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> DocumentSnapshot {
        try DocumentStorageCancellation.check()
        guard patch.operations.count <= limits.maximumOperations else {
            throw EditingFailure.make(
                .operationLimit,
                "The transaction exceeds its operation limit.",
                path: "operations"
            )
        }
        guard patch.expectedRevision.canonicalContent.utf8.count <= documentLimits.maximumDecodedBytes else {
            throw EditingFailure.make(
                .payloadLimit,
                "The expected revision exceeds the document byte limit.",
                path: "expectedRevision"
            )
        }
        guard patch.expectedRevision == snapshot.revision else {
            throw EditingFailure.make(
                .staleRevision,
                "The document changed after this patch was prepared.",
                path: "expectedRevision"
            )
        }
        _ = try DocumentSnapshot(snapshot.document, limits: documentLimits)
        try payload(patch.operations, limits: limits)
        var header = DocumentHeader(snapshot.document)
        var planes = snapshot.document.planes
        for (index, operation) in patch.operations.enumerated() {
            try DocumentStorageCancellation.check()
            let path = "operations[\(index)]"
            switch operation {
            case .replaceHeader(let replacement): header = replacement
            case .insert(let plane, let position):
                guard (0...planes.count).contains(position) else {
                    throw EditingFailure.make(
                        .invalidIndex,
                        "Insertion index is outside the source-order list.",
                        path: path
                    )
                }
                guard let id = plane.stableID else {
                    throw EditingFailure.make(
                        .missingIdentity,
                        "An inserted plane needs a stable identity.",
                        path: path
                    )
                }
                try targetID(id, path: path)
                guard !planes.contains(where: { $0.stableID == id }) else {
                    throw EditingFailure.make(
                        .duplicateIdentity,
                        "An inserted plane identity is already used.",
                        path: path
                    )
                }
                guard planes.count < documentLimits.maximumPlanes else {
                    throw EditingFailure.make(.payloadLimit, "The transaction exceeds the plane limit.", path: path)
                }
                planes.insert(plane, at: position)
            case .remove(let id): planes.remove(at: try target(id, in: planes, path: path))
            case .replace(let id, let plane):
                let position = try target(id, in: planes, path: path)
                guard plane.stableID == id else {
                    throw EditingFailure.make(
                        .identityChanged,
                        "Replacement must retain the target identity.",
                        path: path
                    )
                }
                planes[position] = plane
            case .move(let id, let destination):
                let position = try target(id, in: planes, path: path)
                guard planes.indices.contains(destination) else {
                    throw EditingFailure.make(
                        .invalidIndex,
                        "Move index is outside the final source-order list.",
                        path: path
                    )
                }
                let plane = planes.remove(at: position)
                planes.insert(plane, at: destination)
            }
        }
        let result = header.document(planes: planes)
        var coordinates: Set<Double> = []
        for (index, plane) in result.planes.enumerated() {
            try DocumentStorageCancellation.check()
            guard coordinates.insert(plane.z).inserted else {
                throw EditingFailure.make(
                    .duplicatePosition,
                    "Final plane positions must be unique.",
                    path: "planes[\(index)].z"
                )
            }
        }
        do { return try DocumentSnapshot(result, limits: documentLimits) } catch let error as DocumentEditError {
            throw error
        } catch {
            try EditingFailure.propagateCancellation(error)
            throw EditingFailure.document(error)
        }
    }

    internal static func targetID(_ id: String, path: String) throws {
        guard DocumentIdentity.isValid(id) else {
            throw EditingFailure.make(.invalidIdentity, "An edit target must be a safe nonempty ASCII ID.", path: path)
        }
    }

    private static func target(_ id: String, in planes: [Plane], path: String) throws -> Int {
        try targetID(id, path: path)
        guard let index = planes.firstIndex(where: { $0.stableID == id }) else {
            throw EditingFailure.make(.missingTarget, "The target plane identity does not exist.", path: path)
        }
        return index
    }

    private static func payload(_ operations: [DocumentEdit], limits: DocumentEditLimits) throws {
        var budget = EditingPayloadBudget(maximumBytes: limits.maximumPayloadBytes)
        for operation in operations {
            try DocumentStorageCancellation.check()
            switch operation {
            case .insert(let plane, _): try budget.plane(plane)
            case .replace(let id, let plane): try budget.charge(id); try budget.plane(plane)
            case .remove(let id), .move(let id, _): try budget.charge(id)
            case .replaceHeader(let header): try budget.header(header)
            }
        }
    }
}
