import Darwin
import Foundation
import RookSculpture

/// Explicit-file shared-model edits. The native app uses the same pure model replacement values.
internal enum SculptureReferenceModelTool {
    static let maximumRequestBytes = 262_144

    static func run(arguments: [String], workingDirectory: URL) throws -> Data {
        try Task.checkCancellation()
        guard let operation = arguments.first else { throw ReferenceToolError.usage }
        switch operation {
        case "inspect":
            guard (2...3).contains(arguments.count) else { throw ReferenceToolError.usage }
            let input = try fileURL(arguments[1], relativeTo: workingDirectory)
            let source = try readFile(at: input)
            let document = try readDocument(source, at: input)
            return try json(Inspection(document: document, modelID: arguments.count == 3 ? arguments[2] : nil))
        case "apply":
            guard arguments.count == 4 else { throw ReferenceToolError.usage }
            let input = try fileURL(arguments[1], relativeTo: workingDirectory)
            let requestURL = try fileURL(arguments[2], relativeTo: workingDirectory)
            let output = try fileURL(arguments[3], relativeTo: workingDirectory)
            guard output.pathExtension.lowercased() == "3md" else {
                throw ReferenceToolError.readableOutputRequired(output)
            }
            let source = try readFile(at: input)
            let document = try readDocument(source, at: input)
            let request = try JSONDecoder().decode(
                Request.self,
                from: readFile(at: requestURL, maximumBytes: maximumRequestBytes)
            )
            let edited: ReferenceDocument
            let changedModelID: String
            let count: Int
            switch request.operation {
            case .editModel(let modelID, let expectedPath, let batch):
                let expectedURL = try fileURL(expectedPath, relativeTo: requestURL.deletingLastPathComponent())
                let expected = try expectedModel(at: expectedURL)
                let current = try document.voxelModel(modelID)
                guard current == expected else { throw SculptureModelEditingError.expectedModelChanged(modelID) }
                var replacement = current
                for command in batch.commands {
                    try Task.checkCancellation()
                    replacement = try SculptureCommandEngine.apply(command, to: replacement)
                }
                switch document {
                case .composition(let composition):
                    edited = .composition(
                        try SculptureModelEditing.replacingVoxelModel(
                            in: composition,
                            modelID: modelID,
                            expected: expected,
                            with: replacement
                        )
                    )
                case .world(let world):
                    edited = .world(
                        try SculptureModelEditing.replacingVoxelModel(
                            in: world,
                            modelID: modelID,
                            expected: expected,
                            with: replacement
                        )
                    )
                }
                changedModelID = modelID
                count = batch.commands.count
            case .makeUnique(let instanceID, let newModelID, let expectedPath):
                guard case .world(let world) = document else { throw ReferenceToolError.worldRequired }
                let expectedURL = try fileURL(expectedPath, relativeTo: requestURL.deletingLastPathComponent())
                guard try readFile(at: expectedURL) == source else { throw ReferenceToolError.sourceChanged }
                edited = .world(
                    try SculptureModelEditing.makingUnique(in: world, instanceID: instanceID, newModelID: newModelID)
                )
                changedModelID = newModelID
                count = 0
            }
            try Task.checkCancellation()
            let data = try edited.encoded()
            let result = try json(
                ApplyResult(
                    action: request.action,
                    output: output.path,
                    modelID: changedModelID,
                    appliedCommandCount: count,
                    inspection: try Inspection(document: edited, modelID: nil)
                )
            )
            try publishNewFile(data, at: output)
            return result
        case "insert":
            return try SculptureInsertTool.runReference(
                arguments: Array(arguments.dropFirst()),
                workingDirectory: workingDirectory
            )
        default:
            throw ReferenceToolError.usage
        }
    }

    private enum ReferenceDocument {
        case composition(SculptureComposition)
        case world(SculptureWorld)

        var library: SculptureComposition {
            switch self {
            case .composition(let value): value
            case .world(let value): value.library
            }
        }

        func voxelModel(_ id: String) throws -> Sculpture {
            guard let model = library.models[id] else { throw SculptureCompositionError.unknownModel(id) }
            guard case .sculpture(let sculpture) = model else {
                throw SculptureModelEditingError.voxelModelRequired(id)
            }
            return sculpture
        }

        func encoded() throws -> Data {
            switch self {
            case .composition(let value): try SculptureCompositionCodec.encode(value)
            case .world(let value): try SculptureWorldCodec.encode(value)
            }
        }
    }

