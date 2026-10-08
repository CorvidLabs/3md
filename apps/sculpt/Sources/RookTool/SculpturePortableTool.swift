import Foundation
import RookSculpture
import ThreeMD

/// Explicit file interchange for people and agents. Legacy commands keep their existing formats.
internal enum SculpturePortableTool {
    static let maximumRequestBytes = 262_144

    static func run(arguments: [String], workingDirectory: URL) throws -> Data {
        do { return try execute(arguments: arguments, workingDirectory: workingDirectory) } catch let error
            as DocumentEditError
        {
            throw PortableToolError.diagnostic(error.diagnostic)
        } catch let error as SculptureThreeMDError {
            throw PortableToolError.diagnostic(error.diagnostic)
        } catch let error as DocumentStorageError {
            if case .invalidText(let parseError) = error {
                throw PortableToolError.diagnostic(DocumentDiagnostics.parseFailure(parseError))
            }
            throw error
        }
    }

    private static func execute(arguments: [String], workingDirectory: URL) throws -> Data {
        try Task.checkCancellation()
        guard let action = arguments.first else { throw PortableToolError.usage }
        switch action {
        case "inspect":
            guard arguments.count == 2 else { throw PortableToolError.usage }
            let input = try url(arguments[1], relativeTo: workingDirectory)
            let data = try read(input)
            let snapshot = try decode(data, file: input)
            return try json(Inspection(snapshot: snapshot, portableInput: SculptureThreeMDCodec.isPortable(data)))
        case "export":
            guard arguments.count == 3 else { throw PortableToolError.usage }
            let input = try url(arguments[1], relativeTo: workingDirectory)
            let snapshot = try decode(read(input), file: input)
            let output = try url(arguments[2], relativeTo: workingDirectory)
            let data = try encode(snapshot, to: output)
            let receipt = try json(Receipt(action: action, output: output.path, snapshot: snapshot, bytes: data.count))
            try SculptureReferenceModelTool.publishNewFile(data, at: output)
            return receipt
        case "apply":
            guard arguments.count == 4 else { throw PortableToolError.usage }
            let input = try url(arguments[1], relativeTo: workingDirectory)
            let current = try decode(read(input), file: input)
            let requestURL = try url(arguments[2], relativeTo: workingDirectory)
            let requestData = try SculptureReferenceModelTool.readFile(
                at: requestURL,
                maximumBytes: maximumRequestBytes
            )
            try PortableRequestJSON.validate(requestData)
            let request = try JSONDecoder().decode(Request.self, from: requestData)
            let expectedURL = try url(request.expectedScene, relativeTo: requestURL.deletingLastPathComponent())
            let expected = try decode(read(expectedURL), file: expectedURL)
            // Check the complete exact revision before applying any local command.
            guard current.revision == expected.revision else {
                throw DocumentEditError(
                    .init(
                        code: .staleRevision,
                        message: "The scene differs from expectedScene.",
                        path: "expectedRevision"
                    )
                )
            }
            let source = try voxelModel(request.modelID, in: current.scene)
            let replacement = try SculptureCommandEngine.apply(request.batch, to: source)
            let edited = try SculptureThreeMDEditing.replacingVoxelModel(
                in: current,
                modelID: request.modelID,
                expectedRevision: expected.revision,
                with: replacement
            )
            let output = try url(arguments[3], relativeTo: workingDirectory)
            let data = try encode(edited, to: output)
            let receipt = try json(Receipt(action: action, output: output.path, snapshot: edited, bytes: data.count))
            try SculptureReferenceModelTool.publishNewFile(data, at: output)
            return receipt
        case "insert":
            return try SculptureInsertTool.runPortable(
                arguments: Array(arguments.dropFirst()),
                workingDirectory: workingDirectory
            )
        default: throw PortableToolError.usage
        }
    }

    static func read(_ url: URL) throws -> Data {
        try SculptureReferenceModelTool.readFile(at: url, maximumBytes: SculptureDocumentCodec.maximumBytes)
    }

    /// Decodes one named scene file with the shared reader. A self-contained bundle opens as a composition; a linked
    /// root is refused naming `file`, because its models are other files that only the app reads with its folder.
    static func decode(_ data: Data, file: URL) throws -> SculptureThreeMDSnapshot {
        let opened: (scene: SculptureScene, snapshot: SculptureThreeMDSnapshot?)
        do { opened = try SculptureSceneReader.decode(data) } catch let error as SculptureLinkedError {
            throw SculptureLinkedInput.naming(error, file: file.path)
        }
        return try opened.snapshot ?? SculptureThreeMDCodec.capture(opened.scene)
    }

    private static func voxelModel(_ modelID: String, in scene: SculptureScene) throws -> Sculpture {
        let library: SculptureComposition
        switch scene {
        case .composition(let value): library = value
        case .world(let value): library = value.library
        case .voxels: throw SculptureModelEditingError.voxelModelRequired(modelID)
        }
        guard case .sculpture(let sculpture) = library.models[modelID] else {
            throw SculptureModelEditingError.voxelModelRequired(modelID)
        }
        return sculpture
    }

    static func encode(_ snapshot: SculptureThreeMDSnapshot, to output: URL) throws -> Data {
        switch output.pathExtension.lowercased() {
        case "3md": return try SculptureThreeMDCodec.encode(snapshot, format: .text)
        case "3mdb": return try SculptureThreeMDCodec.encode(snapshot, format: .binary(compression: .none))
        default: throw PortableToolError.outputExtension
        }
    }

