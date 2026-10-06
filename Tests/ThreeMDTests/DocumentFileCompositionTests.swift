import Dispatch
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

    func testDiscoveryMissingFilePrecedesUnvalidatedFinalGraphDepth() throws {
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
            XCTAssertEqual(error as? DocumentFileCompositionError, .missingFile("missing"))
        }
    }

    func testOuterRecognitionDoesNotUseCallerPlaneLimitBeforeByteAndLinePolicies() throws {
        let value = Document(version: "1.0", axis: .space, planes: [Plane(z: 0, body: "A"), Plane(z: 1, body: "B")])
        for binary in [false, true] {
            let input = try source("root", value, binary: binary)
            let policies: [(DocumentDecodeLimits, DocumentStorageError)] = [
                (try .init(maximumEncodedBytes: 1, maximumPlanes: 1), .oversizedInput),
                (try .init(maximumDecodedBytes: 1, maximumPlanes: 1), .oversizedOutput),
                (try .init(maximumLines: 1, maximumPlanes: 1), .tooManyLines),
            ]
            for (policy, expected) in policies {
                XCTAssertThrowsError(
                    try DocumentFileComposition.resolve(rootPath: "root", sources: [input], documentLimits: policy)
                ) {
                    XCTAssertEqual($0 as? DocumentStorageError, expected)
                }
            }
        }
    }

    func testDisconnectedEmbeddedLedgerUsesActualEntryDepthAndRepeatedCachedFiles() throws {
        let embedded = try DocumentComposition(
            rootID: "r",
            entries: [
                .init(id: "r", document: document(title: "Root")),
                .init(id: "u", document: document(metadata: ["3md-files": #"{"1":"x"}"#])),
            ]
        )
        let sources = try [
            source("root", document(metadata: ["3md-files": #"{"1":"bundle","2":"bundle"}"#])),
            DocumentFileSource(path: "bundle", data: DocumentCompositionCodec.encode(embedded)),
            source("x", document(title: "Disconnected child")),
        ]
        let result = try DocumentFileComposition.resolve(
            rootPath: "root",
            sources: sources,
            limits: .init(maximumDepth: 2)
        )
        XCTAssertEqual(result.composition.entries.count, 4)
        XCTAssertEqual(result.resolvedPaths, ["bundle", "root", "x"])
        XCTAssertEqual(result.composition.rootEntry.references.map(\.targetID), ["file-000000", "file-000000"])
        XCTAssertEqual(result.composition.entry(id: "file-000001")?.references.first?.targetID, "file-000003")
    }

    func testRepeatedCachedFilesAreStillCheckedAgainstFinalCompleteEntryDepth() throws {
        let sources = try [
            source("root", document(metadata: ["3md-files": #"{"1":"short","2":"long"}"#])),
            source("short", document(metadata: ["3md-files": #"{"1":"leaf"}"#])),
            source("long", document(metadata: ["3md-files": #"{"1":"short","2":"short"}"#])),
            source("leaf", document()),
        ]
        assertCompositionFailure(.depthExceeded) {
            try DocumentFileComposition.resolve(rootPath: "root", sources: sources, limits: .init(maximumDepth: 3))
        }
        let valid = try DocumentFileComposition.resolve(
            rootPath: "root",
            sources: sources,
            limits: .init(maximumDepth: 4)
        )
        XCTAssertEqual(valid.composition.entries.count, 4)
        XCTAssertEqual(
            valid.composition.entry(id: "file-000001")?.references.map(\.targetID),
            ["file-000003", "file-000003"]
        )
    }

    func testFixedFileDiscoverySafetyCeilingRemainsBoundedForDisconnectedEntries() throws {
        func files(_ count: Int) throws -> [DocumentFileSource] {
            try (0..<count).map { index in
                let metadata = index + 1 < count ? ["3md-files": "{\"1\":\"f\(index + 1)\"}"] : [:]
                let graph = try DocumentComposition(
                    rootID: "r",
                    entries: [
                        .init(id: "r", document: document()), .init(id: "u", document: document(metadata: metadata)),
                    ]
                )
                return .init(path: "f\(index)", data: try DocumentCompositionCodec.encode(graph))
            }
        }
        let valid = try DocumentFileComposition.resolve(
            rootPath: "f0",
            sources: files(64),
            limits: .init(maximumDepth: 2)
        )
        XCTAssertEqual(valid.composition.entries.count, 128)
        assertCompositionFailure(.depthExceeded) {
            try DocumentFileComposition.resolve(rootPath: "f0", sources: files(65), limits: .init(maximumDepth: 2))
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
            #"{"1":"x"} trailing"#, #"{"1":"\ud800"}"#, #"{"1":"\udc00"}"#,
            "{\"1\":\"a\u{01}b\"}", "{\"1\":\"a\tb\"}",
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

    func testOwnerDirectoryResolutionKeepsParentDotAndGrammarSemantics() throws {
        let cases = [
            ("../../x", "a/b/c/owner", "a/x"), ("x/..", "a/owner", "a"), ("../c", "a/\u{301}b/owner", "a/c"),
            ("./x/./y", "a/./b/owner", "a/b/x/y"), ("child", "owner", "child"), ("x/../../y", "a/b/owner", "a/y"),
        ]
        for (source, owner, expected) in cases {
            XCTAssertEqual(try DocumentFileComposition.resolvePath(source, relativeTo: owner), expected)
        }
        for (source, owner) in [("../..", "a/b/owner"), ("x/../..", "a/owner"), ("..", "owner"), ("../../..", "a/b/o")]
        {
            assertFileFailure(.invalidPath(source)) {
                try DocumentFileComposition.resolvePath(source, relativeTo: owner)
            }
        }
    }

    func testLongOwnerPathWithManyReferencesResolvesEveryReferenceInItsDirectory() throws {
        let glyphs = (33...126).map { String(UnicodeScalar(UInt8($0))) }
        let ledger = String(
            decoding: try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: glyphs.map { ($0, "leaf.3md") })),
            as: UTF8.self
        )
        let entries = (0..<3).map { DocumentEntry(id: "e\($0)", document: document(metadata: ["3md-files": ledger])) }
        let graph = try DocumentComposition(
            rootID: "m",
            entries: entries + [
                .init(id: "m", document: document(), references: entries.map { .init(targetID: $0.id) })
            ]
        )
        let owner = "owner/" + String(repeating: "\u{E9}", count: 200_000) + ".3md"
        let result = try DocumentFileComposition.resolve(
            rootPath: owner,
            sources: [
                .init(path: owner, data: try DocumentCompositionCodec.encode(graph)),
                try source("owner/leaf.3md", document(body: "Leaf")),
            ]
        )
        XCTAssertEqual(result.resolvedPaths, ["owner/leaf.3md", owner])
        let edges = result.composition.entries.flatMap(\.references).filter { $0.attributes["glyph"] != nil }
        XCTAssertEqual(edges.count, 3 * glyphs.count)
        XCTAssertTrue(edges.allSatisfy { $0.attributes["source-file"] == "owner/leaf.3md" })
    }

    func testRefusalsFollowEntryIDThenGlyphDiscoveryOrder() throws {
        assertFileFailure(.missingFile("missing")) {
            try DocumentFileComposition.resolve(
                rootPath: "root",
                sources: [try source("root", document(metadata: ["3md-files": #"{"a":"missing","b":"/x"}"#]))]
            )
        }
        assertFileFailure(.invalidPath("/x")) {
            try DocumentFileComposition.resolve(
                rootPath: "root",
                sources: [try source("root", document(metadata: ["3md-files": #"{"a":"/x","b":"missing"}"#]))]
            )
        }
        for (first, second, expected) in [
            ("missing", "/x", DocumentFileCompositionError.missingFile("missing")),
            ("/x", "missing", DocumentFileCompositionError.invalidPath("/x")),
        ] {
            let graph = try DocumentComposition(
                rootID: "m",
                entries: [
                    .init(id: "m", document: document()),
                    .init(id: "a", document: document(metadata: ["3md-files": "{\"z\":\"\(first)\"}"])),
                    .init(id: "b", document: document(metadata: ["3md-files": "{\"a\":\"\(second)\"}"])),
                ]
            )
            assertFileFailure(expected) {
                try DocumentFileComposition.resolve(
                    rootPath: "root",
                    sources: [.init(path: "root", data: try DocumentCompositionCodec.encode(graph))]
                )
            }
        }
    }

    func testRootAndUnreachableSuppliedPathsUseTheLedgerPathGrammar() throws {
        let leaf = try source("root.3md", document())
        for path in ["/root.3md", ".", "../root.3md", "", "a\\b.3md", "a:b.3md", "a\u{7F}b.3md", "a\u{0}b.3md"] {
            assertFileFailure(.invalidPath(path)) {
                try DocumentFileComposition.resolve(rootPath: path, sources: [leaf])
            }
            assertFileFailure(.invalidPath(path)) {
                try DocumentFileComposition.resolve(
                    rootPath: leaf.path,
                    sources: [leaf, .init(path: path, data: leaf.data)]
                )
            }
        }
        let percent = try DocumentFileComposition.resolve(
            rootPath: "root",
            sources: [
                try source("root", document(metadata: ["3md-files": #"{"1":"%2e%2e/leaf"}"#])),
                try source("%2e%2e/leaf", document()),
            ]
        )
        XCTAssertEqual(percent.resolvedPaths, ["%2e%2e/leaf", "root"])
        let distinct = try DocumentFileComposition.resolve(
            rootPath: "root",
            sources: [
                try source("root", document(metadata: ["3md-files": #"{"1":"Leaf","2":"leaf"}"#])),
                try source("Leaf", document(body: "Upper")), try source("leaf", document(body: "Lower")),
            ]
        )
        XCTAssertEqual(distinct.resolvedPaths, ["Leaf", "leaf", "root"])
    }

    func testLedgerEscapesDecodeBeforePathGrammar() throws {
        func resolve(_ ledger: String, _ extra: [DocumentFileSource] = []) throws -> DocumentFileCompositionResult {
            try DocumentFileComposition.resolve(
                rootPath: "root",
                sources: [try source("root", document(metadata: ["3md-files": ledger]))] + extra
            )
        }
        let leaf = try source("models/leaf", document())
        let slash = try resolve(#"{"1":"models\/leaf","2":"models/leaf"}"#, [leaf])
        XCTAssertEqual(slash.resolvedPaths, ["models/leaf", "root"])
        XCTAssertEqual(Set(slash.composition.rootEntry.references.map(\.targetID)).count, 1)
        assertFileFailure(.invalidPath("models\\leaf")) { try resolve(#"{"1":"models\\leaf"}"#, [leaf]) }
        assertFileFailure(.invalidPath("a\u{1}b")) { try resolve(#"{"1":"a\u0001b"}"#) }
        // The ledger text holds the escape pair itself: backslash, "ud83d", backslash, "ude00".
        let backslash = "\u{5C}"
        let escaped = "{\"1\":\"" + backslash + "ud83d" + backslash + "ude00\"}"
        XCTAssertFalse(escaped.unicodeScalars.contains("\u{1F600}"))
        let pair = try resolve(escaped, [try source("\u{1F600}", document())])
        XCTAssertEqual(pair.resolvedPaths, ["root", "\u{1F600}"])
        XCTAssertThrowsError(try resolve(#"{"\ud800":"leaf"}"#)) {
            guard case .invalidLedger = $0 as? DocumentFileCompositionError else {
                return XCTFail("Expected a malformed ledger, received \($0)")
            }
        }
    }

    func testSelfAndAliasCyclesCompareNormalizedPaths() throws {
        for ledger in [#"{"1":"root.3md"}"#, #"{"1":"./root.3md"}"#] {
            assertCompositionFailure(.cycle("root.3md")) {
                try DocumentFileComposition.resolve(
                    rootPath: "root.3md",
                    sources: [try source("root.3md", document(metadata: ["3md-files": ledger]))]
                )
            }
        }
        for (child, link) in [("models/child.3md", "../root.3md"), ("child.3md", "models/../root.3md")] {
            assertCompositionFailure(.cycle("root.3md")) {
                try DocumentFileComposition.resolve(
                    rootPath: "root.3md",
                    sources: [
                        try source("root.3md", document(metadata: ["3md-files": "{\"1\":\"\(child)\"}"])),
                        try source(child, document(metadata: ["3md-files": "{\"1\":\"\(link)\"}"])),
                    ]
                )
            }
        }
    }

    func testCachedSubtreeIsChargedAtItsDeeperOccurrenceAgainstTheDiscoveryCeiling() throws {
        func chain(_ prefix: String, count: Int, lastLedger: String?) throws -> [DocumentFileSource] {
            try (1...count).map { index in
                let ledger = index < count ? "{\"1\":\"\(prefix)\(index + 1)\"}" : lastLedger
                let graph = try DocumentComposition(
                    rootID: "r",
                    entries: [
                        .init(id: "r", document: document()),
                        .init(
                            id: "u",
                            document: document(metadata: ledger.map { ["3md-files": $0] } ?? [:])
                        ),
                    ]
                )
                return .init(path: "\(prefix)\(index)", data: try DocumentCompositionCodec.encode(graph))
            }
        }
        let root = try source("root", document(metadata: ["3md-files": #"{"1":"a1","2":"b1"}"#]))
        let long = try chain("a", count: 40, lastLedger: nil)
        assertCompositionFailure(.depthExceeded) {
            try DocumentFileComposition.resolve(
                rootPath: "root",
                sources: [root] + long + chain("b", count: 24, lastLedger: #"{"1":"a1"}"#)
            )
        }
        // Only the cache-hit height check can refuse before b24's second glyph names a missing file.
        assertCompositionFailure(.depthExceeded) {
            try DocumentFileComposition.resolve(
                rootPath: "root",
                sources: [root] + long + chain("b", count: 24, lastLedger: #"{"1":"a1","2":"missing"}"#)
            )
        }
        let exact = try DocumentFileComposition.resolve(
            rootPath: "root",
            sources: [root] + long + chain("b", count: 23, lastLedger: #"{"1":"a1"}"#)
        )
        XCTAssertEqual(exact.composition.entries.count, 127)
    }

    func testExistingEdgesPrecedeLedgerEdgesAndEmbeddedLedgersResolveFromTheirBundleFolder() throws {
        let graph = try DocumentComposition(
            rootID: "m",
            entries: [
                .init(
                    id: "m",
                    document: document(metadata: ["3md-files": #"{"2":"leaf"}"#]),
                    references: [.init(targetID: "c", attributes: ["glyph": "1", "opaque": "keep"])]
                ),
                .init(id: "c", document: document(body: "Kept")),
            ]
        )
        let result = try DocumentFileComposition.resolve(
            rootPath: "root",
            sources: [
                try source("root", document(metadata: ["3md-files": #"{"1":"models/group"}"#])),
                .init(path: "models/group", data: try DocumentCompositionCodec.encode(graph)),
                try source("models/leaf", document(body: "Leaf")),
            ]
        )
        let group = try XCTUnwrap(result.composition.entry(id: try XCTUnwrap(result.fileRootIDs["models/group"])))
        XCTAssertEqual(group.references.map { $0.attributes["glyph"] }, ["1", "2"])
        XCTAssertEqual(group.references.first?.attributes["opaque"], "keep")
        XCTAssertEqual(group.references.last?.targetID, result.fileRootIDs["models/leaf"])
        XCTAssertEqual(group.references.last?.attributes["source-file"], "models/leaf")
    }

    func testResolverOutputRebundlesWithOpaqueGlyphAndSourceFileAttributes() throws {
        let first = try simpleResult()
        let second = try DocumentFileComposition.resolve(
            rootPath: "root.3md",
            sources: [
                try source("root.3md", document(metadata: ["3md-files": #"{"1":"archive/bundle.3md"}"#])),
                .init(path: "archive/bundle.3md", data: try DocumentCompositionCodec.encode(first.composition)),
            ]
        )
        XCTAssertEqual(second.resolvedPaths, ["archive/bundle.3md", "root.3md"])
        XCTAssertEqual(second.composition.entries.count, 3)
        let archived = try XCTUnwrap(
            second.composition.entry(id: try XCTUnwrap(second.fileRootIDs["archive/bundle.3md"]))
        )
        XCTAssertEqual(archived.references.first?.attributes, ["glyph": "1", "source-file": "leaf.3md"])
    }

    func testSourceFileAttributeBoundCountsNormalizedUTF8Bytes() throws {
        // glyph (5) + "1" (1) + source-file (11) + path: a 16,367-byte NFC path exactly fills 16,384 bytes.
        func resolve(padding: Int, limits: DocumentCompositionLimits = .standard) throws
            -> DocumentFileCompositionResult
        {
            let path = "models/" + String(repeating: "e\u{301}", count: 8_000) + String(repeating: "a", count: padding)
            let ledger = String(decoding: try JSONEncoder().encode(["1": path]), as: UTF8.self)
            return try DocumentFileComposition.resolve(
                rootPath: "root",
                sources: [try source("root", document(metadata: ["3md-files": ledger])), try source(path, document())],
                limits: limits
            )
        }
        let exact = try resolve(padding: 360)
        let edge = try XCTUnwrap(exact.composition.rootEntry.references.first)
        XCTAssertEqual(edge.attributes["source-file"]?.utf8.count, 16_367)
        assertCompositionFailure(.referenceAttributesExceeded) { try resolve(padding: 361) }
        let lowered = try DocumentCompositionLimits(maximumReferenceAttributeBytes: 16_383)
        assertCompositionFailure(.referenceAttributesExceeded) { try resolve(padding: 360, limits: lowered) }
    }

    func testLoweredPolicyChargesOriginalPathBytesBeforePathGrammarAndEncodedBytesBeforeDecoding() throws {
        let root = try source("/root", document())
        assertFileFailure(.inputLimit) {
            try DocumentFileComposition.resolve(
                rootPath: "/root",
                sources: [root],
                limits: .init(maximumProfileBytes: 9)
            )
        }
        assertFileFailure(.invalidPath("/root")) {
            try DocumentFileComposition.resolve(
                rootPath: "/root",
                sources: [root],
                limits: .init(maximumProfileBytes: 10)
            )
        }
        assertFileFailure(.inputLimit) {
            try DocumentFileComposition.resolve(
                rootPath: "a",
                sources: [try source("a", document()), try source("b", document()), try source("c", document())],
                limits: .init(maximumDefinitions: 2)
            )
        }
        let parent = try source("root", document(metadata: ["3md-files": #"{"1":"leaf"}"#]))
        let leaf = try source("leaf", document())
        let result = try DocumentFileComposition.resolve(
            rootPath: "root",
            sources: [parent, leaf],
            limits: .init(maximumReferenceAttributes: 2)
        )
        XCTAssertEqual(result.composition.entries.count, 2)
    }

    func testOverBoundLedgerEdgeIsRefusedWhileResolvingBeforeLaterRefusals() throws {
        // A 40-byte policy leaves 23 bytes for a target after "glyph", the glyph and "source-file".
        let tight = try DocumentCompositionLimits(maximumReferenceAttributeBytes: 40)
        let long = String(repeating: "x", count: 30) + ".3md"
        func resolve(root: String = "root", _ sources: [DocumentFileSource]) throws -> DocumentFileCompositionResult {
            try DocumentFileComposition.resolve(rootPath: root, sources: sources, limits: tight)
        }
        func ledger(_ fields: [String: String]) throws -> [String: String] {
            ["3md-files": String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)]
        }
        let target = try source(long, document())
        assertCompositionFailure(.referenceAttributesExceeded) {
            try resolve([try source("root", document(metadata: ledger(["a": long, "b": "missing"]))), target])
        }
        assertFileFailure(.missingFile("missing")) {
            try resolve([try source("root", document(metadata: ledger(["a": "missing", "b": long]))), target])
        }
        assertCompositionFailure(.referenceAttributesExceeded) {
            try resolve([try source("root", document(metadata: ledger(["1": long])))])
        }
        assertCompositionFailure(.referenceAttributesExceeded) {
            try resolve(root: long, [try source(long, document(metadata: ledger(["1": "./" + long])))])
        }
        assertFileFailure(.invalidPath(long + "/")) {
            try resolve([try source("root", document(metadata: ledger(["1": long + "/"])))])
        }
    }

    func testAttributeBoundCountsNormalizedDirectoryPrefixBytes() throws {
        // Twelve decomposed é become 24 NFC bytes, so "é…/leaf" is 29 bytes and needs a 46-byte policy.
        let directory = String(repeating: "e\u{301}", count: 12)
        let sources = try [
            source(directory + "/root", document(metadata: ["3md-files": #"{"1":"leaf","2":"../top"}"#])),
            source(directory + "/leaf", document()), source("top", document()),
        ]
        let result = try DocumentFileComposition.resolve(
            rootPath: directory + "/root",
            sources: sources,
            limits: .init(maximumReferenceAttributeBytes: 46)
        )
        let edge = try XCTUnwrap(result.composition.rootEntry.references.first)
        XCTAssertEqual(edge.attributes["source-file"]?.utf8.count, 29)
        assertCompositionFailure(.referenceAttributesExceeded) {
            try DocumentFileComposition.resolve(
                rootPath: directory + "/root",
                sources: sources,
                limits: .init(maximumReferenceAttributeBytes: 45)
            )
        }
    }

    func testLongDirectoryOwnersResolveRepeatedSourcesOnceAndRefuseOverBoundTargetsAtTheFirstEdge() throws {
        let glyphs = (33...126).map { String(UnicodeScalar(UInt8($0))) }
        let ledger = String(
            decoding: try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: glyphs.map { ($0, "leaf.3md") })),
            as: UTF8.self
        )
        func owner(_ directory: String, entries count: Int) throws -> [DocumentFileSource] {
            let entries = (0..<count).map {
                DocumentEntry(id: "e\($0)", document: document(metadata: ["3md-files": ledger]))
            }
            let graph = try DocumentComposition(
                rootID: "m",
                entries: entries + [
                    .init(id: "m", document: document(), references: entries.map { .init(targetID: $0.id) })
                ]
            )
            return [
                .init(path: directory + "/root", data: try DocumentCompositionCodec.encode(graph)),
                try source(directory + "/leaf.3md", document(body: "Leaf")),
            ]
        }
        let inBound = String(repeating: "d", count: 8_000)
        let result = try DocumentFileComposition.resolve(
            rootPath: inBound + "/root",
            sources: owner(inBound, entries: 3)
        )
        let edges = result.composition.entries.flatMap(\.references).filter { $0.attributes["glyph"] != nil }
        XCTAssertEqual(edges.count, 3 * glyphs.count)
        XCTAssertTrue(edges.allSatisfy { $0.attributes["source-file"] == inBound + "/leaf.3md" })
        let overBound = String(repeating: "d", count: 262_144)
        assertCompositionFailure(.referenceAttributesExceeded) {
            try DocumentFileComposition.resolve(rootPath: overBound + "/root", sources: owner(overBound, entries: 170))
        }
    }

    @MainActor
    func testCancellationDuringARunningFanOutResolutionPublishesNoResult() async throws {
        let sources = try cancellationWorkload(files: 60)
        // The uncancelled duration sets the cancellation delay, so the run cannot finish within it.
        let baselineStart = DispatchTime.now().uptimeNanoseconds
        XCTAssertEqual(
            try DocumentFileComposition.resolve(rootPath: "m/root", sources: sources).resolvedPaths.count,
            61
        )
        let baseline = DispatchTime.now().uptimeNanoseconds - baselineStart
        let delay = baseline / 4
        let started = StartSignal()
        let task = Task.detached { () -> (failure: (any Error)?, callStart: UInt64) in
            await started.mark()
            let callStart = DispatchTime.now().uptimeNanoseconds
            do {
                _ = try DocumentFileComposition.resolve(rootPath: "m/root", sources: sources)
                return (nil, callStart)
            } catch {
                return (error, callStart)
            }
        }
        while !(await started.isMarked) { await Task.yield() }
        try await Task.sleep(nanoseconds: delay)
        let cancelAt = DispatchTime.now().uptimeNanoseconds
        task.cancel()
        let outcome = await task.value
        guard let failure = outcome.failure else {
            return XCTFail("A resolution canceled while running returned a composition")
        }
        XCTAssertTrue(failure is CancellationError, "Unexpected error \(failure)")
        // The call had been running for at least half the delay when cancellation arrived, so this is a
        // mid-run interruption, not a check at entry. A thread descheduled for that long between recording
        // `callStart` and entering the call would defeat the assertion; that residual is accepted.
        XCTAssertGreaterThan(cancelAt, outcome.callStart)
        XCTAssertGreaterThanOrEqual(cancelAt - outcome.callStart, delay / 2)
    }

    /// About 16 KB per file, fanned out through ledgers in a composition root.
    private func cancellationWorkload(files count: Int) throws -> [DocumentFileSource] {
        let body = String(repeating: "abcdefghij", count: 1_600)
        var sources = try (0..<count).map { try source("f/\($0)", document(body: body)) }
        let glyphs = (33...126).map { String(UnicodeScalar(UInt8($0))) }
        var entries: [DocumentEntry] = []
        for group in 0..<((count + glyphs.count - 1) / glyphs.count) {
            var ledger: [String: String] = [:]
            for (offset, glyph) in glyphs.enumerated() where group * glyphs.count + offset < count {
                ledger[glyph] = "../f/\(group * glyphs.count + offset)"
            }
            let json = String(decoding: try JSONEncoder().encode(ledger), as: UTF8.self)
            entries.append(.init(id: "g\(group)", document: document(metadata: ["3md-files": json])))
        }
        let root = try DocumentComposition(
            rootID: "root",
            entries: entries + [
                .init(id: "root", document: document(), references: entries.map { .init(targetID: $0.id) })
            ]
        )
        sources.append(.init(path: "m/root", data: try DocumentCompositionCodec.encode(root)))
        return sources
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

/// Marks when a detached resolution is about to begin so the test can cancel it while it runs.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
fileprivate actor StartSignal {
    private(set) var isMarked = false

    func mark() { isMarked = true }
}
