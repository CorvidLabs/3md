import Foundation
import RookSculpture
import Testing

@testable import RookTool

private struct CommandFixture {
    let folder: URL
    let input: URL
    let commands: URL

    init(format: SculptureStorageFormat = .readable, sculpture: Sculpture = .blank()) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SculptCommandTest-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        input = folder.appendingPathComponent("source with spaces.\(format.fileExtension)")
        commands = folder.appendingPathComponent("commands.json")
        try SculptureDocumentCodec.encode(sculpture, format: format).write(to: input)
    }

    func write(_ batch: SculptureCommandBatch) throws {
        try JSONEncoder().encode(batch).write(to: commands)
    }

    func apply(to output: URL) throws -> Data {
        try SculptureCommandTool.run(
            arguments: ["apply", input.path, commands.path, output.path],
            workingDirectory: folder
        )
    }
}

@Test func commandCLIInspectsAndPublishesCanonicalEditsWithMachineReadableResult() throws {
    let fixture = try CommandFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let original = try Data(contentsOf: fixture.input)
    let inspected = try SculptureCommandTool.run(
        arguments: ["inspect", fixture.input.lastPathComponent],
        workingDirectory: fixture.folder
    )
    let inspection = try JSONDecoder().decode(SculptureInspection.self, from: inspected)
    #expect(inspection.coordinateBase == 0)
    #expect(inspection.occupiedCount == 0)
    try fixture.write(
        SculptureCommandBatch(commands: [
            .rename(title: "Agent copy"), .paint(x: 2, y: 3, z: 0, glyph: "@"),
        ])
    )
    let output = fixture.folder.appendingPathComponent("edited copy.3md")
    let report = try #require(JSONSerialization.jsonObject(with: fixture.apply(to: output)) as? [String: Any])
    #expect(report["operation"] as? String == "apply")
    #expect(report["appliedCommandCount"] as? Int == 2)
    #expect(report["output"] as? String == output.path)
    let document = try SculptureCodec.decode(Data(contentsOf: output))
    #expect(document.title == "Agent copy")
    #expect(document.glyph(at: SculptureCell(x: 2, y: 3, z: 0)) == 64)
    #expect(try Data(contentsOf: output) == SculptureCodec.encode(document))
    #expect(try Data(contentsOf: fixture.input) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).count == 3)
}

@Test func failedCLIBatchCreatesNoOutputAndKeepsInputAndCommandBytes() throws {
    let fixture = try CommandFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    try fixture.write(
        SculptureCommandBatch(commands: [
            .rename(title: "Must not publish"), .paint(x: 0, y: 0, z: 0, glyph: "#"),
            .erase(x: 999, y: 0, z: 0),
        ])
    )
    let original = try Data(contentsOf: fixture.input)
    let commandBytes = try Data(contentsOf: fixture.commands)
    let output = fixture.folder.appendingPathComponent("rejected.3md")
    #expect(throws: (any Error).self) { try fixture.apply(to: output) }
    #expect(!FileManager.default.fileExists(atPath: output.path))
    #expect(try Data(contentsOf: fixture.input) == original)
    #expect(try Data(contentsOf: fixture.commands) == commandBytes)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).count == 2)
}

@Test func cliRefusesExistingFilesDirectoriesAndDanglingOutputSymlinks() throws {
    let fixture = try CommandFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    try fixture.write(SculptureCommandBatch(commands: [.rename(title: "New title")]))
    let manager = FileManager.default
    let existing = fixture.folder.appendingPathComponent("existing.3md")
    let original = Data("keep these bytes".utf8)
    try original.write(to: existing)
    #expect(throws: (any Error).self) { try fixture.apply(to: existing) }
    #expect(try Data(contentsOf: existing) == original)
    let directory = fixture.folder.appendingPathComponent("existing-directory.3md")
    try manager.createDirectory(at: directory, withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try fixture.apply(to: directory) }
    let link = fixture.folder.appendingPathComponent("dangling.3md")
    let absent = fixture.folder.appendingPathComponent("must-not-exist.3md")
    try manager.createSymbolicLink(at: link, withDestinationURL: absent)
    #expect(throws: (any Error).self) { try fixture.apply(to: link) }
    #expect(try manager.destinationOfSymbolicLink(atPath: link.path) == absent.path)
    #expect(!manager.fileExists(atPath: absent.path))
    let names = try manager.contentsOfDirectory(atPath: fixture.folder.path)
    #expect(!names.contains { $0.hasPrefix(".rook-command-") })
}

