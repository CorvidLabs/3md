import Foundation
import ThreeMD

/// Bridges public native APIs into the development-only, exact-byte interchange protocol.
internal func swiftInterchange(_ request: InterchangeRequest) throws -> InterchangeResponse {
    do {
        let data = try Data(hex: request.bytesHex)
        switch request.kind {
        case "document": return try documentInterchange(data)
        case "composition": return try compositionInterchange(data)
        case "files": return try filesInterchange(data)
        default: return InterchangeResponse(ok: false, error: "adapterFailure")
        }
    } catch {
        return InterchangeResponse(ok: false, error: interchangeErrorCode(error))
    }
}

private func documentInterchange(_ data: Data) throws -> InterchangeResponse {
    let document = try DocumentStorageCodec.decode(data)
    let canonical = try DocumentStorageCodec.encode(document)
    let binary = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
    let rawCanonical: Data?
    if DocumentStorageCodec.isBinary(data) {
        rawCanonical = nil
    } else {
        guard let source = String(data: data, encoding: .utf8) else {
            throw DocumentStorageError.invalidUTF8
        }
        rawCanonical = try DocumentStorageCodec.encode(Parser().parse(source))
    }
    let adopted = try DocumentIdentity.adopt(document)
    let snapshot = try DocumentSnapshot(adopted)
    let edited: DocumentSnapshot
    let staleRejected: Bool
    if let plane = adopted.planes.first {
        guard let id = plane.stableID else { throw InterchangeAdapterError.missingAdoptedIdentity }
        let patch = DocumentPatch(
            expectedRevision: snapshot.revision,
            operations: [.replace(id: id, plane: editedPlane(plane))]
        )
        edited = try DocumentEditor.apply(patch, to: snapshot)
        do {
            _ = try DocumentEditor.apply(patch, to: edited)
            staleRejected = false
        } catch let error as DocumentEditError where error.diagnostic.code == .staleRevision {
            staleRejected = true
        }
    } else {
        edited = snapshot
        staleRejected = true
    }
    return InterchangeResponse(
        ok: true,
        canonicalHex: canonical.hex,
        binaryHex: binary.hex,
        legacyHex: Data(Serializer().render(document).utf8).hex,
        rawCanonicalHex: rawCanonical?.hex,
        revisionHex: Data(snapshot.revision.canonicalContent.utf8).hex,
        adoptedHex: try DocumentStorageCodec.encode(adopted).hex,
        editedHex: try DocumentStorageCodec.encode(edited.document).hex,
        staleRejected: staleRejected,
        semantic: documentSemantic(document)
    )
}

private func compositionInterchange(_ data: Data) throws -> InterchangeResponse {
    let composition = try DocumentCompositionCodec.decode(data)
    return try compositionResponse(composition)
}

private func filesInterchange(_ data: Data) throws -> InterchangeResponse {
    try validateInterchangeJSON(data)
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    guard case .object(let manifest) = value,
        Set(manifest.keys) == ["rootPath", "files"],
        let rootValue = manifest["rootPath"], case .string(let rootPath) = rootValue,
        let filesValue = manifest["files"], case .array(let files) = filesValue
    else { throw InterchangeAdapterError.invalidFilesRequest }
    guard files.count <= DocumentCompositionLimits.standard.maximumDefinitions else {
        throw DocumentFileCompositionError.inputLimit
    }
    let sources = try files.map { value -> DocumentFileSource in
        guard case .object(let file) = value,
            Set(file.keys) == ["path", "bytesHex"],
            let pathValue = file["path"], case .string(let path) = pathValue,
            let bytesValue = file["bytesHex"], case .string(let bytesHex) = bytesValue
        else { throw InterchangeAdapterError.invalidFilesRequest }
        return DocumentFileSource(path: path, data: try Data(hex: bytesHex))
    }
    let result = try DocumentFileComposition.resolve(rootPath: rootPath, sources: sources)
    return try compositionResponse(result.composition)
}

private func compositionResponse(_ composition: DocumentComposition) throws -> InterchangeResponse {
    let canonical = try DocumentCompositionCodec.encode(composition)
    let binary = try DocumentStorageCodec.encode(
        DocumentCompositionCodec.document(for: composition),
        format: .binary(compression: .none),
        limits: DocumentDecodeLimits(
            maximumEncodedBytes: DocumentCompositionLimits.standard.maximumProfileBytes,
            maximumDecodedBytes: DocumentCompositionLimits.standard.maximumProfileBytes,
            maximumPlanes: 1,
            maximumRecordBytes: DocumentCompositionLimits.standard.maximumProfileBytes
        )
    )
    let adopted = try DocumentIdentity.adopt(composition)
    let snapshot = try DocumentCompositionSnapshot(adopted)
    let root = adopted.rootEntry
    let edited: DocumentCompositionSnapshot
    let staleRejected: Bool
    if let plane = root.document.planes.first {
        let planes = [editedPlane(plane)] + root.document.planes.dropFirst()
        let document = Document(
            version: root.document.version,
            axis: root.document.axis,
            title: root.document.title,
            metadata: root.document.metadata,
            preamble: root.document.preamble,
            planes: planes
        )
        let patch = CompositionPatch(
            expectedRevision: snapshot.revision,
            operations: [
                .replaceEntry(
                    id: root.id,
                    entry: DocumentEntry(id: root.id, document: document, references: root.references)
                )
            ]
        )
        edited = try CompositionEditor.apply(patch, to: snapshot)
        do {
            _ = try CompositionEditor.apply(patch, to: edited)
            staleRejected = false
        } catch let error as DocumentEditError where error.diagnostic.code == .staleRevision {
            staleRejected = true
        }
    } else {
        edited = snapshot
        staleRejected = true
    }
    return InterchangeResponse(
        ok: true,
        canonicalHex: canonical.hex,
        binaryHex: binary.hex,
        revisionHex: Data(snapshot.revision.canonicalContent.utf8).hex,
        adoptedHex: try DocumentCompositionCodec.encode(adopted).hex,
        editedHex: try DocumentCompositionCodec.encode(edited.composition).hex,
        staleRejected: staleRejected,
        semantic: compositionSemantic(composition)
    )
}

