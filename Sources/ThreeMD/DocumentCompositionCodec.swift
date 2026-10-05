import Foundation

/// A versioned text profile using an ordinary Document envelope. It resolves no external resources.
public enum DocumentCompositionCodec {
    /// Converts a composition to a document that can also be passed to `DocumentStorageCodec` for binary storage.
    public static func document(
        for composition: DocumentComposition,
        limits: DocumentCompositionLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> Document {
        try profile(for: composition, limits: limits, documentLimits: documentLimits).document
    }

    private static func profile(
        for composition: DocumentComposition,
        limits: DocumentCompositionLimits,
        documentLimits: DocumentDecodeLimits
    ) throws -> (document: Document, data: Data) {
        let validated = try DocumentCompositionValidation.validate(
            rootID: composition.rootID,
            entries: composition.entries,
            limits: limits,
            documentLimits: documentLimits
        )
        let json = try DocumentCompositionJSON.encode(
            rootID: composition.rootID,
            entries: composition.entries,
            sources: validated.sources,
            maximumBytes: limits.maximumProfileBytes
        )
        guard let manifest = String(data: json, encoding: .utf8) else {
            throw DocumentCompositionError.invalidProfile("manifest is not UTF-8")
        }
        let document = Document(
            version: "0.1",
            axis: .layer,
            metadata: ["profile": "3md-composition-1"],
            planes: [Plane(z: 0, label: "Composition", body: "```json\n\(manifest)\n```")]
        )
        let data = try boundedProfile {
            try DocumentStorageCodec.encode(document, format: .text, limits: profileLimits(limits))
        }
        try DocumentStorageCancellation.check()
        return (document, data)
    }

    /// Encodes canonical readable 3md with each definition stored exactly once.
    public static func encode(
        _ composition: DocumentComposition,
        limits: DocumentCompositionLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> Data {
        try profile(for: composition, limits: limits, documentLimits: documentLimits).data
    }

    /// Reads either bounded text or a generic Document storage envelope containing this profile.
    public static func decode(
        _ data: Data,
        limits: DocumentCompositionLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> DocumentComposition {
        try DocumentStorageCancellation.check()
        guard data.count <= limits.maximumProfileBytes else { throw DocumentCompositionError.profileBytesExceeded }
        let document = try boundedProfile { try DocumentStorageCodec.decode(data, limits: profileLimits(limits)) }
        return try decode(document, limits: limits, documentLimits: documentLimits)
    }

    /// Decodes an already supplied profile document. Every definition, including unused ones, is validated.
    public static func decode(
        _ document: Document,
        limits: DocumentCompositionLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> DocumentComposition {
        try DocumentStorageCancellation.check()
        try boundedProfile { try DocumentStorageCodec.validate(document, limits: profileLimits(limits)) }
        guard document.metadata["profile"] == "3md-composition-1" else {
            throw DocumentCompositionError.unsupportedProfile(document.metadata["profile"] ?? "missing")
        }
        guard document.version == "0.1", document.axis == .layer, document.title == nil, document.preamble == nil,
            document.metadata.count == 1, document.planes.count == 1, let plane = document.planes.first,
            plane.z == 0, plane.label == "Composition", plane.x == nil, plane.y == nil, plane.attributes.isEmpty,
            plane.body.hasPrefix("```json\n"), plane.body.hasSuffix("\n```")
        else { throw DocumentCompositionError.invalidProfile("unexpected composition envelope") }
        let json = Data(plane.body.dropFirst(8).dropLast(4).utf8)
        let manifest = try DocumentCompositionJSON.decode(json, limits: limits)
        guard manifest.schema == "3md-composition-1" else {
            throw DocumentCompositionError.unsupportedProfile(manifest.schema)
        }
        guard manifest.entries.count <= limits.maximumDefinitions else {
            throw DocumentCompositionError.tooManyDefinitions
        }
        var totalBytes = 0
        var entries: [DocumentEntry] = []
        entries.reserveCapacity(manifest.entries.count)
        for entry in manifest.entries {
            try DocumentStorageCancellation.check()
            guard entry.source.utf8.count <= limits.maximumDefinitionBytes - totalBytes else {
                throw DocumentCompositionError.definitionBytesExceeded
            }
            totalBytes += entry.source.utf8.count
            // A source is text, not another storage container and never a path or URL.
            let data = Data(entry.source.utf8)
            guard !DocumentStorageCodec.isBinary(data) else {
                throw DocumentCompositionError.invalidProfile("embedded definitions must be text 3md")
            }
            let definition = try DocumentStorageCodec.decode(data, limits: documentLimits)
            entries.append(
                DocumentEntry(
                    id: entry.id,
                    document: definition,
                    references: entry.references.map {
                        DocumentReference(targetID: $0.targetID, attributes: $0.attributes)
                    }
                )
            )
        }
        return try DocumentComposition(
            rootID: manifest.rootID,
            entries: entries,
            limits: limits,
            documentLimits: documentLimits
        )
    }

    /// Header recognition only; this does not validate the graph or accept a malformed payload.
    public static func isComposition(_ document: Document) -> Bool {
        document.metadata["profile"] == "3md-composition-1"
    }

    private static func boundedProfile<Value>(_ operation: () throws -> Value) throws -> Value {
        do { return try operation() } catch let error as DocumentStorageError {
            switch error {
            case .oversizedInput, .oversizedOutput, .oversizedRecord:
                throw DocumentCompositionError.profileBytesExceeded
            default: throw error
            }
        }
    }

    private static func profileLimits(_ limits: DocumentCompositionLimits) throws -> DocumentDecodeLimits {
        try DocumentDecodeLimits(
            maximumEncodedBytes: limits.maximumProfileBytes,
            maximumDecodedBytes: limits.maximumProfileBytes,
            maximumPlanes: 1,
            maximumRecordBytes: limits.maximumProfileBytes
        )
    }
}