@Test func cliRefusesNonRegularOversizedAndMalformedInputsBeforePublishing() throws {
    let fixture = try CommandFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    #expect(throws: (any Error).self) {
        try SculptureCommandTool.run(arguments: ["inspect", fixture.folder.path], workingDirectory: fixture.folder)
    }
    let large = fixture.folder.appendingPathComponent("large.3md")
    try Data(repeating: 46, count: SculptureCodec.maximumBytes + 1).write(to: large)
    #expect(throws: (any Error).self) {
        try SculptureCommandTool.run(arguments: ["inspect", large.path], workingDirectory: fixture.folder)
    }
    let output = fixture.folder.appendingPathComponent("not-written.3md")
    for source in [
        #"{"version":1,"commands":[{"action":"rename","title":"OK","ignored":true}]}"#,
        #"{"version":2,"commands":[{"action":"clearSlice","z":0}]}"#,
        #"{"version":1,"commands":[]}"#,
        "not JSON",
    ] {
        try Data(source.utf8).write(to: fixture.commands)
        #expect(throws: (any Error).self) { try fixture.apply(to: output) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

@Test func commandCLIInspectsAndEditsSliceTwoHundredFiftyFiveBeyondTheOldFileBudget() throws {
    let fixture = try CommandFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let large = try Sculpture(
        title: "Large agent document",
        width: 256,
        height: 16,
        layers: Array(repeating: Array(repeating: UInt8(35), count: 4096), count: 256)
    )
    let encoded = SculptureCodec.encode(large)
    #expect(encoded.count > 1_048_576)
    try encoded.write(to: fixture.input)
    let inspected = try SculptureCommandTool.run(
        arguments: ["inspect", fixture.input.path],
        workingDirectory: fixture.folder
    )
    let inspection = try JSONDecoder().decode(SculptureInspection.self, from: inspected)
    #expect(inspection.width == 256 && inspection.height == 16 && inspection.depth == 256)
    #expect(inspection.occupiedCount == 1_048_576)
    try fixture.write(SculptureCommandBatch(commands: [.erase(x: 255, y: 15, z: 255)]))
    let output = fixture.folder.appendingPathComponent("large-edited.3md")
    _ = try fixture.apply(to: output)
    let edited = try SculptureCodec.decode(Data(contentsOf: output))
    #expect(edited.occupiedCount == 1_048_575)
    #expect(edited.glyph(at: SculptureCell(x: 255, y: 15, z: 255)) == Sculpture.empty)
    #expect(edited.glyph(at: SculptureCell(x: 255, y: 15, z: 254)) == 35)
    try fixture.write(
        SculptureCommandBatch(commands: [.rename(title: "Must not publish"), .erase(x: 255, y: 15, z: 256)])
    )
    let refused = fixture.folder.appendingPathComponent("beyond-depth-limit.3md")
    #expect(throws: (any Error).self) { try fixture.apply(to: refused) }
    #expect(!FileManager.default.fileExists(atPath: refused.path))
    #expect(try Data(contentsOf: fixture.input) == encoded)
}

@Test func commandJSONKeepsItsIndependentTwoHundredFiftySixKiBBoundary() throws {
    let fixture = try CommandFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let original = try Data(contentsOf: fixture.input)
    var commandBytes = try JSONEncoder().encode(SculptureCommandBatch(commands: [.rename(title: "Exact JSON limit")]))
    commandBytes.append(Data(repeating: 32, count: 262_144 - commandBytes.count))
    #expect(commandBytes.count == 262_144)
    #expect(commandBytes.count < SculptureCodec.maximumBytes)
    try commandBytes.write(to: fixture.commands)
    let output = fixture.folder.appendingPathComponent("exact-command-limit.3md")
    _ = try fixture.apply(to: output)
    #expect(try SculptureCodec.decode(Data(contentsOf: output)).title == "Exact JSON limit")
    commandBytes.append(32)
    try commandBytes.write(to: fixture.commands)
    let refused = fixture.folder.appendingPathComponent("over-command-limit.3md")
    do {
        _ = try fixture.apply(to: refused)
        Issue.record("A 262,145-byte command document must be refused.")
    } catch {
        #expect(String(describing: error).contains("at most 262144 bytes"))
    }
    #expect(!FileManager.default.fileExists(atPath: refused.path))
    #expect(try Data(contentsOf: fixture.input) == original)
}

@Test func cliWritesChosenTemporaryDirectoryAndDirectoryAliasWithoutReplacingEntries() throws {
    let fixture = try CommandFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    try fixture.write(SculptureCommandBatch(commands: [.rename(title: "Temporary directory")]))
    let temporaryOutput = URL(fileURLWithPath: "/private/tmp/SculptCommandOutput-\(UUID()).3md")
    defer { try? FileManager.default.removeItem(at: temporaryOutput) }
    _ = try fixture.apply(to: temporaryOutput)
    #expect(try SculptureCodec.decode(Data(contentsOf: temporaryOutput)).title == "Temporary directory")
    #expect(throws: (any Error).self) { try fixture.apply(to: temporaryOutput) }
    let alias = fixture.folder.appendingPathComponent("chosen-alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.folder)
    let output = alias.appendingPathComponent("through-alias.3md")
    _ = try fixture.apply(to: output)
    #expect(try SculptureCodec.decode(Data(contentsOf: output)).title == "Temporary directory")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path) == fixture.folder.path)
    #expect(throws: (any Error).self) { try fixture.apply(to: output) }
}

@Test func commandCLIInspectsCompactDocumentsAndAutodetectsBytesWithoutExtensionHints() throws {
    let source = try commandStorageSculpture()
    let fixture = try CommandFixture(format: .compact, sculpture: source)
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let original = try Data(contentsOf: fixture.input)
    #expect(SculptureDocumentCodec.format(of: original) == .compact)
    let misleadingName = fixture.folder.appendingPathComponent("compact document under a text name.3md")
    try original.write(to: misleadingName)
    for input in [fixture.input, misleadingName] {
        let result = try SculptureCommandTool.run(
            arguments: ["inspect", input.lastPathComponent],
            workingDirectory: fixture.folder
        )
        let inspection = try JSONDecoder().decode(SculptureInspection.self, from: result)
        #expect(inspection.title == "Stored sculpture")
        #expect(inspection.width == 8 && inspection.height == 6 && inspection.depth == 3)
        #expect(inspection.occupiedCount == 3)
        #expect(inspection.coordinateBase == 0)
    }
    #expect(try Data(contentsOf: fixture.input) == original)
}

@Test func commandCLIStoresCompactEditsFromExplicitOutputExtensionAndPreservesInput() throws {
    let fixture = try CommandFixture(format: .compact, sculpture: commandStorageSculpture())
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let original = try Data(contentsOf: fixture.input)
    try fixture.write(
        SculptureCommandBatch(commands: [
            .rename(title: "Edited compact copy"), .erase(x: 7, y: 5, z: 2), .paint(x: 6, y: 4, z: 2, glyph: "x"),
        ])
    )
    let output = fixture.folder.appendingPathComponent("edited compact copy.3MDB")
    let result = try #require(JSONSerialization.jsonObject(with: fixture.apply(to: output)) as? [String: Any])
    #expect(result["output"] as? String == output.path)
    #expect(result["appliedCommandCount"] as? Int == 3)
    let data = try Data(contentsOf: output)
    #expect(SculptureDocumentCodec.format(of: data) == .compact)
    let edited = try SculptureBinaryCodec.decode(data)
    #expect(edited.title == "Edited compact copy")
    #expect(edited.occupiedCount == 3)
    #expect(edited.glyph(at: SculptureCell(x: 7, y: 5, z: 2)) == Sculpture.empty)
    #expect(edited.glyph(at: SculptureCell(x: 6, y: 4, z: 2)) == 120)
    #expect(edited.glyph(at: SculptureCell(x: 3, y: 2, z: 1)) == 64)
    #expect(try Data(contentsOf: fixture.input) == original)
    #expect(throws: (any Error).self) { try fixture.apply(to: output) }
    #expect(try Data(contentsOf: output) == data)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).count == 3)
}

@Test func commandCLIConvertsBothStorageFormatsWhileApplyingTheSameCommands() throws {
    let conversions: [(input: SculptureStorageFormat, output: SculptureStorageFormat)] = [
        (.readable, .compact), (.compact, .readable),
    ]
    for conversion in conversions {
        let source = try commandStorageSculpture()
        let fixture = try CommandFixture(format: conversion.input, sculpture: source)
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let original = try Data(contentsOf: fixture.input)
        try fixture.write(
            SculptureCommandBatch(commands: [.rename(title: "Converted copy"), .paint(x: 5, y: 3, z: 1, glyph: "o")])
        )
        let output = fixture.folder.appendingPathComponent("converted.\(conversion.output.fileExtension)")
        _ = try fixture.apply(to: output)
        let data = try Data(contentsOf: output)
        #expect(SculptureDocumentCodec.format(of: data) == conversion.output)
        let converted: Sculpture
        switch conversion.output {
        case .readable:
            converted = try SculptureCodec.decode(data)
            #expect(data == SculptureCodec.encode(converted))
        case .compact:
            converted = try SculptureBinaryCodec.decode(data)
        }
        #expect(converted.title == "Converted copy")
        #expect(converted.width == source.width && converted.height == source.height && converted.depth == source.depth)
        #expect(converted.occupiedCount == 4)
        #expect(converted.glyph(at: SculptureCell(x: 5, y: 3, z: 1)) == 111)
        #expect(converted.glyph(at: SculptureCell(x: 7, y: 5, z: 2)) == 43)
        #expect(converted.glyph(at: SculptureCell(x: 0, y: 0, z: 0)) == 35)
        #expect(try Data(contentsOf: fixture.input) == original)
    }
}

@Test func commandCLIRejectsUnsupportedOutputExtensionsWithoutWritingOrChangingInputs() throws {
    let fixture = try CommandFixture(format: .compact, sculpture: commandStorageSculpture())
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    try fixture.write(SculptureCommandBatch(commands: [.rename(title: "Must not publish")]))
    let original = try Data(contentsOf: fixture.input)
    let commands = try Data(contentsOf: fixture.commands)
    for name in ["no-extension", "mesh.obj", "compact.3mdb.tmp", "document.json"] {
        let output = fixture.folder.appendingPathComponent(name)
        do {
            _ = try fixture.apply(to: output)
            Issue.record("An unsupported output extension must be refused.")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("Unsupported output extension"))
            #expect(message.contains(".3md") && message.contains(".3mdb"))
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
    #expect(try Data(contentsOf: fixture.input) == original)
    #expect(try Data(contentsOf: fixture.commands) == commands)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).count == 2)
}

@Test func commandCLIReportsTruncatedCompactInputWithoutPublishingEdits() throws {
    let fixture = try CommandFixture(format: .compact, sculpture: commandStorageSculpture())
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let original = try Data(contentsOf: fixture.input)
    let truncated = Data(original.dropLast())
    try truncated.write(to: fixture.input)
    try fixture.write(SculptureCommandBatch(commands: [.rename(title: "Must not publish")]))
    let output = fixture.folder.appendingPathComponent("rejected.3mdb")
    do {
        _ = try fixture.apply(to: output)
        Issue.record("A truncated compact document must be refused.")
    } catch {
        #expect(String(describing: error).contains("Invalid sculpture"))
    }
    #expect(!FileManager.default.fileExists(atPath: output.path))
    #expect(try Data(contentsOf: fixture.input) == truncated)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).count == 2)
}

private func commandStorageSculpture() throws -> Sculpture {
    var sculpture = try Sculpture(
        title: "Stored sculpture",
        width: 8,
        height: 6,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: 48), count: 3)
    )
    sculpture.paint(SculptureCell(x: 0, y: 0, z: 0), glyph: 35)
    sculpture.paint(SculptureCell(x: 7, y: 5, z: 2), glyph: 43)
    sculpture.paint(SculptureCell(x: 3, y: 2, z: 1), glyph: 64)
    return sculpture
}

private struct CompositionFixture {
    let folder: URL
    let recipeFolder: URL
    let manifest: URL
    let model: URL

    init(format: SculptureStorageFormat = .compact) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SculptCompositionCLI-\(UUID())")
        recipeFolder = folder.appendingPathComponent("chosen recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: recipeFolder, withIntermediateDirectories: true)
        manifest = recipeFolder.appendingPathComponent("scene.json")
        model = recipeFolder.appendingPathComponent("corner model.\(format.fileExtension)")
        let sculpture = try Sculpture(
            title: "Corner model",
            width: 2,
            height: 2,
            layers: [
                Array("#@..".utf8), Array("..+.".utf8),
            ]
        )
        try SculptureDocumentCodec.encode(sculpture, format: format).write(to: model)
        try write(manifestObject())
    }

    func manifestObject() -> [String: Any] {
        [
            "version": 1, "title": "Repeated corners", "width": 3, "height": 2,
            "tileWidth": 2, "tileHeight": 2, "tileDepth": 2,
            "layers": [["C.C", ".C."], [".C.", "..."]],
            "bindings": [["glyph": "C", "model": "castle", "quarterTurns": 1]],
            "models": [["id": "castle", "path": model.lastPathComponent]],
        ]
    }

    func write(_ object: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: manifest)
    }

    func compose(to output: URL) throws -> Data {
        try SculptureCommandTool.run(
            arguments: ["compose", manifest.path, output.path],
            workingDirectory: folder
        )
    }

    func expand(_ composition: URL, to output: URL) throws -> Data {
        try SculptureCommandTool.run(
            arguments: ["expand", composition.path, output.path],
            workingDirectory: folder
        )
    }
}

