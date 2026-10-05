import Foundation
import XCTest

@testable import ThreeMD

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class DocumentFileCompositionTests: XCTestCase {
    func testSimpleRepeatedFilesProduceOneDefinitionAndPreserveOrdinaryDocumentFields() throws {
        let root = document(
            title: "Parent",
            body: "12\nMarkdown stays Markdown",
            axis: .frame,
            metadata: ["3md-files": #"{"2":"./models/tree.3md","1":"models/tree.3md"}"#, "custom": "keep"],
            identity: "existing-plane"
        )
        let child = document(title: "Tree", body: "A tree", axis: .time)
        let result = try DocumentFileComposition.resolve(
            rootPath: "./root.3md",
            sources: [try source("root.3md", root), try source("models/tree.3md", child)]
        )
        XCTAssertEqual(result.rootPath, "root.3md")
        XCTAssertEqual(result.resolvedPaths, ["models/tree.3md", "root.3md"])
        XCTAssertEqual(result.fileRootIDs, ["models/tree.3md": "file-000000", "root.3md": "file-000001"])
        XCTAssertEqual(result.composition.entries.count, 2)
        let bundled = result.composition.rootEntry
        XCTAssertEqual(bundled.document.version, root.version)
        XCTAssertEqual(bundled.document.axis, root.axis)
        XCTAssertEqual(bundled.document.title, root.title)
        XCTAssertEqual(bundled.document.preamble, root.preamble)
        XCTAssertEqual(bundled.document.planes, root.planes)
        XCTAssertEqual(bundled.document.metadata, ["custom": "keep"])
        XCTAssertEqual(bundled.references.map(\.targetID), ["file-000000", "file-000000"])
        XCTAssertEqual(bundled.references.map { $0.attributes["glyph"] }, ["1", "2"])
        XCTAssertTrue(bundled.references.allSatisfy { $0.attributes["source-file"] == "models/tree.3md" })
        XCTAssertTrue(bundled.references.allSatisfy { $0.stableID == nil })
        XCTAssertEqual(result.composition.entry(id: "file-000000")?.document, child)
    }

    func testNestedParentPathsAndRefreshedChildrenRetainDeterministicIDs() throws {
        let root = try source("root.3md", document(metadata: ["3md-files": #"{"A":"models/branch.3md"}"#]))
        let branch = try source(
            "models/branch.3md",
            document(metadata: ["3md-files": #"{"B":"../leaves/leaf.3md"}"#])
        )
        let leaf = try source("leaves/leaf.3md", document(body: "Original", axis: Axis(rawValue: "custom-axis")))
        let original = try DocumentFileComposition.resolve(rootPath: root.path, sources: [root, branch, leaf])
        let refreshed = try DocumentFileComposition.resolve(
            rootPath: root.path,
            sources: [
                try source(leaf.path, document(body: "Changed", axis: Axis(rawValue: "custom-axis"))), branch, root,
            ]
        )
        XCTAssertEqual(original.fileRootIDs, refreshed.fileRootIDs)
        XCTAssertNotEqual(original.composition, refreshed.composition)
        let leafID = try XCTUnwrap(refreshed.fileRootIDs[leaf.path])
        XCTAssertEqual(refreshed.composition.entry(id: leafID)?.document.planes.first?.body, "Changed")
        XCTAssertEqual(refreshed.composition.entry(id: leafID)?.document.axis, Axis(rawValue: "custom-axis"))
    }

    func testTextAndUncompressedBinaryChildrenBundleIdenticallyWithoutExtensionRestrictions() throws {
        let root = try source("root.3md", document(metadata: ["3md-files": #"{"1":"child.whatever"}"#]))
        let child = document(body: "Portable child")
        let text = try DocumentFileComposition.resolve(
            rootPath: root.path,
            sources: [root, try source("child.whatever", child)]
        )
        let binary = try DocumentFileComposition.resolve(
            rootPath: root.path,
            sources: [root, try source("child.whatever", child, binary: true)]
        )
        XCTAssertEqual(text, binary)
    }

    func testExistingBundleRetainsUnusedEntriesOpaqueAttributesAndIdentitiesAndScansEveryLedger() throws {
        let leaf = DocumentEntry(id: "leaf", document: document(body: "Leaf", identity: "kept-plane"))
        let reference = DocumentReference(
            targetID: leaf.id,
            attributes: ["3md-id": "kept-ref", "3md-ref-id": "opaque", "location": "opaque://kept"]
        )
        let bundle = try DocumentComposition(
            rootID: "root",
            entries: [
                leaf,
                .init(
                    id: "root",
                    document: document(metadata: ["3md-files": #"{"Z":"../extra.3md"}"#]),
                    references: [reference]
                ),
                .init(id: "unused", document: document(metadata: ["3md-files": #"{"1":"other.3md"}"#])),
            ]
        )
        let result = try DocumentFileComposition.resolve(
            rootPath: "root.3md",
            sources: [
                try source("root.3md", document(metadata: ["3md-files": #"{"B":"models/library.3mdb"}"#])),
                .init(
                    path: "models/library.3mdb",
                    data: try DocumentStorageCodec.encode(
                        DocumentCompositionCodec.document(for: bundle),
                        format: .binary(compression: .none)
                    )
                ),
                try source("extra.3md", document(body: "Extra")),
                try source("models/other.3md", document(body: "Other")),
            ]
        )
        XCTAssertEqual(result.resolvedPaths, ["extra.3md", "models/library.3mdb", "models/other.3md", "root.3md"])
        XCTAssertEqual(result.composition.entries.count, 6)
        let importedRoot = try XCTUnwrap(result.composition.entry(id: result.fileRootIDs["models/library.3mdb"] ?? ""))
        XCTAssertEqual(importedRoot.references.first?.attributes, reference.attributes)
        XCTAssertEqual(importedRoot.references.first?.stableID, "kept-ref")
        XCTAssertEqual(importedRoot.references.last?.attributes, ["glyph": "Z", "source-file": "extra.3md"])
        let importedLeaf = try XCTUnwrap(importedRoot.references.first?.targetID)
        XCTAssertEqual(result.composition.entry(id: importedLeaf)?.document, leaf.document)
        XCTAssertTrue(result.composition.entries.contains { $0.references.contains { $0.attributes["glyph"] == "1" } })
        XCTAssertTrue(result.composition.entries.allSatisfy { $0.document.metadata["3md-files"] == nil })
    }

    func testBundledTextAndBinaryReopenWithoutSupplyingAnySourceFiles() throws {
        let result = try simpleResult()
        let text = try DocumentCompositionCodec.encode(result.composition)
        XCTAssertEqual(try DocumentCompositionCodec.decode(text), result.composition)
        let binary = try DocumentStorageCodec.encode(
            DocumentCompositionCodec.document(for: result.composition),
            format: .binary(compression: .none)
        )
        XCTAssertEqual(try DocumentCompositionCodec.decode(binary), result.composition)
    }

    func testDuplicateBasenamesAndUnicodeScalarOrderingRemainDistinct() throws {
        let privateUse = "\u{E000}.3md"
        let supplementary = "\u{10000}.3md"
        let ledger = "{\"1\":\"a/tree.3md\",\"2\":\"b/tree.3md\",\"3\":\"\(privateUse)\",\"4\":\"\(supplementary)\"}"
        let root = try source("root.3md", document(metadata: ["3md-files": ledger]))
        let children = try ["a/tree.3md", "b/tree.3md", privateUse, supplementary].map {
            try source($0, document(body: $0))
        }
        let result = try DocumentFileComposition.resolve(
            rootPath: root.path,
            sources: Array(children.reversed()) + [root]
        )
        XCTAssertEqual(result.resolvedPaths, ["a/tree.3md", "b/tree.3md", "root.3md", privateUse, supplementary])
        XCTAssertNotEqual(result.fileRootIDs["a/tree.3md"], result.fileRootIDs["b/tree.3md"])
    }

    func testNestedProfileUsesProfileRecordPolicyWhileOrdinaryAndChildDocumentsKeepTheirOwnPolicy() throws {
        let childPolicy = try DocumentDecodeLimits(maximumRecordBytes: 512)
        let bundle = try DocumentComposition(
            rootID: "root",
            entries: (0..<4).map { index in
                DocumentEntry(
                    id: index == 0 ? "root" : "entry-\(index)",
                    document: document(body: String(repeating: "a", count: 150))
                )
            },
            documentLimits: childPolicy
        )
        let bundleDocument = try DocumentCompositionCodec.document(for: bundle, documentLimits: childPolicy)
        XCTAssertGreaterThan(try XCTUnwrap(bundleDocument.planes.first).body.utf8.count, childPolicy.maximumRecordBytes)
        let parent = try source("root.3md", document(metadata: ["3md-files": #"{"1":"bundle.3md"}"#]))
        let result = try DocumentFileComposition.resolve(
            rootPath: parent.path,
            sources: [
                parent,
                .init(
                    path: "bundle.3md",
                    data: try DocumentCompositionCodec.encode(bundle, documentLimits: childPolicy)
                ),
            ],
            documentLimits: childPolicy
        )
        XCTAssertEqual(result.composition.entries.count, 5)
        let ordinary = try source("ordinary.3md", document(body: String(repeating: "a", count: 513)))
        XCTAssertThrowsError(
            try DocumentFileComposition.resolve(
                rootPath: ordinary.path,
                sources: [ordinary],
                documentLimits: childPolicy
            )
        ) { XCTAssertEqual($0 as? DocumentStorageError, .oversizedRecord) }
    }

    func testCachedDepthFailurePrecedesLaterMissingFile() throws {
        let sources = try [
            source("root", document(metadata: ["3md-files": #"{"1":"short","2":"long"}"#])),
            source("short", document(metadata: ["3md-files": #"{"1":"leaf"}"#])),
            source("long", document(metadata: ["3md-files": #"{"1":"short","2":"missing"}"#])),
            source("leaf", document()),
        ]
        XCTAssertThrowsError(
            try DocumentFileComposition.resolve(
                rootPath: "root",
                sources: sources,
                limits: .init(maximumDepth: 3)
            )
        ) { error in
            XCTAssertEqual(error as? DocumentCompositionError, .depthExceeded)
        }
    }

    func testOnlyReachableSourcesDecode() throws {
        let root = try source("root.3md", document())
        let result = try DocumentFileComposition.resolve(
            rootPath: root.path,
            sources: [root, .init(path: "not-read.3md", data: Data([255, 0, 255]))]
        )
        XCTAssertEqual(result.resolvedPaths, [root.path])
        XCTAssertEqual(result.composition.entries.count, 1)
    }

    func testMissingRootAndLinkedChildReportNormalizedMissingPaths() throws {
        assertFileFailure(.missingFile("root.3md")) {
            try DocumentFileComposition.resolve(rootPath: "./root.3md", sources: [])
        }
        let root = try source("root.3md", document(metadata: ["3md-files": #"{"1":"models/../missing.3md"}"#]))
        assertFileFailure(.missingFile("missing.3md")) {
            try DocumentFileComposition.resolve(rootPath: root.path, sources: [root])
        }
    }

    func testPathsNormalizeNFCAndParentsWithoutPercentDecoding() throws {
        XCTAssertEqual(
            try DocumentFileComposition.resolvePath("../e\u{301}.3md", relativeTo: "models/parent.3md"),
            "é.3md"
        )
        XCTAssertEqual(
            try DocumentFileComposition.resolvePath("./leaf.3md", relativeTo: "models/../root.3md"),
            "leaf.3md"
        )
        XCTAssertEqual(try DocumentFileComposition.resolvePath("%2e%2e/model", relativeTo: "root.3md"), "%2e%2e/model")
        for path in [
            "", "/absolute", "a\\b", "https:resource", "a//b", "trailing/", "../outside", "a\n", "a\u{7F}", ".", "x/..",
        ] {
            XCTAssertThrowsError(try DocumentFileComposition.resolvePath(path, relativeTo: "root.3md")) {
                XCTAssertEqual($0 as? DocumentFileCompositionError, .invalidPath(path))
            }
        }
        XCTAssertThrowsError(try DocumentFileComposition.resolvePath("leaf", relativeTo: "/absolute"))
    }

    func testDuplicateNormalizedAndCanonicallyEquivalentSourcesFailBeforeDecode() throws {
        for paths in [["root.3md", "models/../root.3md"], ["é.3md", "e\u{301}.3md"]] {
            XCTAssertThrowsError(
                try DocumentFileComposition.resolve(
                    rootPath: paths[0],
                    sources: paths.map { .init(path: $0, data: Data()) }
                )
            ) { error in
                guard case .duplicatePath = error as? DocumentFileCompositionError else {
                    return XCTFail("Expected duplicate normalized paths, received \(error)")
                }
            }
        }
    }

    func testLedgerRejectsDuplicateEscapedKeysAndMalformedValuesAndGlyphs() throws {
        for ledger in [
            #"{"1":"x","\u0031":"y"}"#, #"{"1":false}"#, #"{"1":{}}"#, #"{"1":"x",}"#, #"[]"#, #"{"1":"\q"}"#,
            #"{"1":"x"} trailing"#,
        ] {
            XCTAssertThrowsError(try DocumentFileComposition.ledger(in: document(metadata: ["3md-files": ledger]))) {
                guard case .invalidLedger = $0 as? DocumentFileCompositionError else {
                    return XCTFail("Expected malformed ledger, received \($0)")
                }
            }
        }
        for glyph in ["", " ", "ab", "é", "\n"] {
            let data = try JSONEncoder().encode([glyph: "x"])
            let ledger = String(decoding: data, as: UTF8.self)
            assertFileFailure(.invalidGlyph(glyph)) {
                try DocumentFileComposition.ledger(in: document(metadata: ["3md-files": ledger]))
            }
        }
        XCTAssertEqual(try DocumentFileComposition.ledger(in: document(metadata: ["3md-files": " {} \n"])), [])
        XCTAssertEqual(try DocumentFileComposition.ledger(in: document()), [])
    }

    func testFileCyclesIncludeUnusedEmbeddedEntryLedgers() throws {
        let root = try source("root.3md", document(metadata: ["3md-files": #"{"1":"./root.3md"}"#]))
        assertCompositionFailure(.cycle("root.3md")) {
            try DocumentFileComposition.resolve(rootPath: root.path, sources: [root])
        }
        let bundle = try DocumentComposition(
            rootID: "root",
            entries: [
                .init(id: "root", document: document()),
                .init(id: "unused", document: document(metadata: ["3md-files": #"{"1":"root.3md"}"#])),
            ]
        )
        let parent = try source("root.3md", document(metadata: ["3md-files": #"{"A":"bundle.3md"}"#]))
        assertCompositionFailure(.cycle("root.3md")) {
            try DocumentFileComposition.resolve(
                rootPath: parent.path,
                sources: [parent, .init(path: "bundle.3md", data: try DocumentCompositionCodec.encode(bundle))]
            )
        }
    }

    func testLoweredDefinitionDepthReferenceTraversalAndAttributePoliciesApplyToCompleteGraph() throws {
        let root = try source("root.3md", document(metadata: ["3md-files": #"{"1":"leaf.3md","2":"leaf.3md"}"#]))
        let leaf = try source("leaf.3md", document())
        assertCompositionFailure(.tooManyReferences) {
            try DocumentFileComposition.resolve(
                rootPath: root.path,
                sources: [root, leaf],
                limits: .init(maximumReferences: 1)
            )
        }
        assertCompositionFailure(.traversalOccurrencesExceeded) {
            try DocumentFileComposition.resolve(
                rootPath: root.path,
                sources: [root, leaf],
                limits: .init(maximumTraversalOccurrences: 2)
            )
        }
        assertCompositionFailure(.depthExceeded) {
            try DocumentFileComposition.resolve(
                rootPath: root.path,
                sources: [root, leaf],
                limits: .init(maximumDepth: 1)
            )
        }
        assertCompositionFailure(.referenceAttributesExceeded) {
            try DocumentFileComposition.resolve(
                rootPath: root.path,
                sources: [root, leaf],
                limits: .init(maximumReferenceAttributes: 1)
            )
        }
        let bundle = try DocumentComposition(
            rootID: "root",
            entries: [.init(id: "root", document: document()), .init(id: "unused", document: document())]
        )
        let parent = try source("root.3md", document(metadata: ["3md-files": #"{"1":"bundle.3md"}"#]))
        assertCompositionFailure(.tooManyDefinitions) {
            try DocumentFileComposition.resolve(
                rootPath: parent.path,
                sources: [parent, .init(path: "bundle.3md", data: try DocumentCompositionCodec.encode(bundle))],
                limits: .init(maximumDefinitions: 2)
            )
        }
    }

    func testReachableEncodedByteAndSuppliedCountAndAggregatePathLimitsFailBeforeIndexingOrPublishing() throws {
        let root = try source("root.3md", document(metadata: ["3md-files": #"{"1":"leaf.3md"}"#]))
        let leaf = try source("leaf.3md", document())
        assertFileFailure(.inputLimit) {
            try DocumentFileComposition.resolve(
                rootPath: root.path,
                sources: [root, leaf],
                limits: .init(maximumDefinitions: 1)
            )
        }
        assertFileFailure(.inputLimit) {
            try DocumentFileComposition.resolve(
                rootPath: root.path,
                sources: [root, leaf],
                limits: .init(maximumProfileBytes: root.data.count + leaf.data.count - 1)
            )
        }
        let longPath = String(repeating: "a", count: 600)
        assertFileFailure(.inputLimit) {
            try DocumentFileComposition.resolve(
                rootPath: longPath,
                sources: [.init(path: longPath, data: Data())],
                limits: .init(maximumProfileBytes: 1_000)
            )
        }
    }

    func testStandalonePathAndLedgerRecordCapsUseInputLimit() throws {
        let oversized = String(repeating: "a", count: DocumentDecodeLimits.standard.maximumRecordBytes + 1)
        assertFileFailure(.inputLimit) { try DocumentFileComposition.resolvePath(oversized, relativeTo: "root.3md") }
        assertFileFailure(.inputLimit) {
            try DocumentFileComposition.ledger(in: document(metadata: ["3md-files": oversized]))
        }
    }

    func testChildStorageFailuresKeepOriginalErrorType() throws {
        let root = try source("root.3md", document(metadata: ["3md-files": #"{"1":"leaf.3md"}"#]))
        XCTAssertThrowsError(
            try DocumentFileComposition.resolve(
                rootPath: root.path,
                sources: [root, .init(path: "leaf.3md", data: Data([255]))]
            )
        ) { XCTAssertEqual($0 as? DocumentStorageError, .invalidUTF8) }
    }

    @MainActor
    func testCancellationStaysDistinctAndNeverReturnsPartialComposition() async throws {
        let sources = [try source("root.3md", document())]
        let task = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try DocumentFileComposition.resolve(rootPath: "root.3md", sources: sources)
        }
        task.cancel()
        switch await task.result {
        case .success: XCTFail("Canceled file resolution returned a composition")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
    }

    @MainActor
    func testCancelledPathResolutionPrecedesOversizedInput() async {
        let oversized = String(repeating: "a", count: DocumentDecodeLimits.standard.maximumRecordBytes + 1)
        let task = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try DocumentFileComposition.resolvePath(oversized, relativeTo: "root.3md")
        }
        task.cancel()
        switch await task.result {
        case .success: XCTFail("Canceled path resolution returned a path")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
    }

    private func document(
        title: String = "Document",
        body: String = "Body",
        axis: Axis = .space,
        metadata: [String: String] = [:],
        identity: String? = nil
    ) -> Document {
        Document(
            version: "0.1",
            axis: axis,
            title: title,
            metadata: metadata,
            preamble: "Preserved preamble",
            planes: [
                Plane(z: 3, label: "Layer", x: -2, y: 4, attributes: identity.map { ["3md-id": $0] } ?? [:], body: body)
            ]
        )
    }

    private func source(_ path: String, _ document: Document, binary: Bool = false) throws -> DocumentFileSource {
        .init(
            path: path,
            data: try DocumentStorageCodec.encode(document, format: binary ? .binary(compression: .none) : .text)
        )
    }

    private func simpleResult() throws -> DocumentFileCompositionResult {
        let root = try source("root.3md", document(metadata: ["3md-files": #"{"1":"leaf.3md"}"#]))
        return try DocumentFileComposition.resolve(
            rootPath: root.path,
            sources: [root, try source("leaf.3md", document())]
        )
    }

    private func assertFileFailure<Value>(_ expected: DocumentFileCompositionError, _ body: () throws -> Value) {
        XCTAssertThrowsError(try body()) { XCTAssertEqual($0 as? DocumentFileCompositionError, expected) }
    }

    private func assertCompositionFailure<Value>(_ expected: DocumentCompositionError, _ body: () throws -> Value) {
        XCTAssertThrowsError(try body()) { XCTAssertEqual($0 as? DocumentCompositionError, expected) }
    }
}