    static func url(_ path: String, relativeTo directory: URL) throws -> URL {
        guard !path.isEmpty, !path.utf8.contains(0) else { throw PortableToolError.invalidPath }
        return (path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path))
            .standardizedFileURL
    }

    static func json(_ value: some Encodable) throws -> Data {
        try Task.checkCancellation()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(10)
        try Task.checkCancellation()
        return data
    }

    private struct Request: Decodable {
        let version: Int
        let modelID: String
        let expectedScene: String
        let batch: SculptureCommandBatch

        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: Key.self)
            guard Set(fields.allKeys.map(\.stringValue)) == ["version", "modelID", "expectedScene", "batch"] else {
                throw PortableToolError.requestFields
            }
            version = try fields.decode(Int.self, forKey: Key("version"))
            guard version == 1 else { throw PortableToolError.requestVersion }
            modelID = try fields.decode(String.self, forKey: Key("modelID"))
            expectedScene = try fields.decode(String.self, forKey: Key("expectedScene"))
            batch = try fields.decode(SculptureCommandBatch.self, forKey: Key("batch"))
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }

    private struct Inspection: Encodable {
        let version = 1
        let kind: String
        let title: String
        let portableInput: Bool
        let revisionUTF8Bytes: Int
        let diagnostics: DocumentDiagnosticReport
        let modelIDs: [String]
        let placementCount: Int

        init(snapshot: SculptureThreeMDSnapshot, portableInput: Bool) {
            self.portableInput = portableInput
            title = snapshot.scene.title
            revisionUTF8Bytes = snapshot.revision.canonicalContent.utf8.count
            diagnostics = snapshot.diagnostics
            switch snapshot.scene {
            case .voxels: kind = "voxels"; modelIDs = []; placementCount = 0
            case .composition(let scene):
                kind = "composition"; modelIDs = scene.models.keys.sorted(); placementCount = 0
            case .world(let scene):
                kind = "world"; modelIDs = scene.library.models.keys.sorted(); placementCount = scene.instances.count
            }
        }
    }

    private struct Receipt: Encodable {
        let version = 1
        let action: String
        let output: String
        let title: String
        let bytes: Int
        let revisionUTF8Bytes: Int
        let diagnostics: DocumentDiagnosticReport

        init(action: String, output: String, snapshot: SculptureThreeMDSnapshot, bytes: Int) {
            self.action = action; self.output = output; self.bytes = bytes
            title = snapshot.scene.title
            revisionUTF8Bytes = snapshot.revision.canonicalContent.utf8.count
            diagnostics = snapshot.diagnostics
        }
    }

    private enum PortableToolError: LocalizedError {
        case usage, outputExtension, invalidPath, requestFields, requestVersion
        case diagnostic(DocumentDiagnostic)

        var errorDescription: String? {
            switch self {
            case .usage:
                "Usage: RookTool sculpture portable inspect INPUT | export INPUT OUTPUT.3md|OUTPUT.3mdb | apply INPUT REQUEST.json OUTPUT.3md|OUTPUT.3mdb | insert INPUT REQUEST.json OUTPUT.3md|OUTPUT.3mdb"
            case .outputExtension: "Portable output must use .3md or .3mdb."
            case .invalidPath: "File paths must be nonempty and contain no null byte."
            case .requestFields: "A portable request requires exactly version, modelID, expectedScene and batch."
            case .requestVersion: "Portable requests require version 1."
            case .diagnostic(let diagnostic):
                "\(diagnostic.code.rawValue)\(diagnostic.path.map { " at \($0)" } ?? "")\(diagnostic.sourceLine.map { " (line \($0))" } ?? ""): \(diagnostic.message)"
            }
        }
    }
}

/// Foundation decoding accepts duplicate keys. Reject them, including Unicode-equivalent spellings, before decoding.
struct PortableRequestJSON {
    let bytes: [UInt8]
    var index = 0

    static func validate(_ data: Data) throws {
        var scanner = Self(bytes: Array(data))
        try scanner.value(depth: 0)
        scanner.whitespace()
        guard scanner.index == scanner.bytes.count else { throw InvalidJSON() }
    }

    mutating func whitespace() {
        while index < bytes.count, [UInt8(9), 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    mutating func string() throws -> Range<Int> {
        whitespace()
        let start = index
        guard index < bytes.count, bytes[index] == 34 else { throw InvalidJSON() }
        index += 1
        while index < bytes.count {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let byte = bytes[index]
            index += 1
            if byte == 34 { return start..<index }
            if byte == 92 { index += 1 }
        }
        throw InvalidJSON()
    }

    mutating func value(depth: Int) throws {
        try Task.checkCancellation()
        guard depth <= 16 else { throw InvalidJSON() }
        whitespace()
        guard index < bytes.count else { throw InvalidJSON() }
        if consume(123) {
            var keys: Set<String> = []
            if consume(125) { return }
            repeat {
                let range = try string()
                let key = try JSONDecoder().decode(String.self, from: Data(bytes[range]))
                guard keys.insert(key).inserted, consume(58) else { throw InvalidJSON() }
                try value(depth: depth + 1)
                if consume(125) { return }
                guard consume(44) else { throw InvalidJSON() }
            } while true
        } else if consume(91) {
            if consume(93) { return }
            repeat {
                try value(depth: depth + 1)
                if consume(93) { return }
                guard consume(44) else { throw InvalidJSON() }
            } while true
        } else if bytes[index] == 34 {
            _ = try string()
        } else {
            let start = index
            while index < bytes.count, ![UInt8(9), 10, 13, 32, 44, 93, 125].contains(bytes[index]) {
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
                index += 1
            }
            guard start < index else { throw InvalidJSON() }
        }
    }

    private struct InvalidJSON: LocalizedError {
        var errorDescription: String? {
            "Portable request JSON is malformed, too deeply nested, or contains duplicate object keys."
        }
    }
}