@Test func compositionCLIEmbedsOneSharedModelAndPlacesRotatedSingleCharacterTilesInThreeAxes() throws {
    let fixture = try CompositionFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let originalManifest = try Data(contentsOf: fixture.manifest)
    let originalModel = try Data(contentsOf: fixture.model)
    let output = fixture.folder.appendingPathComponent("self contained.3md")
    let result = try #require(JSONSerialization.jsonObject(with: fixture.compose(to: output)) as? [String: Any])
    #expect(result["operation"] as? String == "compose")
    #expect(result["output"] as? String == output.path)
    let inspection = try #require(result["composition"] as? [String: Any])
    #expect(inspection["mode"] as? String == "composition")
    #expect(inspection["modelCount"] as? Int == 2)
    let root = try #require(inspection["root"] as? [String: Any])
    #expect(root["coordinateBase"] as? Int == 0)
    #expect(root["layers"] as? [[String]] == [["C.C", ".C."], [".C.", "..."]])
    let data = try Data(contentsOf: output)
    #expect(SculptureCompositionCodec.isComposition(data))
    let composition = try SculptureCompositionCodec.decode(data)
    #expect(composition.models.count == 2)
    guard case .sculpture(let stored)? = composition.models["castle"] else {
        Issue.record("The four C placements must reference one stored leaf model.")
        return
    }
    #expect(stored.occupiedCount == 3)
    #expect(!String(decoding: data, as: UTF8.self).contains(fixture.model.lastPathComponent))
    let expanded = try composition.expanded()
    #expect(expanded.width == 6 && expanded.height == 4 && expanded.depth == 4)
    #expect(expanded.occupiedCount == 12)
    #expect(expanded.glyph(at: SculptureCell(x: 1, y: 0, z: 0)) == 35)
    #expect(expanded.glyph(at: SculptureCell(x: 1, y: 1, z: 0)) == 64)
    #expect(expanded.glyph(at: SculptureCell(x: 0, y: 0, z: 1)) == 43)
    #expect(expanded.glyph(at: SculptureCell(x: 5, y: 0, z: 0)) == 35)
    #expect(expanded.glyph(at: SculptureCell(x: 3, y: 2, z: 0)) == 35)
    #expect(expanded.glyph(at: SculptureCell(x: 3, y: 0, z: 2)) == 35)
    #expect(expanded.glyph(at: SculptureCell(x: 2, y: 0, z: 0)) == Sculpture.empty)
    #expect(expanded.glyph(at: SculptureCell(x: 5, y: 3, z: 3)) == Sculpture.empty)
    #expect(try Data(contentsOf: fixture.manifest) == originalManifest)
    #expect(try Data(contentsOf: fixture.model) == originalModel)
    try FileManager.default.removeItem(at: fixture.recipeFolder)
    #expect(try SculptureCompositionCodec.decode(Data(contentsOf: output)).expanded() == expanded)
    let report = try SculptureCommandTool.run(arguments: ["inspect", output.path], workingDirectory: fixture.folder)
    let inspected = try #require(JSONSerialization.jsonObject(with: report) as? [String: Any])
    let voxels = try #require(inspected["expanded"] as? [String: Any])
    #expect(voxels["occupiedCount"] as? Int == 12)
    #expect(inspected["rootID"] as? String == "root")
}