    private static func readDocument(_ data: Data, at url: URL) throws -> ReferenceDocument {
        if SculptureWorldCodec.isWorld(data) { return .world(try SculptureWorldCodec.decode(data)) }
        if SculptureCompositionCodec.isComposition(data) {
            return .composition(try SculptureCompositionCodec.decode(data))
        }
        // A linked root is not self-contained. Name it rather than asking for another document type.
        try SculptureLinkedInput.refuseLinkedRoot(data, file: url.path)
        try SculptureLinkedInput.refuseBinaryLinkedRoot(data, file: url.path)
        throw ReferenceToolError.referenceDocumentRequired(url)
    }

    /// Decodes an expected voxel model snapshot. A linked root is refused naming the file.
    private static func expectedModel(at url: URL) throws -> Sculpture {
        let data = try readFile(at: url)
        try SculptureLinkedInput.refuseLinkedRoot(data, file: url.path)
        do { return try SculptureDocumentCodec.decode(data) } catch {
            try SculptureLinkedInput.refuseBinaryLinkedRoot(data, file: url.path)
            throw error
        }
    }

    private struct Inspection: Encodable {
        let version = 1
        let operation = "reference.inspect"
        let mode: String
        let title: String
        let rootID: String
        let models: [ModelInspection]
        let instances: [InstanceInspection]?
        let selectedModelID: String?
        let modelSource: String?

        init(document: ReferenceDocument, modelID: String?) throws {
            let library = document.library
            rootID = library.rootID
            models = try library.models.keys.sorted().map { id in
                try Task.checkCancellation()
                guard let model = library.models[id] else { throw SculptureCompositionError.unknownModel(id) }
                switch model {
                case .sculpture(let value):
                    return ModelInspection(
                        id: id,
                        kind: "voxel",
                        width: value.width,
                        height: value.height,
                        depth: value.depth,
                        inspection: SculptureCommandEngine.inspect(value)
                    )
                case .tiles(let value):
                    return ModelInspection(
                        id: id,
                        kind: "tiles",
                        width: value.width * value.tileSize.width,
                        height: value.height * value.tileSize.height,
                        depth: value.depth * value.tileSize.depth,
                        inspection: nil
                    )
                }
            }
            switch document {
            case .composition(let composition):
                mode = "composition"
                title = composition.title
                instances = nil
            case .world(let world):
                mode = "sparse-world"
                title = world.title
                instances = try world.instances.map { value in
                    try Task.checkCancellation()
                    return InstanceInspection(
                        id: value.id,
                        modelID: value.modelID,
                        x: String(value.origin.x),
                        y: String(value.origin.y),
                        z: String(value.origin.z),
                        quarterTurns: value.quarterTurns
                    )
                }
            }
            selectedModelID = modelID
            modelSource = try modelID.map {
                String(decoding: SculptureCodec.encode(try document.voxelModel($0)), as: UTF8.self)
            }
        }
    }

    private struct ModelInspection: Encodable {
        let id: String
        let kind: String
        let width: Int
        let height: Int
        let depth: Int
        let inspection: SculptureInspection?
    }

    private struct InstanceInspection: Encodable {
        let id: String
        let modelID: String
        let x: String
        let y: String
        let z: String
        let quarterTurns: Int
    }

    private struct ApplyResult: Encodable {
        let version = 1
        let operation = "reference.apply"
        let action: String
        let output: String
        let modelID: String
        let appliedCommandCount: Int
        let inspection: Inspection
    }

    private struct Request: Decodable {
        enum Operation {
            case editModel(modelID: String, expectedModel: String, batch: SculptureCommandBatch)
            case makeUnique(instanceID: String, newModelID: String, expectedSource: String)
        }