private func editedPlane(_ plane: Plane) -> Plane {
    Plane(
        z: plane.z,
        label: plane.label,
        x: plane.x,
        y: plane.y,
        attributes: plane.attributes,
        body: plane.body.isEmpty ? "interchange edited" : plane.body + "\ninterchange edited"
    )
}

private func documentSemantic(_ document: Document) -> JSONValue {
    .object([
        "version": .string(document.version),
        "axis": .string(document.axis.rawValue),
        "title": optionalString(document.title),
        "metadata": stringObject(document.metadata),
        "preamble": optionalString(document.preamble),
        "planes": .array(
            document.planes.map { plane in
                .object([
                    "zBits": .string(coordinateBits(plane.z)),
                    "xBits": plane.x.map { .string(coordinateBits($0)) } ?? .null,
                    "yBits": plane.y.map { .string(coordinateBits($0)) } ?? .null,
                    "label": optionalString(plane.label),
                    "attributes": stringObject(plane.attributes),
                    "body": .string(plane.body),
                ])
            }
        ),
    ])
}

private func compositionSemantic(_ composition: DocumentComposition) -> JSONValue {
    .object([
        "rootID": .string(composition.rootID),
        "entries": .array(
            composition.entries.sorted { $0.id < $1.id }.map { entry in
                .object([
                    "id": .string(entry.id),
                    "document": documentSemantic(entry.document),
                    "references": .array(
                        entry.references.map { reference in
                            .object([
                                "targetID": .string(reference.targetID),
                                "attributes": stringObject(reference.attributes),
                            ])
                        }
                    ),
                ])
            }
        ),
    ])
}

private func optionalString(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }

private func stringObject(_ values: [String: String]) -> JSONValue { .object(values.mapValues(JSONValue.string)) }

private func coordinateBits(_ value: Double) -> String {
    let bits = value == 0 ? UInt64(0) : value.bitPattern
    let digits = String(bits, radix: 16)
    return String(repeating: "0", count: 16 - digits.count) + digits
}

private enum InterchangeAdapterError: Error { case missingAdoptedIdentity, invalidFilesRequest }

private func interchangeErrorCode(_ error: any Error) -> String {
    if let error = error as? DocumentEditError { return error.diagnostic.code.rawValue }
    if let error = error as? ParseError { return error.code }
    if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *), error is CancellationError { return "cancelled" }
    if let error = error as? DocumentFileCompositionError {
        switch error {
        case .invalidPath, .duplicatePath: return "filePath"
        case .invalidLedger, .invalidGlyph: return "fileLedger"
        case .missingFile: return "missingFile"
        case .inputLimit: return "fileLimit"
        }
    }
    if let error = error as? DocumentStorageError {
        switch error {
        case .invalidLimits: return "invalidLimits"
        case .oversizedInput: return "oversizedInput"
        case .oversizedOutput: return "oversizedOutput"
        case .tooManyLines: return "tooManyLines"
        case .tooManyPlanes: return "tooManyPlanes"
        case .oversizedRecord: return "oversizedRecord"
        case .invalidUTF8: return "invalidUTF8"
        case .invalidText: return "invalidText"
        case .invalidDocument: return "invalidDocument"
        case .invalidContainer: return "invalidContainer"
        case .unsupportedVersion: return "unsupportedVersion"
        case .unsupportedPayloadKind: return "unsupportedPayloadKind"
        case .unsupportedCompression: return "unsupportedCompression"
        case .unsupportedFlags: return "unsupportedFlags"
        case .nonzeroReserved: return "nonzeroReserved"
        case .lengthMismatch: return "lengthMismatch"
        case .checksumMismatch: return "checksumMismatch"
        case .compressionUnavailable: return "compressionUnavailable"
        case .compressionFailed: return "compressionFailed"
        }
    }
    if let error = error as? DocumentCompositionError {
        switch error {
        case .invalidLimits: return "invalidLimits"
        case .invalidID: return "invalidID"
        case .duplicateID: return "duplicateID"
        case .missingRoot: return "missingRoot"
        case .missingTarget: return "missingTarget"
        case .cycle: return "cycle"
        case .tooManyDefinitions: return "tooManyDefinitions"
        case .tooManyReferences: return "tooManyReferences"
        case .depthExceeded: return "depthExceeded"
        case .definitionBytesExceeded: return "definitionBytesExceeded"
        case .traversalOccurrencesExceeded: return "traversalOccurrencesExceeded"
        case .referenceAttributesExceeded: return "referenceAttributesExceeded"
        case .profileBytesExceeded: return "profileBytesExceeded"
        case .invalidProfile: return "invalidProfile"
        case .unsupportedProfile: return "unsupportedProfile"
        }
    }
    return "adapterFailure"
}