@Test func compositionCLIExpandsToBothVoxelFormatsAndRefusesImplicitFlattening() throws {
    let fixture = try CompositionFixture(format: .readable)
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let compositionURL = fixture.folder.appendingPathComponent("composed.3md")
    _ = try fixture.compose(to: compositionURL)
    let original = try Data(contentsOf: compositionURL)
    let expected = try SculptureCompositionCodec.decode(original).expanded()
    try FileManager.default.removeItem(at: fixture.recipeFolder)
    for format in SculptureStorageFormat.allCases {
        let output = fixture.folder.appendingPathComponent("expanded.\(format.fileExtension)")
        let report = try #require(
            JSONSerialization.jsonObject(with: fixture.expand(compositionURL, to: output)) as? [String: Any]
        )
        #expect(report["operation"] as? String == "expand")
        #expect(report["sourceModelCount"] as? Int == 2)
        let data = try Data(contentsOf: output)
        #expect(!SculptureCompositionCodec.isComposition(data))
        #expect(SculptureDocumentCodec.format(of: data) == format)
        #expect(try SculptureDocumentCodec.decode(data) == expected)
        #expect(throws: (any Error).self) { try fixture.expand(compositionURL, to: output) }
        #expect(try Data(contentsOf: output) == data)
    }
    let commands = fixture.folder.appendingPathComponent("commands.json")
    try JSONEncoder().encode(SculptureCommandBatch(commands: [.rename(title: "Must not flatten")])).write(to: commands)
    let rejected = fixture.folder.appendingPathComponent("unrequested flattening.3md")
    do {
        _ = try SculptureCommandTool.run(
            arguments: ["apply", compositionURL.path, commands.path, rejected.path],
            workingDirectory: fixture.folder
        )
        Issue.record("apply must refuse a composition rather than silently flatten its model graph.")
    } catch {
        #expect(String(describing: error).contains("Use sculpture expand first"))
    }
    #expect(!FileManager.default.fileExists(atPath: rejected.path))
    #expect(try Data(contentsOf: compositionURL) == original)
}

