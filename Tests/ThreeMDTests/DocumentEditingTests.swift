import Foundation
import XCTest

@testable import ThreeMD

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class DocumentEditingTests: XCTestCase {
    func testAtomicCoordinateSwapRetainsIDsSourceOrderMetadataAndLegacyLinks() throws {
        let snapshot = try DocumentSnapshot(sample())
        let patch = DocumentPatch(
            expectedRevision: snapshot.revision,
            operations: [
                .replace(id: "first", plane: plane("first", z: 1, body: "[[z=1]]")),
                .replace(id: "second", plane: plane("second", z: 0, body: "Second")),
            ]
        )
        let result = try DocumentEditor.apply(patch, to: snapshot)
        XCTAssertEqual(result.document.planes.map(\.z), [1, 0])
        XCTAssertEqual(result.document.planes.map(\.stableID), ["first", "second"])
        XCTAssertEqual(result.document.metadata, snapshot.document.metadata)
        XCTAssertEqual(result.document.planes.first?.body, "[[z=1]]")
        XCTAssertNotEqual(result.revision, snapshot.revision)
        XCTAssertEqual(snapshot.document.planes.map(\.z), [0, 1])
    }

    func testInsertMoveRemoveAndHeaderTransactionPreservesUnrelatedPlanes() throws {
        let snapshot = try DocumentSnapshot(sample())
        let header = DocumentHeader(version: "1.0", axis: .time, title: "New", metadata: ["custom": "yes"])
        let result = try DocumentEditor.apply(
            .init(
                expectedRevision: snapshot.revision,
                operations: [
                    .insert(plane: plane("third", z: 2, body: "Third"), at: 1),
                    .move(id: "second", to: 0), .remove(id: "third"), .replaceHeader(header),
                ]
            ),
            to: snapshot
        )
        XCTAssertEqual(result.document.planes.map(\.stableID), ["second", "first"])
        XCTAssertEqual(result.document.planes, [snapshot.document.planes[1], snapshot.document.planes[0]])
        XCTAssertEqual(result.document.title, "New")
        XCTAssertEqual(result.document.axis, .time)
    }

    func testFinalCoordinateConflictReturnsPrecisePathAndNoMutation() throws {
        let snapshot = try DocumentSnapshot(sample())
        let patch = DocumentPatch(
            expectedRevision: snapshot.revision,
            operations: [
                .replace(id: "first", plane: plane("first", z: 1, body: "Changed"))
            ]
        )
        failure(.duplicatePosition, path: "planes[1].z") { try DocumentEditor.apply(patch, to: snapshot) }
        XCTAssertEqual(snapshot.document, sample())
    }

    func testFailureAfterValidFirstOperationPublishesNothing() throws {
        let snapshot = try DocumentSnapshot(sample())
        let patch = DocumentPatch(
            expectedRevision: snapshot.revision,
            operations: [.remove(id: "first"), .remove(id: "absent")]
        )
        failure(.missingTarget, path: "operations[1]") { try DocumentEditor.apply(patch, to: snapshot) }
        XCTAssertEqual(snapshot.document.planes.count, 2)
    }

    func testReplacementCannotSilentlyChangeOrDropIdentity() throws {
        let snapshot = try DocumentSnapshot(sample())
        for replacement in [plane("different", z: 0, body: "New"), Plane(z: 0, body: "New")] {
            failure(.identityChanged, path: "operations[0]") {
                try DocumentEditor.apply(
                    .init(expectedRevision: snapshot.revision, operations: [.replace(id: "first", plane: replacement)]),
                    to: snapshot
                )
            }
        }
    }

    func testInvalidInsertMoveAndDuplicateIdentityAreDiagnosed() throws {
        let snapshot = try DocumentSnapshot(sample())
        let cases: [(DocumentEdit, DocumentDiagnostic.Code)] = [
            (.insert(plane: plane("third", z: 2, body: "Third"), at: -1), .invalidIndex),
            (.move(id: "first", to: 2), .invalidIndex),
            (.insert(plane: Plane(z: 2, body: "Third"), at: 2), .missingIdentity),
            (.insert(plane: plane("first", z: 2, body: "Third"), at: 2), .duplicateIdentity),
            (.remove(id: "../unsafe"), .invalidIdentity),
        ]
        for (operation, code) in cases {
            failure(code, path: "operations[0]") {
                try DocumentEditor.apply(
                    .init(expectedRevision: snapshot.revision, operations: [operation]),
                    to: snapshot
                )
            }
        }
    }

    func testNoIdentityLegacyDocumentRequiresExplicitAdoptionForTargetedEdits() throws {
        let document = Document(
            version: "0.1",
            axis: .layer,
            planes: [Plane(z: 0, attributes: ["id": "first"], body: "Body")]
        )
        let snapshot = try DocumentSnapshot(document)
        failure(.missingTarget, path: "operations[0]") {
            try DocumentEditor.apply(
                .init(expectedRevision: snapshot.revision, operations: [.remove(id: "first")]),
                to: snapshot
            )
        }
        let adopted = try DocumentSnapshot(DocumentIdentity.adopt(document))
        let result = try DocumentEditor.apply(
            .init(expectedRevision: adopted.revision, operations: [.remove(id: "plane-1")]),
            to: adopted
        )
        XCTAssertTrue(result.document.planes.isEmpty)
    }

    func testStaleExactRevisionRejectsChangedContentAndUnicodeEquivalentBytes() throws {
        let snapshot = try DocumentSnapshot(sample())
        failure(.staleRevision, path: "expectedRevision") {
            try DocumentEditor.apply(
                .init(
                    expectedRevision: .init(canonicalContent: snapshot.revision.canonicalContent + " "),
                    operations: []
                ),
                to: snapshot
            )
        }
        let composed = "caf\u{E9}"
        let decomposed = "cafe\u{301}"
        XCTAssertEqual(composed, decomposed)
        XCTAssertNotEqual(DocumentRevision(canonicalContent: composed), DocumentRevision(canonicalContent: decomposed))
        let unicode = try DocumentSnapshot(
            Document(version: "0.1", axis: .layer, planes: [plane("first", z: 0, body: composed)])
        )
        let expected = DocumentRevision(
            canonicalContent: unicode.revision.canonicalContent.replacingOccurrences(of: composed, with: decomposed)
        )
        failure(.staleRevision, path: "expectedRevision") {
            try DocumentEditor.apply(.init(expectedRevision: expected, operations: []), to: unicode)
        }
    }

    func testCanonicalReopenHasSameRevisionAndCodableValuesRoundTrip() throws {
        let snapshot = try DocumentSnapshot(sample())
        let reopened = try DocumentStorageCodec.decode(
            DocumentStorageCodec.encode(snapshot.document, format: .binary(compression: .none))
        )
        XCTAssertEqual(try DocumentSnapshot(reopened).revision, snapshot.revision)
        XCTAssertEqual(try JSONDecoder().decode(DocumentSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let patch = DocumentPatch(expectedRevision: snapshot.revision, operations: [.move(id: "first", to: 1)])
        XCTAssertEqual(try JSONDecoder().decode(DocumentPatch.self, from: JSONEncoder().encode(patch)), patch)
    }

    func testSnapshotDecoderRejectsForgedRevision() throws {
        let snapshot = try DocumentSnapshot(sample())
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["revision"] = ["canonicalContent": "forged"]
        XCTAssertThrowsError(
            try JSONDecoder().decode(DocumentSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        )
    }

    func testOperationOperandAndExpectedRevisionBudgetsAreEnforced() throws {
        let snapshot = try DocumentSnapshot(sample())
        let operation = DocumentEdit.remove(id: "first")
        failure(.operationLimit, path: "operations") {
            try DocumentEditor.apply(
                .init(expectedRevision: snapshot.revision, operations: [operation]),
                to: snapshot,
                limits: .init(maximumOperations: 0)
            )
        }
        failure(.payloadLimit, path: nil) {
            try DocumentEditor.apply(
                .init(expectedRevision: snapshot.revision, operations: [operation]),
                to: snapshot,
                limits: .init(maximumPayloadBytes: 5)
            )
        }
        let oversized = DocumentRevision(canonicalContent: String(repeating: "x", count: 129))
        failure(.payloadLimit, path: "expectedRevision") {
            try DocumentEditor.apply(
                .init(expectedRevision: oversized, operations: []),
                to: snapshot,
                documentLimits: .init(maximumDecodedBytes: 128)
            )
        }
    }

    func testInvalidFinalDirectValuesCannotEscapeStorageValidation() throws {
        let snapshot = try DocumentSnapshot(sample())
        failure(.invalidDocument, path: nil) {
            try DocumentEditor.apply(
                .init(
                    expectedRevision: snapshot.revision,
                    operations: [.replace(id: "first", plane: plane("first", z: .nan, body: "Invalid"))]
                ),
                to: snapshot
            )
        }
        failure(.invalidDocument, path: nil) {
            try DocumentEditor.apply(
                .init(
                    expectedRevision: snapshot.revision,
                    operations: [.replaceHeader(.init(version: "", axis: .layer))]
                ),
                to: snapshot
            )
        }
    }

    func testCancelledTransactionPropagatesCancellation() async throws {
        let snapshot = try DocumentSnapshot(sample())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DocumentEditor.apply(
                .init(expectedRevision: snapshot.revision, operations: [.remove(id: "first")]),
                to: snapshot
            )
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch {
            XCTFail("\(error)")
        }
        XCTAssertEqual(snapshot.document.planes.count, 2)
    }

    private func sample() -> Document {
        .init(
            version: "0.1",
            axis: .layer,
            title: "Example",
            metadata: ["custom": "retained"],
            planes: [
                plane("first", z: 0, body: "[[z=1]]"), plane("second", z: 1, body: "Second"),
            ]
        )
    }
    private func plane(_ id: String, z: Double, body: String) -> Plane {
        .init(z: z, attributes: ["3md-id": id], body: body)
    }
    private func failure<T>(_ code: DocumentDiagnostic.Code, path: String?, _ operation: () throws -> T) {
        XCTAssertThrowsError(try operation()) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, code)
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.path, path)
        }
    }
}