        let action: String
        let operation: Operation

        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: RequestKey.self)
            let version = try fields.decode(Int.self, forKey: RequestKey("version"))
            guard version == 1 else { throw ReferenceToolError.unsupportedVersion(version) }
            action = try fields.decode(String.self, forKey: RequestKey("action"))
            let allowed: Set<String>
            switch action {
            case "editModel":
                allowed = ["version", "action", "modelID", "expectedModel", "batch"]
                operation = .editModel(
                    modelID: try fields.decode(String.self, forKey: RequestKey("modelID")),
                    expectedModel: try fields.decode(String.self, forKey: RequestKey("expectedModel")),
                    batch: try fields.decode(SculptureCommandBatch.self, forKey: RequestKey("batch"))
                )
            case "makeUnique":
                allowed = ["version", "action", "instanceID", "newModelID", "expectedSource"]
                operation = .makeUnique(
                    instanceID: try fields.decode(String.self, forKey: RequestKey("instanceID")),
                    newModelID: try fields.decode(String.self, forKey: RequestKey("newModelID")),
                    expectedSource: try fields.decode(String.self, forKey: RequestKey("expectedSource"))
                )
            default: throw ReferenceToolError.unknownAction(action)
            }
            let extra = Set(fields.allKeys.map(\.stringValue)).subtracting(allowed)
            guard extra.isEmpty else { throw ReferenceToolError.unexpectedFields(extra.sorted()) }
        }
    }

    private struct RequestKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }

    private static func fileURL(_ path: String, relativeTo directory: URL) throws -> URL {
        guard !path.isEmpty, !path.utf8.contains(0) else { throw ReferenceToolError.usage }
        let base = URL(fileURLWithPath: directory.path, isDirectory: true)
        return URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
    }

    static func readFile(at url: URL, maximumBytes: Int = SculptureCompositionCodec.maximumBytes) throws -> Data {
        try Task.checkCancellation()
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw ReferenceToolError.readFailure(url, systemError()) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0 else { throw ReferenceToolError.readFailure(url, systemError()) }
        guard information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw ReferenceToolError.readFailure(url, "Choose a regular file, not a directory, device, or pipe.")
        }
        guard information.st_size <= maximumBytes else {
            throw ReferenceToolError.readFailure(url, "Input files must be at most \(maximumBytes) bytes.")
        }
        var data = Data()
        while data.count <= maximumBytes {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount: min(65_536, maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw ReferenceToolError.readFailure(url, "Input files must be at most \(maximumBytes) bytes.")
    }

    /// Publish through the chosen directory descriptor. A racing entry or symbolic link is never replaced.
    static func publishNewFile(_ data: Data, at output: URL) throws {
        try Task.checkCancellation()
        let folderDescriptor = Darwin.open(output.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard folderDescriptor >= 0 else { throw ReferenceToolError.outputFailure(output, systemError()) }
        defer { Darwin.close(folderDescriptor) }
        let name = output.lastPathComponent
        var information = stat()
        if fstatat(folderDescriptor, name, &information, AT_SYMLINK_NOFOLLOW) == 0 {
            throw ReferenceToolError.outputExists(output)
        }
        guard errno == ENOENT else { throw ReferenceToolError.outputFailure(output, systemError()) }
        let stagingName = ".rook-reference-\(UUID().uuidString).tmp"
        let descriptor = openat(
            folderDescriptor,
            stagingName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw ReferenceToolError.outputFailure(output, systemError()) }
        defer { unlinkat(folderDescriptor, stagingName, 0) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        try Task.checkCancellation()
        try file.write(contentsOf: data)
        try file.synchronize()
        try file.close()
        try Task.checkCancellation()
        guard linkat(folderDescriptor, stagingName, folderDescriptor, name, 0) == 0 else {
            if errno == EEXIST { throw ReferenceToolError.outputExists(output) }
            throw ReferenceToolError.outputFailure(output, systemError())
        }
    }

    private static func json(_ value: some Encodable) throws -> Data {
        try Task.checkCancellation()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(10)
        try Task.checkCancellation()
        return data
    }

    private static func systemError() -> String { String(cString: strerror(errno)) }

    private enum ReferenceToolError: Error, LocalizedError {
        case usage, worldRequired, sourceChanged
        case referenceDocumentRequired(URL), readableOutputRequired(URL)
        case unsupportedVersion(Int), unknownAction(String), unexpectedFields([String])
        case readFailure(URL, String), outputFailure(URL, String), outputExists(URL)

        var errorDescription: String? {
            switch self {
            case .usage:
                "Usage: RookTool sculpture reference inspect INPUT.3md [MODEL_ID] | sculpture reference apply INPUT.3md REQUEST.json NEW.3md | sculpture reference insert INPUT.3md REQUEST.json NEW.3md"
            case .worldRequired: "makeUnique requires a sparse world document."
            case .sourceChanged:
                "The supplied expectedSource bytes differ from the input world. Inspect the current file first."
            case .referenceDocumentRequired(let url):
                "Choose a self-contained composition or sparse world document: \(url.path)."
            case .readableOutputRequired(let url): "Reference-preserving output must use .3md: \(url.path)."
            case .unsupportedVersion(let version): "Reference request version \(version) is unsupported. Use version 1."
            case .unknownAction(let action): "Unknown reference action '\(action)'. Use editModel or makeUnique."
            case .unexpectedFields(let fields):
                "Unexpected reference request fields: \(fields.joined(separator: ", "))."
            case .readFailure(let url, let reason): "Cannot read \(url.path): \(reason)"
            case .outputFailure(let url, let reason): "Cannot publish \(url.path): \(reason)"
            case .outputExists(let url):
                "Refusing existing output or symbolic link at \(url.path). Choose a new output file."
            }
        }
    }
}