@Test func compositionCLIImportsNestedGraphsWithoutPrivateIDCollisionsOrExternalDependencies() throws {
    let fixture = try CompositionFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let childURL = fixture.recipeFolder.appendingPathComponent("nested child.3md")
    _ = try fixture.compose(to: childURL)
    var manifest = fixture.manifestObject()
    manifest["title"] = "Nested pair"
    manifest["width"] = 2
    manifest["height"] = 1
    manifest["tileWidth"] = 6
    manifest["tileHeight"] = 4
    manifest["tileDepth"] = 4
    manifest["layers"] = [["NN"]]
    manifest["bindings"] = [["glyph": "N", "model": "castle", "quarterTurns": 0]]
    // Both documents use root and castle internally; part-0 deliberately collides with a remapping candidate.
    manifest["models"] = [
        ["id": "castle", "path": childURL.lastPathComponent],
        ["id": "part-0", "path": fixture.model.lastPathComponent],
    ]
    try fixture.write(manifest)
    let output = fixture.folder.appendingPathComponent("nested composition.3md")
    _ = try fixture.compose(to: output)
    let stored = try SculptureCompositionCodec.decode(Data(contentsOf: output))
    #expect(stored.models.count == 4)
    #expect(stored.models["root"] != nil && stored.models["castle"] != nil && stored.models["part-0"] != nil)
    let expanded = try stored.expanded()
    #expect(expanded.width == 12 && expanded.height == 4 && expanded.depth == 4)
    #expect(expanded.occupiedCount == 24)
    #expect(expanded.glyph(at: SculptureCell(x: 1, y: 0, z: 0)) == 35)
    #expect(expanded.glyph(at: SculptureCell(x: 7, y: 0, z: 0)) == 35)
    #expect(expanded.glyph(at: SculptureCell(x: 8, y: 0, z: 0)) == Sculpture.empty)
    try FileManager.default.removeItem(at: fixture.recipeFolder)
    #expect(try SculptureCompositionCodec.decode(Data(contentsOf: output)).expanded() == expanded)
}

