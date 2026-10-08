import Foundation
import Testing
import ThreeMD

@testable import RookSculpture

struct SculptureLinkedBundleTests {
    @Test func readableAndBinaryBundlesRoundTripWithoutTheProjectFolder() async throws {
        let project = try diningProject()
        let resolution = try await project.resolve("scenes/main.3md")
        for format in SculptureLinkedBundleFormat.allCases {
            let data = try SculptureLinkedBundle.encode(resolution, format: format)
            #expect(try SculptureLinkedBundle.encode(resolution, format: format) == data)
            #expect(SculptureThreeMDCodec.isPortable(data) && !SculptureLinkedCodec.isLinked(data))
            switch format {
            case .readable:
                #expect(!DocumentStorageCodec.isBinary(data))
                let expected = try DocumentCompositionCodec.encode(
                    resolution.bundle,
                    limits: SculptureThreeMDPolicy.composition(),
                    documentLimits: SculptureThreeMDPolicy.document()
                )
                #expect(data == expected)
            case .binary:
                #expect(DocumentStorageCodec.isBinary(data))
                #expect(data[data.index(data.startIndex, offsetBy: 11)] == DocumentCompression.none.rawValue)
            }
            let opened = try SculptureSceneReader.decode(data)
            #expect(opened.scene == resolution.scene)
            let snapshot = try SculptureLinkedBundle.decode(data)
            #expect(opened.snapshot == snapshot && snapshot.scene == resolution.scene)
            let storage: DocumentStorageFormat = format == .readable ? .text : .binary(compression: .none)
            let reopened = try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(snapshot, format: storage))
            #expect(reopened == snapshot)
        }
        let graph = try DocumentCompositionCodec.decode(SculptureLinkedBundle.encode(resolution, format: .readable))
        #expect(graph.entries.allSatisfy { $0.document.metadata["3md-files"] == nil })
        let root = try #require(graph.entry(id: graph.rootID))
        #expect(root.document.metadata["scene-schema"] == "ascii-linked-composition-1")
        #expect(root.document.metadata["sculpt-turns"] == "{\"A\":1}")
        #expect(
            Set(root.references.map(\.attributes)) == [
                ["glyph": "A", "source-file": "models/chair.3md"], ["glyph": "B", "source-file": "rooms/annex.3md"],
            ]
        )
        guard case .tiles(let map)? = resolution.composition.models[resolution.composition.rootID] else {
            Issue.record("Expected a linked root map")
            return
        }
        #expect(map.bindings.map(\.quarterTurns) == [1, 0])
    }

    @Test func aBundleProducedDirectlyByThreeMDResolutionOpensAsAComposition() async throws {
        let project = try diningProject()
        let resolution = try await project.resolve("scenes/main.3md")
        let result = try DocumentFileComposition.resolve(
            rootPath: "scenes/main.3md",
            sources: project.files.map { DocumentFileSource(path: $0.key, data: $0.value) }
        )
        #expect(result.resolvedPaths == resolution.resolvedPaths)
        let readable = try DocumentCompositionCodec.encode(result.composition)
        let binary = try DocumentStorageCodec.encode(
            DocumentCompositionCodec.document(for: result.composition),
            format: .binary(compression: .none)
        )
        for data in [readable, binary] {
            let opened = try SculptureSceneReader.decode(data)
            #expect(opened.scene == resolution.scene)
            #expect(opened.snapshot != nil)
        }
    }

    @Test func sourceFileIsNeverFollowedAndOtherReferenceAttributesAreIgnored() async throws {
        let resolution = try await diningProject().resolve("scenes/main.3md")
        let rewritten = try rewritingLinkedReferences(resolution.bundle) { attributes in
            var changed = attributes
            changed["source-file"] = "../../../outside/never-read.3md"
            changed["note"] = "opaque"
            return changed
        }
        let opened = try SculptureSceneReader.decode(DocumentCompositionCodec.encode(rewritten))
        #expect(opened.scene == resolution.scene)
        let refusals: [([String: String]) -> [String: String]] = [
            { attributes in attributes.filter { $0.key != "source-file" } },
            { attributes in attributes.merging(["glyph": "AB"]) { _, new in new } },
            { attributes in attributes.merging(["glyph": "."]) { _, new in new } },
            { attributes in attributes.merging(["glyph": "65"]) { _, new in new } },
        ]
        for change in refusals {
            let invalid = try rewritingLinkedReferences(resolution.bundle, change)
            #expect(throws: SculptureThreeMDError.self) {
                try SculptureSceneReader.decode(DocumentCompositionCodec.encode(invalid))
            }
        }
    }

    @Test func aBundledLinkedEntryMustBeAVersionOneSpaceDocument() async throws {
        let resolution = try await diningProject().resolve("scenes/main.3md")
        let unchanged = try rewritingLinkedDocuments(resolution.bundle) { $0 }
        #expect(try SculptureSceneReader.decode(DocumentCompositionCodec.encode(unchanged)).scene == resolution.scene)
        let changes: [(String, (Document) -> Document)] = [
            ("axis time", { document in document.with(axis: .time) }),
            ("axis layer, the parser's reading of a missing axis", { document in document.with(axis: .layer) }),
            ("version 2.0", { document in document.with(version: "2.0") }),
        ]
        for (name, change) in changes {
            let invalid = try rewritingLinkedDocuments(resolution.bundle, change)
            #expect(throws: SculptureThreeMDError.self, "A linked entry with \(name) must be refused") {
                try SculptureSceneReader.decode(DocumentCompositionCodec.encode(invalid))
            }
        }
    }

    @Test func editedBundleScenesSaveAsCompositionsWithoutLinkedMetadata() async throws {
        let resolution = try await diningProject().resolve("scenes/main.3md")
        let snapshot = try SculptureLinkedBundle.decode(SculptureLinkedBundle.encode(resolution, format: .readable))
        #expect(try SculptureThreeMDCodec.capture(snapshot.scene, preserving: snapshot) == snapshot)
        let edited = try SculptureComposition(
            title: "Edited dining room",
            rootID: resolution.composition.rootID,
            models: resolution.composition.models
        )
        let captured = try SculptureThreeMDCodec.capture(.composition(edited), preserving: snapshot)
        let data = try SculptureThreeMDCodec.encode(captured)
        #expect(try SculptureSceneReader.decode(data).scene == .composition(edited))
        let graph = try DocumentCompositionCodec.decode(data)
        for entry in graph.entries {
            let keys = Set(entry.document.metadata.keys)
            #expect(entry.document.metadata["scene-schema"] != "ascii-linked-composition-1")
            #expect(keys.isDisjoint(with: ["sculpt-turns", "3md-files"]))
            #expect(entry.references.allSatisfy { $0.attributes["source-file"] == nil })
        }
    }
}

