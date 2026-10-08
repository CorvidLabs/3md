import Foundation
import RookSculpture
import Testing

@testable import RookTool

@Test func sparseWorldCLIInspectKeepsExactCoordinatesAndExtractsOnlyAnExplicitModel() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "rook-world-cli-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let library = try SculptureCompositionExamples.courtyard()
    let world = try SculptureWorld(
        title: "Exact positions",
        library: library,
        instances: [
            try SculptureWorldInstance(
                id: "distant",
                modelID: "garden",
                origin: SculptureWorldPoint(x: 9_007_199_254_740_995, y: -99, z: Int64.min)
            )
        ]
    )
    let input = folder.appendingPathComponent("world.3md")
    let original = try SculptureWorldCodec.encode(world)
    try original.write(to: input)
    let result = try SculptureCommandTool.run(arguments: ["inspect", input.path], workingDirectory: folder)
    let json = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
    #expect(json["mode"] as? String == "sparse-world")
    let instances = try #require(json["instances"] as? [[String: Any]])
    #expect(instances[0]["x"] as? String == "9007199254740995")
    #expect(instances[0]["z"] as? String == String(Int64.min))
    let output = folder.appendingPathComponent("garden.3mdb")
    _ = try SculptureCommandTool.run(arguments: ["model", input.path, "garden", output.path], workingDirectory: folder)
    #expect(try SculptureDocumentCodec.decode(Data(contentsOf: output)) == library.expanded(modelID: "garden"))
    #expect(throws: (any Error).self) {
        _ = try SculptureCommandTool.run(
            arguments: ["model", input.path, "garden", output.path],
            workingDirectory: folder
        )
    }
    #expect(try Data(contentsOf: input) == original)
    let absent = folder.appendingPathComponent("absent.3md")
    #expect(throws: (any Error).self) {
        _ = try SculptureCommandTool.run(
            arguments: ["model", input.path, "missing", absent.path],
            workingDirectory: folder
        )
    }
    #expect(!FileManager.default.fileExists(atPath: absent.path))
    #expect(throws: (any Error).self) {
        _ = try SculptureCommandTool.run(arguments: ["expand", input.path, absent.path], workingDirectory: folder)
    }
    #expect(throws: (any Error).self) {
        _ = try SculptureCommandTool.run(
            arguments: ["apply", input.path, "missing.json", absent.path],
            workingDirectory: folder
        )
    }
    #expect(!FileManager.default.fileExists(atPath: absent.path))
}