@Test func compositionCLIRejectsUnknownFieldsInvalidReferencesAndUnusableFilesWithoutPublishing() throws {
    let fixture = try CompositionFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let originalModel = try Data(contentsOf: fixture.model)
    var cases: [[String: Any]] = []
    var object = fixture.manifestObject()
    object["ignored"] = true
    cases.append(object)
    object = fixture.manifestObject()
    object["bindings"] = [["glyph": "C", "model": "castle", "quarterTurns": 0, "ignored": true]]
    cases.append(object)
    object = fixture.manifestObject()
    object["models"] = [["id": "castle", "path": fixture.model.lastPathComponent, "ignored": true]]
    cases.append(object)
    object = fixture.manifestObject()
    object["version"] = 2
    cases.append(object)
    object = fixture.manifestObject()
    object["models"] = [["id": "root", "path": fixture.model.lastPathComponent]]
    cases.append(object)
    object = fixture.manifestObject()
    object["models"] = [["id": "../castle", "path": fixture.model.lastPathComponent]]
    cases.append(object)
    object = fixture.manifestObject()
    object["models"] = Array(repeating: ["id": "castle", "path": fixture.model.lastPathComponent], count: 2)
    cases.append(object)
    object = fixture.manifestObject()
    object["bindings"] = Array(repeating: ["glyph": "C", "model": "castle", "quarterTurns": 0], count: 2)
    cases.append(object)
    object = fixture.manifestObject()
    object["bindings"] = [["glyph": "C", "model": "unlisted", "quarterTurns": 0]]
    cases.append(object)
    object = fixture.manifestObject()
    object["layers"] = [["C?C", ".C."], [".C.", "..."]]
    cases.append(object)
    object = fixture.manifestObject()
    object["layers"] = [["CC", ".C."], [".C.", "..."]]
    cases.append(object)
    object = fixture.manifestObject()
    object["tileWidth"] = 1
    cases.append(object)
    object = fixture.manifestObject()
    object["models"] = [["id": "castle", "path": "missing.3md"]]
    cases.append(object)
    object = fixture.manifestObject()
    object["models"] = [["id": "castle", "path": "."]]
    cases.append(object)
    let corrupt = fixture.recipeFolder.appendingPathComponent("corrupt.3mdb")
    try Data("not a document".utf8).write(to: corrupt)
    object = fixture.manifestObject()
    object["models"] = [["id": "castle", "path": corrupt.lastPathComponent]]
    cases.append(object)
    for (index, invalid) in cases.enumerated() {
        try fixture.write(invalid)
        let manifestBytes = try Data(contentsOf: fixture.manifest)
        let output = fixture.folder.appendingPathComponent("rejected-\(index).3md")
        #expect(throws: (any Error).self) { try fixture.compose(to: output) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try Data(contentsOf: fixture.manifest) == manifestBytes)
        #expect(try Data(contentsOf: fixture.model) == originalModel)
        #expect(
            try !FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).contains {
                $0.hasPrefix(".rook-command-")
            }
        )
    }
}

