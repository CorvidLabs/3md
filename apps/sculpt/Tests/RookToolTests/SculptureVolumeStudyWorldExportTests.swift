import Foundation
import RookSculpture
import Testing

@testable import RookTool

@Suite("Volume world study publication", .serialized)
struct SculptureVolumeStudyWorldExportTests {
    @Test func rejectsInvalidAndExistingDestinationsWithoutChangingThem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookWorldStudy-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("marker")
        try Data("keep".utf8).write(to: marker)
        for arguments in [[], ["--output", "relative"], ["--output", folder.path], ["--output", marker.path]] {
            #expect(throws: (any Error).self) { try SculptureVolumeStudyWorldExport.run(arguments: arguments) }
        }
        let link = folder.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        #expect(throws: (any Error).self) {
            try SculptureVolumeStudyWorldExport.run(arguments: ["--output", link.path])
        }
        #expect(try Data(contentsOf: marker) == Data("keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["link", "marker"])
    }

    @Test func publishesSupportedWorldCopiesWithExactFacts() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookWorldStudy-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("new")
        let receipt = try SculptureVolumeStudyWorldExport.run(
            arguments: ["--output", output.path],
            hooks: .init(willPublish: { staging, target in
                #expect(!FileManager.default.fileExists(atPath: target.path))
                let files = try? FileManager.default.contentsOfDirectory(atPath: staging.path)
                #expect(files?.count == 7)
            })
        )
        let json = try #require(JSONSerialization.jsonObject(with: receipt) as? [String: Any])
        let records = try #require(json["worlds"] as? [[String: Any]])
        #expect(records.count == 2)
        #expect(records[0]["repeatedOccupiedCells"] as? Int64 == 1_073_741_824)
        #expect(records[0]["uniqueVoxelBytes"] as? Int == 262_144)
        #expect(records[0]["instanceCount"] as? Int == 4096)
        for id in ["solid-1024", "landscape-1024"] {
            let native = try SculptureWorldCodec.decode(Data(contentsOf: output.appendingPathComponent(id + ".3md")))
            for suffix in ["portable.3md", "portable.3mdb"] {
                let portable = try SculptureThreeMDCodec.decode(
                    Data(contentsOf: output.appendingPathComponent(id + "." + suffix))
                )
                #expect(portable.scene == .world(native))
            }
        }
        #expect(try Data(contentsOf: output.appendingPathComponent("worlds.json")) == receipt)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["new"])
    }

    @Test func replacementDirectoryIsNeitherPublishedNorRecursivelyRemoved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookWorldStudy-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("new")
        let moved = folder.appendingPathComponent("moved-owned-stage")
        let victim = folder.appendingPathComponent("preexisting")
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: victim.appendingPathComponent("marker"))
        var directory = try SculptureVolumeStudyWorldExport.StudyDirectory(output: output)
        try directory.write(Data("owned".utf8), name: "fixture")
        try FileManager.default.moveItem(at: directory.stagingURL, to: moved)
        try FileManager.default.moveItem(at: victim, to: directory.stagingURL)
        #expect(throws: SculptureVolumeStudyWorldExport.StudyError.destination) { try directory.publish() }
        directory.close(removeFiles: true)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try Data(contentsOf: directory.stagingURL.appendingPathComponent("marker")) == Data("keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.stagingURL.path) == ["marker"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path).isEmpty)
    }

    @Test func exclusiveDirectoryPublicationPreservesARacingExistingTarget() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookWorldStudy-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("new")
        var directory = try SculptureVolumeStudyWorldExport.StudyDirectory(output: output)
        try directory.write(Data("owned".utf8), name: "fixture")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: output.appendingPathComponent("marker"))
        #expect(throws: SculptureVolumeStudyWorldExport.StudyError.destination) { try directory.publish() }
        directory.close(removeFiles: true)
        #expect(try Data(contentsOf: output.appendingPathComponent("marker")) == Data("keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["new"])
    }

    @Test func cleanupPreservesAReplacementFileInsideThePinnedStagingDirectory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookWorldStudy-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let victim = folder.appendingPathComponent("preexisting-file")
        try Data("keep".utf8).write(to: victim)
        var directory = try SculptureVolumeStudyWorldExport.StudyDirectory(output: folder.appendingPathComponent("new"))
        try directory.write(Data("owned".utf8), name: "fixture")
        let fixture = directory.stagingURL.appendingPathComponent("fixture")
        try FileManager.default.moveItem(at: fixture, to: folder.appendingPathComponent("moved-owned-file"))
        try FileManager.default.moveItem(at: victim, to: fixture)
        directory.close(removeFiles: true)
        #expect(try Data(contentsOf: fixture) == Data("keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.stagingURL.path) == ["fixture"])
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("new").path))
    }

    @Test func cancellationAfterCreatingStagingLeavesNoOutputOrTemporaryDirectory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookWorldStudy-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("new")
        let task = Task {
            try SculptureVolumeStudyWorldExport.run(
                arguments: ["--output", output.path],
                hooks: .init(didCreateStaging: { _ in withUnsafeCurrentTask { $0?.cancel() } })
            )
        }
        do {
            _ = try await task.value
            Issue.record("A cancelled world export unexpectedly published a directory.")
        } catch is CancellationError {
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
    }
}
