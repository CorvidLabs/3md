import Foundation
import XCTest

@testable import ThreeMD

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class DocumentIdentityTests: XCTestCase {
    func testAdoptionPreservesNamespaceMetadataAndDeterministicallySkipsExistingIDs() throws {
        let document = Document(
            version: "1.0",
            axis: .time,
            title: "Plan",
            metadata: ["id": "opaque"],
            planes: [
                Plane(z: 3, attributes: ["id": "legacy", "custom": "value"], body: "One"),
                Plane(z: 4, attributes: ["3md-id": "plane-1"], body: "Two"),
                Plane(z: 5, body: "Three"),
            ]
        )
        let adopted = try DocumentIdentity.adopt(document)
        XCTAssertEqual(adopted.planes.map(\.stableID), ["plane-2", "plane-1", "plane-3"])
        XCTAssertEqual(adopted.planes[0].attributes["id"], "legacy")
        XCTAssertEqual(adopted.planes[0].attributes["custom"], "value")
        XCTAssertEqual(adopted.metadata, document.metadata)
        XCTAssertEqual(try DocumentIdentity.adopt(adopted), adopted)
    }

    func testExplicitIdentitiesRoundTripThroughTextAndBothBinaryBackends() throws {
        let document = Document(
            version: "0.1",
            axis: .layer,
            planes: [
                Plane(z: 0, attributes: ["3md-id": "Stable_A", "id": "still-opaque"], body: "[[z=1]]"),
                Plane(z: 1, attributes: ["3md-id": "Stable_B"], body: "Other"),
            ]
        )
        var formats: [DocumentStorageFormat] = [.text, .binary(compression: .none)]
        #if canImport(Compression)
        formats.append(.binary(compression: .lzfse))
        #endif
        for format in formats {
            XCTAssertEqual(
                try DocumentStorageCodec.decode(DocumentStorageCodec.encode(document, format: format)),
                document
            )
        }
        XCTAssertEqual(try Parser().parse(Serializer().render(document)), document)
        XCTAssertEqual(document.planes[0].anchorID, "plane-z-0")
        XCTAssertEqual(document.links().map(\.targetZ), [1])
    }

    func testUnsafeAndEmptyExistingIDsAreRejectedWithExactPaths() throws {
        for id in ["", "../file", "a.b", " bad", "é", "https://server", String(repeating: "a", count: 65)] {
            let document = Document(
                version: "0.1",
                axis: .layer,
                planes: [Plane(z: 0, attributes: ["3md-id": id], body: "Body")]
            )
            XCTAssertThrowsError(try DocumentIdentity.adopt(document)) { error in
                let diagnostic = (error as? DocumentEditError)?.diagnostic
                XCTAssertEqual(diagnostic?.code, .invalidIdentity)
                XCTAssertEqual(diagnostic?.path, "planes[0].attributes[3md-id]")
                XCTAssertNil(diagnostic?.sourceLine)
            }
        }
    }

    func testDuplicatesAreRejectedRatherThanSilentlyRegenerated() throws {
        let document = Document(
            version: "0.1",
            axis: .layer,
            planes: [
                Plane(z: 0, attributes: ["3md-id": "same"], body: "One"),
                Plane(z: 1, attributes: ["3md-id": "same"], body: "Two"),
            ]
        )
        XCTAssertThrowsError(try DocumentIdentity.adopt(document)) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .duplicateIdentity)
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.path, "planes[1].attributes[3md-id]")
        }
        XCTAssertEqual(try Parser().parse(Serializer().render(document)), document)
    }

    func testRepeatedTargetsGainIndependentOwnerScopedReferenceIDs() throws {
        let leaf = DocumentEntry(id: "leaf", document: plain("Leaf"))
        let root = DocumentEntry(
            id: "root",
            document: plain("Root"),
            references: [
                .init(targetID: "leaf", attributes: ["id": "old"]),
                .init(targetID: "leaf", attributes: ["3md-id": "reference-1"]),
            ]
        )
        let other = DocumentEntry(
            id: "other",
            document: plain("Other"),
            references: [
                .init(targetID: "leaf", attributes: ["3md-id": "reference-1"])
            ]
        )
        let adopted = try DocumentIdentity.adopt(DocumentComposition(rootID: "root", entries: [root, leaf, other]))
        XCTAssertEqual(adopted.rootEntry.references.map(\.stableID), ["reference-2", "reference-1"])
        XCTAssertEqual(adopted.rootEntry.references.first?.attributes["id"], "old")
        XCTAssertEqual(adopted.entry(id: "other")?.references.first?.stableID, "reference-1")
        XCTAssertEqual(try DocumentCompositionCodec.decode(DocumentCompositionCodec.encode(adopted)), adopted)
        XCTAssertEqual(try DocumentIdentity.adopt(adopted), adopted)
    }

    func testDuplicateReferenceIdentityFailsWithinOwnerOnly() throws {
        let leaf = DocumentEntry(id: "leaf", document: plain("Leaf"))
        let root = DocumentEntry(
            id: "root",
            document: plain("Root"),
            references: [
                .init(targetID: "leaf", attributes: ["3md-id": "same"]),
                .init(targetID: "leaf", attributes: ["3md-id": "same"]),
            ]
        )
        let composition = try DocumentComposition(rootID: "root", entries: [root, leaf])
        XCTAssertThrowsError(try DocumentIdentity.adopt(composition)) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .duplicateIdentity)
            XCTAssertEqual(
                (error as? DocumentEditError)?.diagnostic.path,
                "entries[1].references[1].attributes[3md-id]"
            )
        }
    }

    func testIdentityAdoptionRespectsDocumentAndReferenceAttributeBudgets() throws {
        let document = plain("Body")
        let sourceBytes = try DocumentStorageCodec.encode(document).count
        let tiny = try DocumentDecodeLimits(maximumDecodedBytes: sourceBytes)
        XCTAssertThrowsError(try DocumentIdentity.adopt(document, documentLimits: tiny))
        let root = DocumentEntry(id: "root", document: document, references: [.init(targetID: "leaf")])
        let composition = try DocumentComposition(
            rootID: "root",
            entries: [root, .init(id: "leaf", document: document)]
        )
        XCTAssertThrowsError(try DocumentIdentity.adopt(composition, limits: .init(maximumReferenceAttributes: 0)))
    }

    func testCancelledIdentityAdoptionReturnsCancellation() async throws {
        let document = plain("Body")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DocumentIdentity.adopt(document)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch {
            XCTFail("\(error)")
        }
    }

    private func plain(_ body: String) -> Document {
        .init(version: "0.1", axis: .layer, planes: [Plane(z: 0, body: body)])
    }
}