@Test func compositionCLIRequiresExplicitFormatsAndAtomicallyRefusesExistingEntries() throws {
    let fixture = try CompositionFixture()
    defer { try? FileManager.default.removeItem(at: fixture.folder) }
    let composed = fixture.folder.appendingPathComponent("composed.3md")
    _ = try fixture.compose(to: composed)
    let original = try Data(contentsOf: composed)
    #expect(throws: (any Error).self) { try fixture.compose(to: composed) }
    #expect(try Data(contentsOf: composed) == original)
    let dangling = fixture.folder.appendingPathComponent("dangling.3md")
    let target = fixture.folder.appendingPathComponent("absent.3md")
    try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: target)
    #expect(throws: (any Error).self) { try fixture.compose(to: dangling) }
    #expect(throws: (any Error).self) { try fixture.expand(composed, to: dangling) }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: dangling.path) == target.path)
    #expect(!FileManager.default.fileExists(atPath: target.path))
    for name in ["compact.3mdb", "mesh.obj", "no-extension"] {
        let rejected = fixture.folder.appendingPathComponent(name)
        do {
            _ = try fixture.compose(to: rejected)
            Issue.record("A composition must be saved as .3md.")
        } catch {
            #expect(String(describing: error).contains("must use .3md"))
        }
        #expect(!FileManager.default.fileExists(atPath: rejected.path))
    }
    let rejected = fixture.folder.appendingPathComponent("flattened.obj")
    #expect(throws: (any Error).self) { try fixture.expand(composed, to: rejected) }
    #expect(!FileManager.default.fileExists(atPath: rejected.path))
    let leafExpansion = fixture.folder.appendingPathComponent("leaf expansion.3md")
    do {
        _ = try fixture.expand(fixture.model, to: leafExpansion)
        Issue.record("expand should require a composition input.")
    } catch {
        #expect(String(describing: error).contains("requires a composition"))
    }
    #expect(!FileManager.default.fileExists(atPath: leafExpansion.path))
    #expect(
        try !FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).contains {
            $0.hasPrefix(".rook-command-")
        }
    )
}
