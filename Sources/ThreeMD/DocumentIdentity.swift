/// Optional identity semantics above the frozen parser. Ordinary `id` attributes remain opaque.
public enum DocumentIdentity {
    /// Preserved optional identity metadata, independent of any application-defined `id` field.
    public static let attributeKey = "3md-id"

    /// Uses the same portable 1...64 byte ASCII grammar as composition definition IDs.
    public static func isValid(_ id: String) -> Bool { DocumentCompositionValidation.validID(id) }

    /// Assigns deterministic missing plane IDs, preserving every valid existing ID and unrelated field.
    /// Invalid or duplicate existing IDs fail; this operation does not silently repair identities.
    public static func adopt(
        _ document: Document,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> Document {
        try DocumentStorageCodec.validate(document, limits: documentLimits)
        try validate(document)
        var ids = Set(document.planes.compactMap(\.stableID))
        var next = 1
        var planes: [Plane] = []
        planes.reserveCapacity(document.planes.count)
        for plane in document.planes {
            try DocumentStorageCancellation.check()
            guard plane.stableID == nil else { planes.append(plane); continue }
            let id = nextID(prefix: "plane", ids: &ids, next: &next)
            planes.append(plane.withIdentity(id))
        }
        let result = DocumentHeader(document).document(planes: planes)
        try DocumentStorageCodec.validate(result, limits: documentLimits)
        return result
    }

    /// Adopts plane IDs independently in each definition and reference IDs independently in each owner.
    public static func adopt(
        _ composition: DocumentComposition,
        limits: DocumentCompositionLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> DocumentComposition {
        try validate(composition)
        var entries: [DocumentEntry] = []
        for entry in composition.entries {
            try DocumentStorageCancellation.check()
            let document = try adopt(entry.document, documentLimits: documentLimits)
            var ids = Set(entry.references.compactMap(\.stableID))
            var next = 1
            var references: [DocumentReference] = []
            for reference in entry.references {
                try DocumentStorageCancellation.check()
                if reference.stableID != nil {
                    references.append(reference)
                } else {
                    var attributes = reference.attributes
                    attributes[attributeKey] = nextID(prefix: "reference", ids: &ids, next: &next)
                    references.append(.init(targetID: reference.targetID, attributes: attributes))
                }
            }
            entries.append(.init(id: entry.id, document: document, references: references))
        }
        return try DocumentComposition(
            rootID: composition.rootID,
            entries: entries,
            limits: limits,
            documentLimits: documentLimits
        )
    }

    internal static func validate(_ document: Document, prefix: String = "") throws {
        var ids: Set<String> = []
        for (index, plane) in document.planes.enumerated() {
            try DocumentStorageCancellation.check()
            guard let id = plane.stableID else { continue }
            let path = "\(prefix)planes[\(index)].attributes[3md-id]"
            guard isValid(id) else {
                throw EditingFailure.make(
                    .invalidIdentity,
                    "Plane identity must be a safe nonempty ASCII ID.",
                    path: path
                )
            }
            guard ids.insert(id).inserted else {
                throw EditingFailure.make(
                    .duplicateIdentity,
                    "Plane identity is already used in this document.",
                    path: path
                )
            }
        }
    }

    internal static func validate(_ composition: DocumentComposition) throws {
        for (index, entry) in composition.entries.enumerated() {
            try validate(entry.document, prefix: "entries[\(index)].document.")
            try validateReferences(entry.references, prefix: "entries[\(index)].")
        }
    }

    internal static func validateReferences(_ references: [DocumentReference], prefix: String) throws {
        var ids: Set<String> = []
        for (index, reference) in references.enumerated() {
            try DocumentStorageCancellation.check()
            guard let id = reference.stableID else { continue }
            let path = "\(prefix)references[\(index)].attributes[3md-id]"
            guard isValid(id) else {
                throw EditingFailure.make(
                    .invalidIdentity,
                    "Reference identity must be a safe nonempty ASCII ID.",
                    path: path
                )
            }
            guard ids.insert(id).inserted else {
                throw EditingFailure.make(
                    .duplicateIdentity,
                    "Reference identity is already used by this owner.",
                    path: path
                )
            }
        }
    }

    private static func nextID(prefix: String, ids: inout Set<String>, next: inout Int) -> String {
        var candidate = "\(prefix)-\(next)"
        while ids.contains(candidate) { next += 1; candidate = "\(prefix)-\(next)" }
        ids.insert(candidate)
        next += 1
        return candidate
    }
}

extension Plane {
    /// Optional stable editing identity. HTML anchors and z links remain coordinate-based.
    public var stableID: String? { attributes[DocumentIdentity.attributeKey] }

    internal func withIdentity(_ id: String) -> Plane {
        var attributes = attributes
        attributes[DocumentIdentity.attributeKey] = id
        return Plane(z: z, label: label, x: x, y: y, attributes: attributes, body: body)
    }
}

extension DocumentReference {
    /// Optional instance identity scoped to one owning entry, independent of its reusable target ID.
    public var stableID: String? { attributes[DocumentIdentity.attributeKey] }
}
