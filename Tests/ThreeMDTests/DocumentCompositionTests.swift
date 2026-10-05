import Foundation
import XCTest

@testable import ThreeMD

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class DocumentCompositionTests: XCTestCase {
    func testSharedNestedDefinitionsPreserveAxesMetadataAndReferenceOrder() throws {
        let leaf = DocumentEntry(id: "leaf", document: sampleDocument())
        let left = DocumentEntry(id: "left", document: plainDocument("Left"), references: [.init(targetID: "leaf")])
        let right = DocumentEntry(id: "right", document: plainDocument("Right"), references: [.init(targetID: "leaf")])
        let root = DocumentEntry(
            id: "root",
            document: plainDocument("Root"),
            references: [
                .init(targetID: "right", attributes: ["binding": "B", "rotation": "clockwise"]),
                .init(targetID: "left", attributes: ["binding": "A"]),
            ]
        )
        let composition = try DocumentComposition(rootID: "root", entries: [root, right, leaf, left])
        XCTAssertEqual(composition.entries.map(\.id), ["leaf", "left", "right", "root"])
        XCTAssertEqual(composition.rootEntry, root)
        XCTAssertEqual(composition.rootEntry.references.map(\.targetID), ["right", "left"])
        XCTAssertEqual(composition.entry(id: "leaf")?.document, sampleDocument())
        XCTAssertNil(composition.entry(id: "/tmp/leaf.3md"))
        XCTAssertEqual(try DocumentCompositionCodec.decode(DocumentCompositionCodec.encode(composition)), composition)
    }

    func testEveryDefinitionIsValidatedEvenWhenUnused() throws {
        let invalid = DocumentEntry(
            id: "unused",
            document: Document(version: "0.1", axis: .layer, planes: [Plane(z: .nan, body: "invalid")])
        )
        XCTAssertThrowsError(
            try DocumentComposition(
                rootID: "root",
                entries: [DocumentEntry(id: "root", document: plainDocument()), invalid]
            )
        ) { error in
            guard case .invalidDocument = error as? DocumentStorageError else {
                return XCTFail("Expected direct document validation, received \(error)")
            }
        }
    }

    func testMissingRootMissingTargetAndDuplicateDefinitionsAreRejected() throws {
        let root = DocumentEntry(id: "root", document: plainDocument())
        assertFailure(.missingRoot("missing")) { try DocumentComposition(rootID: "missing", entries: [root]) }
        assertFailure(.duplicateID("root")) { try DocumentComposition(rootID: "root", entries: [root, root]) }
        let reference = DocumentEntry(id: "unused", document: plainDocument(), references: [.init(targetID: "absent")])
        assertFailure(.missingTarget(from: "unused", target: "absent")) {
            try DocumentComposition(rootID: "root", entries: [root, reference])
        }
    }

    func testIDsAreCaseSensitiveAndNeverFileOrNetworkLocations() throws {
        for id in [
            "", "../model", "/tmp/model", "https://example.org/model", "bad.id", " bad", "é",
            String(repeating: "a", count: 65),
        ] {
            assertFailure(.invalidID(id)) {
                try DocumentComposition(rootID: id, entries: [DocumentEntry(id: id, document: plainDocument())])
            }
        }
        let composition = try DocumentComposition(
            rootID: "A",
            entries: [
                DocumentEntry(id: "a", document: plainDocument()), DocumentEntry(id: "A", document: plainDocument()),
            ]
        )
        XCTAssertEqual(composition.entries.map(\.id), ["A", "a"])
        XCTAssertEqual(composition.entry(id: "A")?.id, "A")
    }

    func testCyclesAreRejectedInRootAndUnusedNodes() throws {
        let selfCycle = DocumentEntry(id: "root", document: plainDocument(), references: [.init(targetID: "root")])
        assertFailure(.cycle("root")) { try DocumentComposition(rootID: "root", entries: [selfCycle]) }
        let root = DocumentEntry(id: "root", document: plainDocument())
        let a = DocumentEntry(id: "a", document: plainDocument(), references: [.init(targetID: "b")])
        let b = DocumentEntry(id: "b", document: plainDocument(), references: [.init(targetID: "a")])
        assertFailure(.cycle("a")) { try DocumentComposition(rootID: "root", entries: [root, a, b]) }
    }

    func testDefinitionDepthAndReferenceBudgetsHaveExactBoundarySemantics() throws {
        let leaf = DocumentEntry(id: "leaf", document: plainDocument())
        let middle = DocumentEntry(id: "middle", document: plainDocument(), references: [.init(targetID: "leaf")])
        let root = DocumentEntry(id: "root", document: plainDocument(), references: [.init(targetID: "middle")])
        _ = try DocumentComposition(rootID: "root", entries: [leaf, middle, root], limits: .init(maximumDepth: 3))
        assertFailure(.depthExceeded) {
            try DocumentComposition(rootID: "root", entries: [leaf, middle, root], limits: .init(maximumDepth: 2))
        }
        assertFailure(.tooManyDefinitions) {
            try DocumentComposition(
                rootID: "root",
                entries: [leaf, middle, root],
                limits: .init(maximumDefinitions: 2)
            )
        }
        assertFailure(.tooManyReferences) {
            try DocumentComposition(rootID: "root", entries: [leaf, middle, root], limits: .init(maximumReferences: 1))
        }
    }

    func testOccurrenceBudgetCountsSharedReferencesWithoutMaterializingThem() throws {
        let leaf = DocumentEntry(id: "leaf", document: plainDocument())
        let root = DocumentEntry(
            id: "root",
            document: plainDocument(),
            references: [.init(targetID: "leaf"), .init(targetID: "leaf")]
        )
        _ = try DocumentComposition(
            rootID: "root",
            entries: [leaf, root],
            limits: .init(maximumTraversalOccurrences: 3)
        )
        assertFailure(.traversalOccurrencesExceeded) {
            try DocumentComposition(
                rootID: "root",
                entries: [leaf, root],
                limits: .init(maximumTraversalOccurrences: 2)
            )
        }
        var exponentiallyShared = [DocumentEntry(id: "n0", document: plainDocument())]
        for index in 1...20 {
            exponentiallyShared.append(
                .init(
                    id: "n\(index)",
                    document: plainDocument(),
                    references: [.init(targetID: "n\(index - 1)"), .init(targetID: "n\(index - 1)")]
                )
            )
        }
        assertFailure(.traversalOccurrencesExceeded) {
            try DocumentComposition(rootID: "n20", entries: exponentiallyShared)
        }
    }

    func testUnusedDepthAndOccurrenceBudgetsAreAlsoEnforced() throws {
        let entries = [
            DocumentEntry(id: "root", document: plainDocument()),
            DocumentEntry(
                id: "unused",
                document: plainDocument(),
                references: [.init(targetID: "leaf"), .init(targetID: "leaf")]
            ),
            DocumentEntry(id: "leaf", document: plainDocument()),
        ]
        assertFailure(.traversalOccurrencesExceeded) {
            try DocumentComposition(rootID: "root", entries: entries, limits: .init(maximumTraversalOccurrences: 2))
        }
        assertFailure(.depthExceeded) {
            try DocumentComposition(rootID: "root", entries: entries, limits: .init(maximumDepth: 1))
        }
    }

    func testUniqueSourceByteBudgetCountsEachDefinitionOnce() throws {
        let document = plainDocument()
        let count = try DocumentStorageCodec.encode(document).count
        let leaf = DocumentEntry(id: "leaf", document: document)
        let root = DocumentEntry(
            id: "root",
            document: document,
            references: [.init(targetID: "leaf"), .init(targetID: "leaf")]
        )
        _ = try DocumentComposition(
            rootID: "root",
            entries: [root, leaf],
            limits: .init(maximumDefinitionBytes: count * 2)
        )
        assertFailure(.definitionBytesExceeded) {
            try DocumentComposition(
                rootID: "root",
                entries: [root, leaf],
                limits: .init(maximumDefinitionBytes: count * 2 - 1)
            )
        }
    }

    func testReferenceAttributesAreOpaqueUnicodeDataWithCountAndByteLimits() throws {
        let leaf = DocumentEntry(id: "leaf", document: plainDocument())
        let root = DocumentEntry(
            id: "root",
            document: plainDocument(),
            references: [.init(targetID: "leaf", attributes: ["": "🌙", "location": "file:///not-read.3md"])]
        )
        let composition = try DocumentComposition(rootID: "root", entries: [root, leaf])
        XCTAssertEqual(try DocumentCompositionCodec.decode(DocumentCompositionCodec.encode(composition)), composition)
        assertFailure(.referenceAttributesExceeded) {
            try DocumentComposition(
                rootID: "root",
                entries: [root, leaf],
                limits: .init(maximumReferenceAttributes: 1)
            )
        }
        assertFailure(.referenceAttributesExceeded) {
            try DocumentComposition(
                rootID: "root",
                entries: [root, leaf],
                limits: .init(maximumReferenceAttributeBytes: 3)
            )
        }
    }

    func testDefinitionDocumentPolicyIsIndependentOfCompositionPolicy() throws {
        let document = Document(
            version: "future",
            axis: .time,
            planes: [Plane(z: 0, body: "A"), Plane(z: 1, body: "B")]
        )
        let entry = DocumentEntry(id: "root", document: document)
        XCTAssertThrowsError(
            try DocumentComposition(rootID: "root", entries: [entry], documentLimits: .init(maximumPlanes: 1))
        ) {
            XCTAssertEqual($0 as? DocumentStorageError, .tooManyPlanes)
        }
    }

    func testResourceLimitsCannotBeRaisedBeyondAbsoluteBounds() {
        XCTAssertThrowsError(try DocumentCompositionLimits(maximumDefinitions: 1_025))
        XCTAssertThrowsError(try DocumentCompositionLimits(maximumDepth: 0))
        XCTAssertThrowsError(try DocumentCompositionLimits(maximumProfileBytes: 20 * 1_024 * 1_024 + 1))
        XCTAssertThrowsError(try DocumentCompositionLimits(maximumReferenceAttributes: -1))
    }

    @MainActor
    func testCanceledConstructionAndStorageStayDistinctFromValidationErrors() async throws {
        let entry = DocumentEntry(id: "root", document: sampleDocument())
        let composition = try DocumentComposition(rootID: "root", entries: [entry])
        let data = try DocumentCompositionCodec.encode(composition)
        let construction = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try DocumentComposition(rootID: "root", entries: [entry])
        }
        construction.cancel()
        assertCancellation(await construction.result)
        let decoding = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try DocumentCompositionCodec.decode(data)
        }
        decoding.cancel()
        assertCancellation(await decoding.result)
        let encoding = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try DocumentCompositionCodec.encode(composition)
        }
        encoding.cancel()
        assertCancellation(await encoding.result)
    }

    private func assertFailure(_ expected: DocumentCompositionError, _ body: () throws -> DocumentComposition) {
        XCTAssertThrowsError(try body()) { XCTAssertEqual($0 as? DocumentCompositionError, expected) }
    }

    private func assertCancellation<Value>(_ result: Result<Value, any Error>) {
        guard case .failure(let error) = result else { return XCTFail("Expected cancellation") }
        XCTAssertTrue(error is CancellationError)
    }
}

internal func sampleDocument() -> Document {
    Document(
        version: "future.beta",
        axis: Axis(rawValue: "weather"),
        title: "'literal quotes' 🌙",
        metadata: ["author": "Leif", "note": "Unicode café", "location": "https://example.invalid/never-loaded"],
        preamble: "# General Markdown\nThis stays in memory.",
        planes: [
            Plane(
                z: -2.5,
                label: "'label'",
                x: 3.5,
                y: -1.25,
                attributes: ["asset": "🦉", "binding": "A"],
                body: "## STORED_ONCE_marker\n```3md\n@plane z=99\n```\n[Local](file:///not-opened.3md)"
            ),
            Plane(z: 7, body: "Another plane"),
        ]
    )
}

internal func plainDocument(_ body: String = "General Markdown") -> Document {
    Document(version: "0.1", axis: .layer, planes: [Plane(z: 0, body: body)])
}
