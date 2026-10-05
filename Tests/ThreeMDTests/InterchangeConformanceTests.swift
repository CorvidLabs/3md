import Foundation
import ThreeMD
import XCTest

/// Native readers exercise every mandatory source and exact byte anchor used by the three-language driver.
final class InterchangeConformanceTests: XCTestCase {
    func testCatalogRequiresEveryLegacySourceAndHasUniqueCompleteCases() throws {
        let catalog = try manifest()
        XCTAssertEqual(catalog.schema, "3md-interchange-catalog-1")
        XCTAssertEqual(catalog.numericVectors, "conformance/extensions/numeric-vectors.json")
        XCTAssertEqual(catalog.cases.count, 79)
        XCTAssertEqual(Set(catalog.cases.map(\.id)).count, catalog.cases.count)
        let legacyFiles = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("conformance"),
            includingPropertiesForKeys: nil
        ).filter {
            $0.pathExtension == "json"
                && ($0.lastPathComponent.hasPrefix("valid-") || $0.lastPathComponent.hasPrefix("invalid-"))
        }
        XCTAssertEqual(legacyFiles.count, 37)
        for file in legacyFiles {
            let fixture = try JSONDecoder().decode(LegacyFixture.self, from: Data(contentsOf: file))
            let record = try XCTUnwrap(
                catalog.cases.first { $0.id == "legacy-" + file.deletingPathExtension().lastPathComponent }
            )
            XCTAssertEqual(try data(record.sourceFile), Data(fixture.source.utf8), record.id)
            XCTAssertEqual(record.expectedError, fixture.error == nil ? nil : "invalidText", record.id)
        }
        for record in catalog.cases {
            XCTAssertTrue(["document", "composition"].contains(record.kind), record.id)
            XCTAssertFalse(try data(record.sourceFile).isEmpty, record.id)
            if record.expectedError != nil {
                XCTAssertTrue(record.formats.isEmpty, record.id)
                XCTAssertNil(record.canonicalFile, record.id)
                XCTAssertNil(record.binaryFile, record.id)
            } else {
                XCTAssertEqual(
                    record.formats,
                    record.kind == "document" ? ["canonical", "binary", "legacy"] : ["canonical", "binary"],
                    record.id
                )
            }
        }
    }

    func testEveryValidCatalogSourceAndLegacyOutputPreserveExactCanonicalBytes() throws {
        let records = try manifest().cases.filter { $0.expectedError == nil }
        XCTAssertEqual(records.count, 46)
        for record in records {
            let source = try data(record.sourceFile)
            let decoded = try DocumentStorageCodec.decode(source)
            let canonical: Data
            let binary: Data
            if record.kind == "document" {
                canonical = try DocumentStorageCodec.encode(decoded)
                binary = try DocumentStorageCodec.encode(decoded, format: .binary(compression: .none))
                let legacy = Data(Serializer().render(decoded).utf8)
                XCTAssertEqual(
                    try DocumentStorageCodec.encode(DocumentStorageCodec.decode(legacy)),
                    canonical,
                    record.id
                )
                let raw = try Parser().parse(String(decoding: source, as: UTF8.self))
                XCTAssertEqual(try DocumentStorageCodec.encode(raw), canonical, record.id)
            } else {
                let graph = try DocumentCompositionCodec.decode(decoded)
                canonical = try DocumentCompositionCodec.encode(graph)
                binary = try DocumentStorageCodec.encode(
                    DocumentCompositionCodec.document(for: graph),
                    format: .binary(compression: .none)
                )
                XCTAssertEqual(
                    try DocumentCompositionCodec.encode(DocumentCompositionCodec.decode(binary)),
                    canonical,
                    record.id
                )
            }
            if let path = record.canonicalFile { XCTAssertEqual(canonical, try data(path), record.id) }
            if let path = record.binaryFile { XCTAssertEqual(binary, try data(path), record.id) }
            XCTAssertEqual(binary.count, canonical.count + DocumentStorageCodec.headerByteCount, record.id)
            XCTAssertEqual(Data(binary.dropFirst(DocumentStorageCodec.headerByteCount)), canonical, record.id)
            XCTAssertEqual(
                try DocumentStorageCodec.encode(DocumentStorageCodec.decode(binary)),
                try DocumentStorageCodec.encode(DocumentStorageCodec.decode(canonical)),
                record.id
            )
        }
    }

    func testCatalogIncludesEveryDeclaredExtensionSourceAndBinaryGolden() throws {
        let catalog = try manifest()
        let declared = try JSONSerialization.jsonObject(with: data("conformance/extensions/manifest.json"))
        var files: Set<String> = []
        func collect(_ value: Any) {
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    if key.hasSuffix("File"), let path = child as? String,
                        ["3md", "3mdb"].contains(URL(fileURLWithPath: path).pathExtension)
                    {
                        files.insert("conformance/extensions/" + path)
                    } else {
                        collect(child)
                    }
                }
            } else if let array = value as? [Any] {
                array.forEach(collect)
            }
        }
        collect(declared)
        XCTAssertEqual(files.count, 8)
        let catalogFiles = Set(
            catalog.cases.flatMap { record in
                [record.sourceFile] + [record.canonicalFile, record.binaryFile].compactMap { $0 }
            }
        )
        XCTAssertTrue(
            files.isSubset(of: catalogFiles),
            "Unexecuted extension files: \(files.subtracting(catalogFiles))"
        )
    }

    func testEveryInvalidCatalogSourceReportsItsRequiredTypedError() throws {
        let records = try manifest().cases.filter { $0.expectedError != nil }
        XCTAssertEqual(records.count, 33)
        for record in records {
            XCTAssertThrowsError(
                try {
                    let decoded = try DocumentStorageCodec.decode(data(record.sourceFile))
                    if record.kind == "composition" {
                        _ = try DocumentIdentity.adopt(DocumentCompositionCodec.decode(decoded))
                    } else {
                        _ = try DocumentIdentity.adopt(decoded)
                    }
                }(),
                record.id
            ) { error in
                XCTAssertEqual(self.errorCode(error), record.expectedError, record.id)
            }
        }
    }

    func testLegacySerializerPreservesRepresentableScalarQuotesAndFoundationEdgeWhitespace() throws {
        let values = [
            "'quoted'", "'", "''", "\u{00a0}leading", "trailing\u{2003}",
            "\u{2009}both\u{00a0}", "quote\"inside", "slash\\inside", "", "plain",
        ]
        for value in values {
            let document = Document(
                version: value.isEmpty ? "0.1" : value,
                axis: Axis(rawValue: value),
                title: value,
                metadata: ["literal": value],
                planes: [Plane(z: 0, label: value, attributes: ["literal": value], body: "Text")]
            )
            let canonical = try DocumentStorageCodec.encode(document)
            let legacy = Serializer().render(document)
            let restored = try Parser().parse(legacy)
            XCTAssertEqual(try DocumentStorageCodec.encode(restored), canonical, value)
            XCTAssertEqual(Array(restored.version.utf8), Array(document.version.utf8), value)
            XCTAssertEqual(Array(restored.axis.rawValue.utf8), Array(document.axis.rawValue.utf8), value)
            XCTAssertEqual(Array(try XCTUnwrap(restored.title).utf8), Array(value.utf8), value)
        }
        XCTAssertTrue(
            Serializer().render(Document(version: "0.1", axis: .layer, planes: [])).hasPrefix(
                "---\n3md: 0.1\naxis: layer\n---\n"
            )
        )
    }

    func testAdoptionAndDeterministicDocumentEditsHaveExactRevisionAndRejectReuse() throws {
        let records = try manifest().cases.filter { $0.expectedError == nil && $0.kind == "document" }
        for record in records {
            let document = try DocumentStorageCodec.decode(data(record.sourceFile))
            let original = try DocumentStorageCodec.encode(document)
            let adopted = try DocumentIdentity.adopt(document)
            let snapshot = try DocumentSnapshot(adopted)
            XCTAssertEqual(Data(snapshot.revision.canonicalContent.utf8), try DocumentStorageCodec.encode(adopted))
            if let plane = adopted.planes.first {
                let replacement = appendedPlane(plane)
                let patch = DocumentPatch(
                    expectedRevision: snapshot.revision,
                    operations: [.replace(id: try XCTUnwrap(plane.stableID), plane: replacement)]
                )
                let edited = try DocumentEditor.apply(patch, to: snapshot)
                XCTAssertEqual(edited.document.planes.first?.body, replacement.body, record.id)
                XCTAssertNotEqual(edited.revision, snapshot.revision, record.id)
                XCTAssertThrowsError(try DocumentEditor.apply(patch, to: edited), record.id) { error in
                    XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .staleRevision, record.id)
                }
            } else {
                XCTAssertEqual(snapshot.document, adopted, record.id)
            }
            XCTAssertEqual(try DocumentStorageCodec.encode(document), original, record.id)
        }
    }

    func testSharedDAGAndUnusedDefinitionsSurviveAdoptionAndRootReplacement() throws {
        let source = try data("conformance/interchange/composition-shared-dag-unused.3md")
        let original = try DocumentCompositionCodec.decode(source)
        XCTAssertEqual(original.entries.map(\.id), ["branch", "leaf", "root", "unused"])
        XCTAssertEqual(original.rootEntry.references.map(\.targetID), ["branch", "leaf", "leaf"])
        let graph = try DocumentIdentity.adopt(original)
        let root = graph.rootEntry
        XCTAssertEqual(root.references.map(\.stableID), ["reference-1", "reference-2", "again"])
        XCTAssertEqual(root.references.last?.attributes["id"], "opaque")
        XCTAssertEqual(graph.entry(id: "unused")?.references.first?.stableID, "reference-1")
        let snapshot = try DocumentCompositionSnapshot(graph)
        let plane = try XCTUnwrap(root.document.planes.first)
        let replacement = DocumentEntry(
            id: root.id,
            document: Document(
                version: root.document.version,
                axis: root.document.axis,
                title: root.document.title,
                metadata: root.document.metadata,
                preamble: root.document.preamble,
                planes: [appendedPlane(plane)] + root.document.planes.dropFirst()
            ),
            references: root.references
        )
        let patch = CompositionPatch(
            expectedRevision: snapshot.revision,
            operations: [.replaceEntry(id: root.id, entry: replacement)]
        )
        let edited = try CompositionEditor.apply(patch, to: snapshot)
        XCTAssertEqual(edited.composition.entry(id: "unused"), graph.entry(id: "unused"))
        XCTAssertEqual(edited.composition.entry(id: "leaf"), graph.entry(id: "leaf"))
        XCTAssertEqual(edited.composition.rootEntry.references, root.references)
        XCTAssertThrowsError(try CompositionEditor.apply(patch, to: edited)) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .staleRevision)
        }
        XCTAssertEqual(try DocumentCompositionCodec.encode(original), source)
    }

    private func appendedPlane(_ plane: Plane) -> Plane {
        Plane(
            z: plane.z,
            label: plane.label,
            x: plane.x,
            y: plane.y,
            attributes: plane.attributes,
            body: plane.body.isEmpty ? "interchange edited" : plane.body + "\ninterchange edited"
        )
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func data(_ path: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(path)) }

    private func manifest() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: data("conformance/interchange/manifest.json"))
    }

    private func errorCode(_ error: any Error) -> String {
        if let edit = error as? DocumentEditError { return edit.diagnostic.code.rawValue }
        if let storage = error as? DocumentStorageError {
            switch storage {
            case .invalidText: return "invalidText"
            case .invalidContainer: return "invalidContainer"
            case .unsupportedVersion: return "unsupportedVersion"
            case .unsupportedPayloadKind: return "unsupportedPayloadKind"
            case .unsupportedCompression: return "unsupportedCompression"
            case .unsupportedFlags: return "unsupportedFlags"
            case .nonzeroReserved: return "nonzeroReserved"
            case .lengthMismatch: return "lengthMismatch"
            case .checksumMismatch: return "checksumMismatch"
            case .invalidUTF8: return "invalidUTF8"
            default: return "unexpectedStorageError"
            }
        }
        if let composition = error as? DocumentCompositionError {
            switch composition {
            case .invalidProfile: return "invalidProfile"
            case .missingTarget: return "missingTarget"
            case .missingRoot: return "missingRoot"
            case .cycle: return "cycle"
            case .duplicateID: return "duplicateID"
            default: return "unexpectedCompositionError"
            }
        }
        return "unexpectedError"
    }

    private struct Catalog: Decodable {
        let schema: String
        let numericVectors: String
        let cases: [Fixture]
    }

    private struct Fixture: Decodable {
        let id: String
        let kind: String
        let sourceFile: String
        let canonicalFile: String?
        let binaryFile: String?
        let formats: [String]
        let expectedError: String?
    }

    private struct LegacyFixture: Decodable {
        let source: String
        let error: String?
    }
}