/// A project with a turned voxel, a nested linked room, an uncompressed binary voxel and an unreachable file.
private func diningProject() throws -> LinkedTestProject {
    let tile = try SculptureTileSize(width: 2, height: 2, depth: 2)
    let root = try SculptureLinkedComposition(
        title: "Dining room",
        width: 2,
        height: 1,
        tileSize: tile,
        layers: [[65, 66]],
        files: [65: "../models/chair.3md", 66: "../rooms/annex.3md"],
        quarterTurns: [65: 1]
    )
    let annex = try SculptureLinkedComposition(
        title: "Annex",
        width: 2,
        height: 1,
        tileSize: .init(width: 1, height: 1, depth: 1),
        layers: [[84, 46]],
        files: [84: "../models/table.3md", 85: "../models/unplaced.3md"]
    )
    return LinkedTestProject([
        "scenes/main.3md": try SculptureLinkedCodec.encode(root),
        "rooms/annex.3md": try SculptureLinkedCodec.encode(annex),
        "models/chair.3md": SculptureCodec.encode(try LinkedFixture.voxel("Chair", glyph: 64, width: 2)),
        "models/table.3md": try LinkedFixture.binaryVoxel(LinkedFixture.voxel("Table", glyph: 111)),
        "models/unplaced.3md": try LinkedFixture.voxelData("Unplaced"),
        "models/unreachable.3md": try LinkedFixture.voxelData("Unreachable"),
    ])
}

/// Rewrites the attributes of every reference whose entry declares the linked schema.
private func rewritingLinkedReferences(
    _ graph: DocumentComposition,
    _ transform: ([String: String]) -> [String: String]
) throws -> DocumentComposition {
    let entries = graph.entries.map { entry in
        guard entry.document.metadata["scene-schema"] == "ascii-linked-composition-1" else { return entry }
        return DocumentEntry(
            id: entry.id,
            document: entry.document,
            references: entry.references.map { .init(targetID: $0.targetID, attributes: transform($0.attributes)) }
        )
    }
    return try DocumentComposition(rootID: graph.rootID, entries: entries)
}

/// Rewrites the document of every entry that declares the linked schema, keeping its references.
private func rewritingLinkedDocuments(
    _ graph: DocumentComposition,
    _ transform: (Document) -> Document
) throws -> DocumentComposition {
    let entries = graph.entries.map { entry in
        guard entry.document.metadata["scene-schema"] == "ascii-linked-composition-1" else { return entry }
        return DocumentEntry(id: entry.id, document: transform(entry.document), references: entry.references)
    }
    return try DocumentComposition(rootID: graph.rootID, entries: entries)
}

extension Document {
    /// This document with another version or axis.
    fileprivate func with(version: String? = nil, axis: Axis? = nil) -> Document {
        Document(
            version: version ?? self.version,
            axis: axis ?? self.axis,
            title: title,
            metadata: metadata,
            preamble: preamble,
            planes: planes
        )
    }
}
