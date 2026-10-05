import Foundation
import XCTest

@testable import ThreeMD

/// Extension goldens are shared with the TypeScript and Rust readers without changing text conformance vectors.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class ExtensionConformanceTests: XCTestCase {
    func testCanonicalNumericBitPatternsMatchSharedSwiftFormattingVectors() throws {
        let fixture = try decode(NumericFixture.self, file: "numeric-vectors.json")
        XCTAssertEqual(fixture.schema, "3md-canonical-numbers-1")
        XCTAssertEqual(fixture.vectors.count, 45)
        XCTAssertEqual(Set(fixture.vectors.map(\.name)).count, fixture.vectors.count)
        for vector in fixture.vectors {
            XCTAssertEqual(vector.bitPattern.count, 16, vector.name)
            let bits = try XCTUnwrap(UInt64(vector.bitPattern, radix: 16), vector.name)
            let value = Double(bitPattern: bits)
            XCTAssertTrue(value.isFinite, vector.name)
            XCTAssertEqual(value.formatted3MD(), vector.formatted, vector.name)
            let document = Document(version: "0.1", axis: .layer, planes: [.init(z: value, body: "Number")])
            let source = try DocumentStorageCodec.encode(document)
            XCTAssertTrue(
                String(decoding: source, as: UTF8.self).contains("@plane z=\(vector.formatted)\n"),
                vector.name
            )
            let restored = try XCTUnwrap(DocumentStorageCodec.decode(source).planes.first, vector.name)
            // The pre-existing canonical text policy writes both signs of zero as 0.
            XCTAssertEqual(restored.z.bitPattern, value == 0 ? 0 : bits, vector.name)
        }
    }

    func testDocumentEnvelopeAndProfileGoldensMatchExactCanonicalBytes() throws {
        let manifest = try decode(Manifest.self, file: "manifest.json")
        XCTAssertEqual(manifest.schema, "3md-extension-fixtures-1")
        XCTAssertEqual(manifest.compression, "none")
        XCTAssertEqual(manifest.numericVectors, "numeric-vectors.json")
        XCTAssertEqual(manifest.editingVectors, "editing-vectors.json")
        XCTAssertEqual(Set(manifest.fixtures.map(\.name)), ["document-unicode", "composition-instances"])
        for record in manifest.fixtures {
            let source = try data(record.sourceFile)
            let binary = try data(record.binaryFile)
            XCTAssertEqual(source.count, record.sourceBytes, record.name)
            XCTAssertEqual(binary.count, record.binaryBytes, record.name)
            XCTAssertEqual(binary.count, source.count + DocumentStorageCodec.headerByteCount, record.name)
            XCTAssertEqual(binary.prefix(8), Data("3mdbin\r\n".utf8), record.name)
            XCTAssertEqual(binary[11], DocumentCompression.none.rawValue, record.name)
            XCTAssertEqual(Data(binary.dropFirst(DocumentStorageCodec.headerByteCount)), source, record.name)
            switch record.kind {
            case "document":
                let expected = try decode(Document.self, file: record.expectedFile)
                XCTAssertEqual(try DocumentStorageCodec.decode(source), expected, record.name)
                XCTAssertEqual(try DocumentStorageCodec.decode(binary), expected, record.name)
                XCTAssertEqual(try DocumentStorageCodec.encode(expected), source, record.name)
                XCTAssertEqual(
                    try DocumentStorageCodec.encode(expected, format: .binary(compression: .none)),
                    binary,
                    record.name
                )
            case "composition":
                let expected = try decode(DocumentComposition.self, file: record.expectedFile)
                XCTAssertEqual(try DocumentCompositionCodec.decode(source), expected, record.name)
                XCTAssertEqual(try DocumentCompositionCodec.decode(binary), expected, record.name)
                XCTAssertEqual(try DocumentCompositionCodec.encode(expected), source, record.name)
                let profile = try DocumentCompositionCodec.document(for: expected)
                XCTAssertEqual(
                    try DocumentStorageCodec.encode(profile, format: .binary(compression: .none)),
                    binary,
                    record.name
                )
            default: XCTFail("Unsupported extension fixture kind: \(record.kind)")
            }
        }
    }

    func testSharedBinaryChecksumGoldensRejectCorruption() throws {
        let manifest = try decode(Manifest.self, file: "manifest.json")
        for record in manifest.fixtures {
            var binary = try data(record.binaryFile)
            binary[binary.index(before: binary.endIndex)] ^= 1
            XCTAssertThrowsError(try DocumentStorageCodec.decode(binary), record.name) { error in
                XCTAssertEqual(error as? DocumentStorageError, .checksumMismatch, record.name)
            }
        }
    }

    func testUnicodeKeyOrderingGoldensPreserveOriginalSpellingAndExactBytes() throws {
        let fixture = try decode(Manifest.self, file: "manifest.json").unicodeFixtures
        let expected = try decode(Document.self, file: fixture.documentExpectedFile)
        let source = try data(fixture.documentSourceFile)
        let binary = try data(fixture.documentBinaryFile)
        XCTAssertEqual(try DocumentStorageCodec.encode(expected), source)
        XCTAssertEqual(try DocumentStorageCodec.encode(expected, format: .binary(compression: .none)), binary)
        XCTAssertEqual(try DocumentStorageCodec.decode(source), expected)
        XCTAssertEqual(try DocumentStorageCodec.decode(binary), expected)
        let originalKey = try XCTUnwrap(expected.metadata.keys.first(where: { $0 == "é" }))
        XCTAssertEqual(Array(originalKey.utf8), [0x65, 0xCC, 0x81])
        XCTAssertEqual(expected.metadata[originalKey], "last")
        XCTAssertEqual(
            expected.metadata.keys.sorted().map { Array($0.unicodeScalars.map(\.value)) },
            [
                [0x7A], [0x65, 0x301], [0xE000], [0x1F600],
            ]
        )
        let snapshot = try DocumentSnapshot(expected)
        let changedSpelling = DocumentRevision(
            canonicalContent: snapshot.revision.canonicalContent.replacingOccurrences(of: "e\u{301}", with: "é")
        )
        XCTAssertNotEqual(changedSpelling, snapshot.revision)
        XCTAssertThrowsError(
            try DocumentEditor.apply(.init(expectedRevision: changedSpelling, operations: []), to: snapshot)
        ) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .staleRevision)
        }
    }

    func testUnicodeSourceKeyCollisionsKeepFirstSpellingAndLastValue() throws {
        let fixture = try decode(Manifest.self, file: "manifest.json").unicodeFixtures
        let expected = try decode(Document.self, file: fixture.sourceCollisionExpectedFile)
        let source = try data(fixture.sourceCollisionFile)
        let document = try DocumentStorageCodec.decode(source)
        XCTAssertEqual(document, expected)
        XCTAssertEqual(document.metadata.count, 1)
        XCTAssertEqual(document.metadata["é"], "last")
        XCTAssertEqual(Array(try XCTUnwrap(document.metadata.keys.first).utf8), [0x65, 0xCC, 0x81])
        let key = try XCTUnwrap(document.planes.first?.attributes.keys.first(where: { $0 == "é" }))
        XCTAssertEqual(Array(key.utf8), [0x65, 0xCC, 0x81])
        XCTAssertEqual(document.planes.first?.attributes[key], "last")
        let canonical = try DocumentStorageCodec.encode(document)
        XCTAssertEqual(try DocumentStorageCodec.decode(canonical), expected)
    }

    func testStrictCompositionJSONRejectsCanonicallyEquivalentDuplicateKeys() throws {
        let fixture = try decode(Manifest.self, file: "manifest.json").unicodeFixtures
        XCTAssertEqual(fixture.compositionDuplicateError, "invalidProfile")
        XCTAssertThrowsError(try DocumentCompositionCodec.decode(data(fixture.compositionDuplicateFile))) { error in
            XCTAssertEqual(error as? DocumentCompositionError, .invalidProfile("duplicate JSON object key"))
        }
    }

    func testSharedIdentityAdoptionPreservesOpaqueFieldsAndOwnerScopes() throws {
        let fixture = try semanticFixture()
        XCTAssertEqual(try DocumentIdentity.adopt(fixture.documentAdoption.input), fixture.documentAdoption.expected)
        XCTAssertEqual(
            try DocumentIdentity.adopt(fixture.compositionAdoption.input),
            fixture.compositionAdoption.expected
        )
        XCTAssertEqual(fixture.documentAdoption.expected.planes.map(\.stableID), ["plane-main", "plane-1"])
        XCTAssertEqual(fixture.documentAdoption.expected.planes[1].attributes["id"], "ordinary-id")
        XCTAssertEqual(
            fixture.compositionAdoption.expected.rootEntry.references.map(\.stableID),
            ["reference-1", "right", "nested"]
        )
        XCTAssertEqual(fixture.compositionAdoption.expected.entry(id: "other")?.references.first?.stableID, "left")
        XCTAssertEqual(
            fixture.compositionAdoption.expected.rootEntry.references.first?.attributes["id"],
            "opaque-instance"
        )
    }

    func testSharedDocumentTransactionsValidateFinalValuesAtomically() throws {
        let fixture = try semanticFixture()
        let document = try decode(Document.self, file: "\(fixture.documentFixture).json")
        let snapshot = try DocumentSnapshot(document)
        XCTAssertEqual(fixture.documentTransactions.map(\.name), ["atomic-coordinate-swap", "source-order-change"])
        for vector in fixture.documentTransactions {
            let operations = try vector.operations.map(documentEdit)
            let result = try DocumentEditor.apply(
                .init(expectedRevision: snapshot.revision, operations: operations),
                to: snapshot
            )
            XCTAssertEqual(result.document, vector.expected, vector.name)
            XCTAssertNotEqual(result.revision, snapshot.revision, vector.name)
            XCTAssertEqual(snapshot.document, document, vector.name)
            XCTAssertEqual(
                Set(result.document.planes.compactMap(\.stableID)),
                Set(document.planes.compactMap(\.stableID)),
                vector.name
            )
        }
    }

    func testSharedCompositionTransactionsKeepUnchangedDefinitionsAndRepeatedInstances() throws {
        let fixture = try semanticFixture()
        let composition = try decode(DocumentComposition.self, file: "\(fixture.compositionFixture).json")
        let snapshot = try DocumentCompositionSnapshot(composition)
        XCTAssertEqual(fixture.compositionTransactions.count, 2)
        for vector in fixture.compositionTransactions {
            let operations = try vector.operations.map(compositionEdit)
            let result = try CompositionEditor.apply(
                .init(expectedRevision: snapshot.revision, operations: operations),
                to: snapshot
            )
            XCTAssertEqual(result.composition, vector.expected, vector.name)
            XCTAssertNotEqual(result.revision, snapshot.revision, vector.name)
            XCTAssertEqual(result.composition.entry(id: "leaf"), composition.entry(id: "leaf"), vector.name)
            XCTAssertEqual(result.composition.entry(id: "other"), composition.entry(id: "other"), vector.name)
            XCTAssertEqual(snapshot.composition, composition, vector.name)
        }
    }

    func testSharedFailedTransactionsHaveStableCodesPathsAndNoPartialPublication() throws {
        let fixture = try semanticFixture()
        let document = try decode(Document.self, file: "\(fixture.documentFixture).json")
        let composition = try decode(DocumentComposition.self, file: "\(fixture.compositionFixture).json")
        let documentSnapshot = try DocumentSnapshot(document)
        let compositionSnapshot = try DocumentCompositionSnapshot(composition)
        XCTAssertEqual(fixture.failures.count, 6)
        for vector in fixture.failures {
            let canonical =
                vector.scope == "document"
                ? documentSnapshot.revision.canonicalContent : compositionSnapshot.revision.canonicalContent
            let revision = DocumentRevision(canonicalContent: canonical + (vector.expectedRevisionSuffix ?? ""))
            XCTAssertThrowsError(
                try {
                    switch vector.scope {
                    case "document":
                        _ = try DocumentEditor.apply(
                            .init(expectedRevision: revision, operations: vector.operations.map(documentEdit)),
                            to: documentSnapshot
                        )
                    case "composition":
                        _ = try CompositionEditor.apply(
                            .init(expectedRevision: revision, operations: vector.operations.map(compositionEdit)),
                            to: compositionSnapshot
                        )
                    default: XCTFail("Unsupported transaction scope: \(vector.scope)")
                    }
                }(),
                vector.name
            ) { error in
                let diagnostic = (error as? DocumentEditError)?.diagnostic
                XCTAssertEqual(diagnostic?.code.rawValue, vector.expectedCode, vector.name)
                XCTAssertEqual(diagnostic?.path, vector.expectedPath, vector.name)
                XCTAssertNil(diagnostic?.sourceLine, vector.name)
            }
        }
        XCTAssertEqual(documentSnapshot.document, document)
        XCTAssertEqual(compositionSnapshot.composition, composition)
    }

    private func semanticFixture() throws -> SemanticFixture {
        let fixture = try decode(SemanticFixture.self, file: "editing-vectors.json")
        XCTAssertEqual(fixture.schema, "3md-editing-semantic-fixtures-1")
        return fixture
    }

    private func documentEdit(_ command: SemanticCommand) throws -> DocumentEdit {
        switch command.kind {
        case "replace": return .replace(id: try XCTUnwrap(command.id), plane: try XCTUnwrap(command.plane))
        case "move": return .move(id: try XCTUnwrap(command.id), to: try XCTUnwrap(command.to))
        default: throw FixtureError.unsupportedCommand(command.kind)
        }
    }

    private func compositionEdit(_ command: SemanticCommand) throws -> CompositionEdit {
        switch command.kind {
        case "replaceReference":
            return .replaceReference(
                ownerID: try XCTUnwrap(command.ownerID),
                id: try XCTUnwrap(command.id),
                reference: try XCTUnwrap(command.reference)
            )
        case "moveReference":
            return .moveReference(
                ownerID: try XCTUnwrap(command.ownerID),
                id: try XCTUnwrap(command.id),
                to: try XCTUnwrap(command.to)
            )
        case "removeReference":
            return .removeReference(ownerID: try XCTUnwrap(command.ownerID), id: try XCTUnwrap(command.id))
        default: throw FixtureError.unsupportedCommand(command.kind)
        }
    }

    private func data(_ file: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("conformance/extensions")
        return try Data(contentsOf: directory.appendingPathComponent(file))
    }

    private func decode<Value: Decodable>(_ type: Value.Type, file: String) throws -> Value {
        try JSONDecoder().decode(type, from: data(file))
    }

    private enum FixtureError: Error { case unsupportedCommand(String) }
    private struct NumericFixture: Decodable {
        let schema: String
        let vectors: [NumericVector]
    }
    private struct NumericVector: Decodable {
        let name: String
        let bitPattern: String
        let formatted: String
    }
    private struct Manifest: Decodable {
        let schema: String
        let numericVectors: String
        let editingVectors: String
        let compression: String
        let fixtures: [FixtureRecord]
        let unicodeFixtures: UnicodeFixtures
    }
    private struct UnicodeFixtures: Decodable {
        let documentSourceFile: String
        let documentBinaryFile: String
        let documentExpectedFile: String
        let sourceCollisionFile: String
        let sourceCollisionExpectedFile: String
        let compositionDuplicateFile: String
        let compositionDuplicateError: String
    }
    private struct FixtureRecord: Decodable {
        let name: String
        let kind: String
        let sourceFile: String
        let binaryFile: String
        let expectedFile: String
        let sourceBytes: Int
        let binaryBytes: Int
    }
    private struct SemanticCommand: Decodable {
        let kind: String
        let id: String?
        let plane: Plane?
        let to: Int?
        let ownerID: String?
        let reference: DocumentReference?
    }
    private struct Adoption<Value: Decodable>: Decodable {
        let input: Value
        let expected: Value
    }
    private struct DocumentTransaction: Decodable {
        let name: String
        let operations: [SemanticCommand]
        let expected: Document
    }
    private struct CompositionTransaction: Decodable {
        let name: String
        let operations: [SemanticCommand]
        let expected: DocumentComposition
    }
    private struct FailureVector: Decodable {
        let name: String
        let scope: String
        let operations: [SemanticCommand]
        let expectedCode: String
        let expectedPath: String
        let expectedRevisionSuffix: String?
    }
    private struct SemanticFixture: Decodable {
        let schema: String
        let documentFixture: String
        let compositionFixture: String
        let documentAdoption: Adoption<Document>
        let compositionAdoption: Adoption<DocumentComposition>
        let documentTransactions: [DocumentTransaction]
        let compositionTransactions: [CompositionTransaction]
        let failures: [FailureVector]
    }
}
