import Foundation
import XCTest

@testable import ThreeMD

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class CompositionEditingTests: XCTestCase {
    func testReferenceRetargetMoveAndRemoveKeepInstanceIdentityAndOpaqueAttributes() throws {
        let snapshot = try DocumentCompositionSnapshot(sample())
        let replacement = DocumentReference(targetID: "other", attributes: ["3md-id": "left", "placement": "retained"])
        let result = try CompositionEditor.apply(
            .init(
                expectedRevision: snapshot.revision,
                operations: [
                    .replaceReference(ownerID: "root", id: "left", reference: replacement),
                    .moveReference(ownerID: "root", id: "left", to: 1),
                    .removeReference(ownerID: "root", id: "right"),
                ]
            ),
            to: snapshot
        )
        XCTAssertEqual(result.composition.rootEntry.references, [replacement])
        XCTAssertEqual(result.composition.entry(id: "leaf"), snapshot.composition.entry(id: "leaf"))
        XCTAssertEqual(snapshot.composition.rootEntry.references.map(\.targetID), ["leaf", "leaf"])
        XCTAssertNotEqual(result.revision, snapshot.revision)
    }

    func testFinalGraphValidationAllowsForwardReferenceInsertionAndRootReplacement() throws {
        let snapshot = try DocumentCompositionSnapshot(sample())
        let next = DocumentEntry(
            id: "next",
            document: document("Next"),
            references: [.init(targetID: "other", attributes: ["3md-id": "future"])]
        )
        let result = try CompositionEditor.apply(
            .init(
                expectedRevision: snapshot.revision,
                operations: [
                    .insertReference(
                        ownerID: "root",
                        reference: .init(targetID: "next", attributes: ["3md-id": "next-instance"]),
                        at: 0
                    ),
                    .insertEntry(next), .selectRoot(id: "next"),
                ]
            ),
            to: snapshot
        )
        XCTAssertEqual(result.composition.rootID, "next")
        XCTAssertEqual(result.composition.entry(id: "root")?.references.first?.targetID, "next")
    }

    func testRemovingAndRewritingReferencesValidatesOnlyCompleteFinalGraph() throws {
        let snapshot = try DocumentCompositionSnapshot(sample())
        let result = try CompositionEditor.apply(
            .init(
                expectedRevision: snapshot.revision,
                operations: [
                    .removeEntry(id: "leaf"),
                    .replaceReference(
                        ownerID: "root",
                        id: "left",
                        reference: .init(targetID: "other", attributes: ["3md-id": "left"])
                    ),
                    .removeReference(ownerID: "root", id: "right"),
                ]
            ),
            to: snapshot
        )
        XCTAssertNil(result.composition.entry(id: "leaf"))
        XCTAssertEqual(result.composition.rootEntry.references.first?.targetID, "other")
    }

    func testMissingTargetAndCycleFailuresHaveGraphPathsWithoutPartialPublication() throws {
        let snapshot = try DocumentCompositionSnapshot(sample())
        let missing = CompositionPatch(expectedRevision: snapshot.revision, operations: [.removeEntry(id: "leaf")])
        XCTAssertThrowsError(try CompositionEditor.apply(missing, to: snapshot)) { error in
            let diagnostic = (error as? DocumentEditError)?.diagnostic
            XCTAssertEqual(diagnostic?.code, .invalidComposition)
            XCTAssertEqual(diagnostic?.path, "entries[1].references[0].targetID")
        }
        let cycle = CompositionPatch(
            expectedRevision: snapshot.revision,
            operations: [
                .replaceReference(
                    ownerID: "root",
                    id: "left",
                    reference: .init(targetID: "root", attributes: ["3md-id": "left"])
                )
            ]
        )
        XCTAssertThrowsError(try CompositionEditor.apply(cycle, to: snapshot)) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .invalidComposition)
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.path, "entries[2]")
        }
        XCTAssertEqual(snapshot.composition.entries.count, 3)
    }

    func testReferenceIdentityCannotChangeOrBeDuplicatedWithinOwner() throws {
        let snapshot = try DocumentCompositionSnapshot(sample())
        let changes: [(CompositionEdit, DocumentDiagnostic.Code)] = [
            (
                .replaceReference(
                    ownerID: "root",
                    id: "left",
                    reference: .init(targetID: "leaf", attributes: ["3md-id": "new"])
                ), .identityChanged
            ),
            (
                .insertReference(
                    ownerID: "root",
                    reference: .init(targetID: "leaf", attributes: ["3md-id": "left"]),
                    at: 0
                ), .duplicateIdentity
            ),
            (.insertReference(ownerID: "root", reference: .init(targetID: "leaf"), at: 0), .missingIdentity),
            (.moveReference(ownerID: "root", id: "left", to: 2), .invalidIndex),
            (.removeReference(ownerID: "leaf", id: "left"), .missingTarget),
        ]
        for (operation, code) in changes {
            XCTAssertThrowsError(
                try CompositionEditor.apply(
                    .init(expectedRevision: snapshot.revision, operations: [operation]),
                    to: snapshot
                )
            ) { error in
                XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, code)
                XCTAssertEqual((error as? DocumentEditError)?.diagnostic.path, "operations[0]")
            }
        }
    }

    func testEntryReplacementKeepsIDAndCanEditSharedDefinitionWithoutFlattening() throws {
        let snapshot = try DocumentCompositionSnapshot(sample())
        let replacement = DocumentEntry(id: "leaf", document: document("Changed"))
        let result = try CompositionEditor.apply(
            .init(expectedRevision: snapshot.revision, operations: [.replaceEntry(id: "leaf", entry: replacement)]),
            to: snapshot
        )
        XCTAssertEqual(result.composition.entry(id: "leaf"), replacement)
        XCTAssertEqual(result.composition.rootEntry.references, snapshot.composition.rootEntry.references)
        XCTAssertEqual(result.composition.entries.count, 3)
        XCTAssertThrowsError(
            try CompositionEditor.apply(
                .init(
                    expectedRevision: snapshot.revision,
                    operations: [.replaceEntry(id: "leaf", entry: .init(id: "new", document: document("New")))]
                ),
                to: snapshot
            )
        ) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .identityChanged)
        }
    }

    func testGraphRevisionIncludesReferenceOrderAttributesAndRootAndSurvivesReopen() throws {
        let snapshot = try DocumentCompositionSnapshot(sample())
        let profile = try DocumentCompositionCodec.document(for: snapshot.composition)
        let encoded = try DocumentStorageCodec.encode(profile, format: .binary(compression: .none))
        XCTAssertEqual(
            try DocumentCompositionSnapshot(DocumentCompositionCodec.decode(encoded)).revision,
            snapshot.revision
        )
        for operation in [
            CompositionEdit.selectRoot(id: "leaf"),
            .moveReference(ownerID: "root", id: "left", to: 1),
            .replaceReference(
                ownerID: "root",
                id: "left",
                reference: .init(targetID: "leaf", attributes: ["3md-id": "left", "new": "attribute"])
            ),
        ] {
            let result = try CompositionEditor.apply(
                .init(expectedRevision: snapshot.revision, operations: [operation]),
                to: snapshot
            )
            XCTAssertNotEqual(result.revision, snapshot.revision)
            XCTAssertThrowsError(
                try CompositionEditor.apply(.init(expectedRevision: snapshot.revision, operations: []), to: result)
            ) { error in
                XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .staleRevision)
            }
        }
    }

    func testGraphSnapshotsAndPatchesAreCodableAndDecodedGraphsStillValidate() throws {
        let snapshot = try DocumentCompositionSnapshot(sample())
        XCTAssertEqual(
            try JSONDecoder().decode(DocumentCompositionSnapshot.self, from: JSONEncoder().encode(snapshot)),
            snapshot
        )
        let patch = CompositionPatch(expectedRevision: snapshot.revision, operations: [.selectRoot(id: "leaf")])
        XCTAssertEqual(try JSONDecoder().decode(CompositionPatch.self, from: JSONEncoder().encode(patch)), patch)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.composition)) as? [String: Any]
        )
        object["rootID"] = "missing"
        XCTAssertThrowsError(
            try JSONDecoder().decode(DocumentComposition.self, from: JSONSerialization.data(withJSONObject: object))
        )
    }

    func testGraphTransactionBoundsOperationsPayloadAndDefinitions() throws {
        let snapshot = try DocumentCompositionSnapshot(sample())
        XCTAssertThrowsError(
            try CompositionEditor.apply(
                .init(expectedRevision: snapshot.revision, operations: [.selectRoot(id: "leaf")]),
                to: snapshot,
                limits: .init(maximumOperations: 0)
            )
        ) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .operationLimit)
        }
        XCTAssertThrowsError(
            try CompositionEditor.apply(
                .init(
                    expectedRevision: snapshot.revision,
                    operations: [
                        .insertEntry(.init(id: "huge", document: document(String(repeating: "x", count: 128))))
                    ]
                ),
                to: snapshot,
                limits: .init(maximumPayloadBytes: 64)
            )
        ) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .payloadLimit)
        }
        XCTAssertThrowsError(
            try CompositionEditor.apply(
                .init(
                    expectedRevision: snapshot.revision,
                    operations: [.insertEntry(.init(id: "extra", document: document("Extra")))]
                ),
                to: snapshot,
                compositionLimits: .init(maximumDefinitions: 3)
            )
        ) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .payloadLimit)
        }
    }

    func testCancelledGraphTransactionPropagatesCancellation() async throws {
        let snapshot = try DocumentCompositionSnapshot(sample())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try CompositionEditor.apply(
                .init(expectedRevision: snapshot.revision, operations: [.removeEntry(id: "leaf")]),
                to: snapshot
            )
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch {
            XCTFail("\(error)")
        }
    }

    private func sample() throws -> DocumentComposition {
        try DocumentComposition(
            rootID: "root",
            entries: [
                .init(
                    id: "root",
                    document: document("Root"),
                    references: [
                        .init(targetID: "leaf", attributes: ["3md-id": "left", "placement": "retained"]),
                        .init(targetID: "leaf", attributes: ["3md-id": "right"]),
                    ]
                ),
                .init(id: "leaf", document: document("Leaf")), .init(id: "other", document: document("Other")),
            ]
        )
    }
    private func document(_ body: String) -> Document {
        .init(version: "0.1", axis: .layer, planes: [.init(z: 0, attributes: ["3md-id": "plane-1"], body: body)])
    }
}
