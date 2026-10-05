import Foundation
import XCTest

@testable import ThreeMD

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class DocumentCompositionCodecTests: XCTestCase {
    func testCheckedInGrovePreservesItsSingleCanopyDefinitionAndBindingAcrossFormats() throws {
        let readable = try DocumentStorageTests.extensionFixture("shared-grove.3md")
        let composition = try DocumentCompositionCodec.decode(readable)
        XCTAssertEqual(composition.rootID, "grove")
        XCTAssertEqual(composition.entries.map(\.id), ["canopy", "grove"])
        let canopy = try DocumentStorageCodec.decode(DocumentStorageTests.extensionFixture("canopy.3md"))
        XCTAssertEqual(composition.entry(id: "canopy")?.document, canopy)
        XCTAssertEqual(composition.rootEntry.document.planes.first?.body, "A.A\n.A.")
        XCTAssertEqual(composition.rootEntry.references, [.init(targetID: "canopy", attributes: ["binding": "A"])])
        let profileSource = try XCTUnwrap(String(data: readable, encoding: .utf8))
        XCTAssertEqual(profileSource.components(separatedBy: "Reusable canopy").count - 1, 1)
        XCTAssertEqual(try DocumentCompositionCodec.encode(composition), readable)
        var binaryFiles = ["shared-grove.3mdb"]
        #if canImport(Compression)
        binaryFiles.append("shared-grove.lzfse.3mdb")
        #endif
        for name in binaryFiles {
            let binary = try DocumentStorageTests.extensionFixture(name)
            XCTAssertEqual(try DocumentCompositionCodec.decode(binary), composition, name)
            let document = try DocumentStorageCodec.decode(binary)
            XCTAssertEqual(try DocumentCompositionCodec.decode(document), composition, name)
        }
    }

    func testCanonicalProfileStoresSharedDefinitionOnceAndIsOrderIndependent() throws {
        let root = DocumentEntry(
            id: "root",
            document: plainDocument("Root"),
            references: [.init(targetID: "shared", attributes: ["z": "1", "a": "2"]), .init(targetID: "shared")]
        )
        let shared = DocumentEntry(id: "shared", document: sampleDocument())
        let first = try DocumentComposition(rootID: "root", entries: [root, shared])
        let second = try DocumentComposition(rootID: "root", entries: [shared, root])
        let data = try DocumentCompositionCodec.encode(first)
        XCTAssertEqual(data, try DocumentCompositionCodec.encode(second))
        let source = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(source.components(separatedBy: "STORED_ONCE_marker").count - 1, 1)
        let profile = try DocumentCompositionCodec.document(for: first)
        XCTAssertEqual(profile.planes.count, 1)
        XCTAssertTrue(DocumentCompositionCodec.isComposition(profile))
        XCTAssertEqual(try Parser().parse(source), profile)
        XCTAssertEqual(try DocumentCompositionCodec.decode(data), first)
    }

    func testProfileUsesGenericPortableBinaryEnvelopeWithoutAnotherFormat() throws {
        let composition = try DocumentComposition(
            rootID: "root",
            entries: [DocumentEntry(id: "root", document: sampleDocument())]
        )
        let profile = try DocumentCompositionCodec.document(for: composition)
        let data = try DocumentStorageCodec.encode(profile, format: .binary(compression: .none))
        XCTAssertTrue(DocumentStorageCodec.isBinary(data))
        XCTAssertEqual(try DocumentCompositionCodec.decode(data), composition)
        XCTAssertEqual(try DocumentCompositionCodec.decode(DocumentStorageCodec.decode(data)), composition)
    }

    func testReaderRejectsUnknownManifestEntryAndReferenceKeys() throws {
        let source = String(decoding: try DocumentStorageCodec.encode(plainDocument()), as: UTF8.self)
        let invalidManifests: [[String: Any]] = [
            ["schema": "3md-composition-1", "rootID": "root", "entries": [], "external": "file:///root.3md"],
            manifest(source: source, entryExtra: ["path": "root.3md"]),
            manifest(
                source: source,
                references: [["targetID": "root", "attributes": [:], "url": "https://example.invalid"]]
            ),
        ]
        for value in invalidManifests {
            assertInvalid(try profile(value))
        }
    }

    func testReaderRejectsDuplicateJSONKeysIncludingEscapedSpelling() throws {
        let source = """
            {"schema":"3md-composition-1","rootID":"a","\\u0072ootID":"b","entries":[]}
            """
        assertInvalid(profile(json: source), expected: .invalidProfile("duplicate JSON object key"))
        let nested = """
            {"schema":"3md-composition-1","rootID":"root","entries":[{"id":"root","id":"other","source":"x","references":[]}]}
            """
        assertInvalid(profile(json: nested), expected: .invalidProfile("duplicate JSON object key"))
    }

    func testReaderRejectsDuplicateDefinitionIDsAndUnusedMissingReferences() throws {
        let source = String(decoding: try DocumentStorageCodec.encode(plainDocument()), as: UTF8.self)
        let item: [String: Any] = ["id": "root", "source": source, "references": []]
        assertInvalid(
            try profile(["schema": "3md-composition-1", "rootID": "root", "entries": [item, item]]),
            expected: .duplicateID("root")
        )
        let unused: [String: Any] = [
            "id": "unused", "source": source, "references": [["targetID": "missing", "attributes": [:]]],
        ]
        assertInvalid(
            try profile(["schema": "3md-composition-1", "rootID": "root", "entries": [item, unused]]),
            expected: .missingTarget(from: "unused", target: "missing")
        )
    }

    func testReaderRejectsInvalidUnusedDefinitionsAndDoesNotLoadSourcePaths() throws {
        let source = String(decoding: try DocumentStorageCodec.encode(plainDocument()), as: UTF8.self)
        let root: [String: Any] = ["id": "root", "source": source, "references": []]
        for unsupportedSource in [
            "file:///tmp/document.3md", "https://example.invalid/3md", "---\naxis: time\n---\nbody",
        ] {
            let unused: [String: Any] = ["id": "unused", "source": unsupportedSource, "references": []]
            XCTAssertThrowsError(
                try DocumentCompositionCodec.decode(
                    profile(["schema": "3md-composition-1", "rootID": "root", "entries": [root, unused]])
                )
            ) { XCTAssertTrue($0 is DocumentStorageError) }
        }
    }

    func testReaderRequiresExactEnvelopeAndVersionedManifest() throws {
        let composition = try DocumentComposition(
            rootID: "root",
            entries: [DocumentEntry(id: "root", document: plainDocument())]
        )
        let valid = try DocumentCompositionCodec.document(for: composition)
        XCTAssertFalse(DocumentCompositionCodec.isComposition(plainDocument()))
        assertInvalid(
            Document(version: valid.version, axis: .time, metadata: valid.metadata, planes: valid.planes),
            expected: .invalidProfile("unexpected composition envelope")
        )
        assertInvalid(
            Document(
                version: valid.version,
                axis: valid.axis,
                title: "unexpected",
                metadata: valid.metadata,
                planes: valid.planes
            ),
            expected: .invalidProfile("unexpected composition envelope")
        )
        assertInvalid(
            profile(json: "{\"schema\":\"3md-composition-2\",\"rootID\":\"root\",\"entries\":[]}"),
            expected: .unsupportedProfile("3md-composition-2")
        )
    }

    func testProfileAndDefinitionBytePoliciesBoundBothReaderAndWriter() throws {
        let composition = try DocumentComposition(
            rootID: "root",
            entries: [DocumentEntry(id: "root", document: plainDocument())]
        )
        let encoded = try DocumentCompositionCodec.encode(composition)
        XCTAssertThrowsError(
            try DocumentCompositionCodec.decode(encoded, limits: .init(maximumProfileBytes: encoded.count - 1))
        ) {
            XCTAssertEqual($0 as? DocumentCompositionError, .profileBytesExceeded)
        }
        XCTAssertThrowsError(
            try DocumentCompositionCodec.encode(composition, limits: .init(maximumProfileBytes: encoded.count - 1))
        ) {
            // The JSON fits this bound; the surrounding 3md header and code fence do not.
            XCTAssertEqual($0 as? DocumentCompositionError, .profileBytesExceeded)
        }
        XCTAssertThrowsError(
            try DocumentCompositionCodec.decode(
                DocumentCompositionCodec.document(for: composition),
                limits: .init(maximumProfileBytes: encoded.count - 1)
            )
        ) {
            XCTAssertEqual($0 as? DocumentCompositionError, .profileBytesExceeded)
        }
        XCTAssertThrowsError(try DocumentCompositionCodec.encode(composition, limits: .init(maximumProfileBytes: 16))) {
            XCTAssertEqual($0 as? DocumentCompositionError, .profileBytesExceeded)
        }
        XCTAssertThrowsError(try DocumentCompositionCodec.decode(encoded, limits: .init(maximumDefinitionBytes: 8))) {
            XCTAssertEqual($0 as? DocumentCompositionError, .definitionBytesExceeded)
        }
    }

    func testReferenceAttributesPreserveControlsQuotesAndUnicodeWithoutBreakingFences() throws {
        let root = DocumentEntry(
            id: "root",
            document: plainDocument(),
            references: [.init(targetID: "leaf", attributes: ["key\n\"🌙": "\u{0000}\t\\\"\n```json\n@plane z=2"])]
        )
        let composition = try DocumentComposition(
            rootID: "root",
            entries: [root, DocumentEntry(id: "leaf", document: plainDocument())]
        )
        XCTAssertEqual(try DocumentCompositionCodec.decode(DocumentCompositionCodec.encode(composition)), composition)
    }

    func testJSONAllocationPreflightRejectsExcessiveArraysNestingAndTrailingBytes() throws {
        let arrays = "[" + Array(repeating: "{}", count: 10).joined(separator: ",") + "]"
        XCTAssertThrowsError(
            try DocumentCompositionCodec.decode(
                profile(json: arrays),
                limits: .init(maximumDefinitions: 1, maximumReferences: 0)
            )
        )
        assertInvalid(profile(json: String(repeating: "[", count: 14) + "null" + String(repeating: "]", count: 14)))
        assertInvalid(profile(json: "{\"schema\":\"3md-composition-1\",\"rootID\":\"root\",\"entries\":[]} true"))
        assertInvalid(
            profile(json: "{\"schema\":\"3md-composition-1\",\"rootID\":\"root\",\"entries\":[],\"number\":1}")
        )
    }

    private func assertInvalid(_ profile: Document, expected: DocumentCompositionError? = nil) {
        XCTAssertThrowsError(try DocumentCompositionCodec.decode(profile)) { error in
            if let expected {
                XCTAssertEqual(error as? DocumentCompositionError, expected)
            } else {
                XCTAssertTrue(error is DocumentCompositionError, "Received \(error)")
            }
        }
    }

    private func manifest(
        source: String,
        entryExtra: [String: Any] = [:],
        references: [[String: Any]] = []
    ) -> [String: Any] {
        var entry: [String: Any] = ["id": "root", "source": source, "references": references]
        entry.merge(entryExtra) { _, new in new }
        return ["schema": "3md-composition-1", "rootID": "root", "entries": [entry]]
    }

    private func profile(_ manifest: [String: Any]) throws -> Document {
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return profile(json: String(decoding: data, as: UTF8.self))
    }

    private func profile(json: String) -> Document {
        Document(
            version: "0.1",
            axis: .layer,
            metadata: ["profile": "3md-composition-1"],
            planes: [Plane(z: 0, label: "Composition", body: "```json\n\(json)\n```")]
        )
    }
}
