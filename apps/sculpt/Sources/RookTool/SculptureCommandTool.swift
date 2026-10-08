import Darwin
import Foundation
import RookSculpture

/// Development-only document commands. This adapter does not contact or control the running app.
internal enum SculptureCommandTool {
    static func run(arguments: [String], workingDirectory: URL) throws -> Data {
        guard let operation = arguments.first else { throw CommandToolError.usage }
        switch operation {
        case "inspect":
            guard arguments.count == 2 else { throw CommandToolError.usage }
            let input = try fileURL(arguments[1], relativeTo: workingDirectory)
            switch try readDocument(at: input) {
            case .sculpture(let sculpture):
                return try json(SculptureCommandEngine.inspect(sculpture))
            case .composition(let composition):
                return try json(CompositionInspection(composition: composition))
            case .world(let world):
                return try json(WorldInspection(world: world))
            }
        case "apply":
            guard arguments.count == 4 else { throw CommandToolError.usage }
            let input = try fileURL(arguments[1], relativeTo: workingDirectory)
            let commands = try fileURL(arguments[2], relativeTo: workingDirectory)
            let output = try fileURL(arguments[3], relativeTo: workingDirectory)
            let format = try storageFormat(for: output)
            let sculpture = try readSculpture(at: input)
            let batch = try readBatch(at: commands)
            let edited: Sculpture
            do {
                edited = try SculptureCommandEngine.apply(batch, to: sculpture)
            } catch {
                throw CommandToolError.commandFailed(describe(error))
            }
            let result = try json(
                ApplyResult(
                    output: output.path,
                    appliedCommandCount: batch.commands.count,
                    inspection: SculptureCommandEngine.inspect(edited)
                )
            )
            let document: Data
            do {
                document = try SculptureDocumentCodec.encode(edited, format: format)
            } catch {
                throw CommandToolError.outputFailure(output, describe(error))
            }
            try publishNewFile(document, at: output)
            return result
        case "compose":
            guard arguments.count == 3 else { throw CommandToolError.usage }
            let manifestURL = try fileURL(arguments[1], relativeTo: workingDirectory)
            let output = try fileURL(arguments[2], relativeTo: workingDirectory)
            guard output.pathExtension.lowercased() == "3md" else {
                throw CommandToolError.compositionOutputExtension(output)
            }
            let composition = try compose(at: manifestURL)
            let result = try json(
                CompositionResult(
                    output: output.path,
                    composition: CompositionInspection(composition: composition)
                )
            )
            let data: Data
            do {
                data = try SculptureCompositionCodec.encode(composition)
            } catch {
                throw CommandToolError.outputFailure(output, describe(error))
            }
            try publishNewFile(data, at: output)
            return result
        case "model":
            guard arguments.count == 4 else { throw CommandToolError.usage }
            let input = try fileURL(arguments[1], relativeTo: workingDirectory)
            let output = try fileURL(arguments[3], relativeTo: workingDirectory)
            let format = try storageFormat(for: output)
            guard case .world(let world) = try readDocument(at: input) else {
                throw CommandToolError.worldRequired(input)
            }
            let sculpture = try world.library.expanded(modelID: arguments[2])
            let data = try SculptureDocumentCodec.encode(sculpture, format: format)
            let result = try json(
                ModelResult(
                    output: output.path,
                    modelID: arguments[2],
                    inspection: SculptureCommandEngine.inspect(sculpture)
                )
            )
            try publishNewFile(data, at: output)
            return result
        case "expand":
            guard arguments.count == 3 else { throw CommandToolError.usage }
            let input = try fileURL(arguments[1], relativeTo: workingDirectory)
            let output = try fileURL(arguments[2], relativeTo: workingDirectory)
            let format = try storageFormat(for: output)
            guard case .composition(let composition) = try readDocument(at: input) else {
                throw CommandToolError.compositionRequired(input)
            }
            let expanded = try composition.expanded()
            let result = try json(
                ExpansionResult(
                    input: input.path,
                    output: output.path,
                    sourceModelCount: composition.models.count,
                    inspection: SculptureCommandEngine.inspect(expanded)
                )
            )
            let data: Data
            do {
                data = try SculptureDocumentCodec.encode(expanded, format: format)
            } catch {
                throw CommandToolError.outputFailure(output, describe(error))
            }
            try publishNewFile(data, at: output)
            return result
        default:
            throw CommandToolError.usage
        }
    }

    internal static func fileURL(_ path: String, relativeTo directory: URL) throws -> URL {
        guard !path.isEmpty, !path.utf8.contains(0) else { throw CommandToolError.usage }
        let base = URL(fileURLWithPath: directory.path, isDirectory: true)
        return URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
    }

    private static func readSculpture(at url: URL) throws -> Sculpture {
        switch try readDocument(at: url) {
        case .sculpture(let sculpture): return sculpture
        case .composition: throw CommandToolError.compositionRequiresExpansion(url)
        case .world: throw CommandToolError.worldRequiresModel(url)
        }
    }

    private static func readDocument(at url: URL) throws -> StoredDocument {
        let data = try readBoundedFile(at: url)
        if SculptureWorldCodec.isWorld(data) {
            do { return .world(try SculptureWorldCodec.decode(data)) } catch {
                throw CommandToolError.invalidWorld(url, describe(error))
            }
        }
        if SculptureCompositionCodec.isComposition(data) {
            do {
                return .composition(try SculptureCompositionCodec.decode(data))
            } catch {
                throw CommandToolError.invalidComposition(url, describe(error))
            }
        }
        // A linked root needs its project folder, which only the app reads. Its links are never followed here.
        try SculptureLinkedInput.refuseLinkedRoot(data, file: url.path)
        do {
            return .sculpture(try SculptureDocumentCodec.decode(data))
        } catch {
            try SculptureLinkedInput.refuseBinaryLinkedRoot(data, file: url.path)
            throw CommandToolError.invalidSculpture(url, describe(error))
        }
    }

    private static func compose(at url: URL) throws -> SculptureComposition {
        let data = try readBoundedFile(at: url, maximumBytes: SculptureCompositionCodec.maximumBytes)
        do {
            let manifest = try JSONDecoder().decode(CompositionManifest.self, from: data)
            try manifest.validate()
            let tileSize = try SculptureTileSize(
                width: manifest.tileWidth,
                height: manifest.tileHeight,
                depth: manifest.tileDepth
            )
            var imported: [String: SculptureCompositionModel] = [:]
            var decoded: [URL: StoredDocument] = [:]
            var usedIDs = Set(manifest.models.map(\.id))
            usedIDs.insert("root")
            for model in manifest.models {
                let source = try fileURL(model.path, relativeTo: url.deletingLastPathComponent())
                guard ["3md", "3mdb"].contains(source.pathExtension.lowercased()) else {
                    throw ManifestError("Model \(model.id) must explicitly choose a .3md or .3mdb file.")
                }
                let document: StoredDocument
                if let cached = decoded[source] {
                    document = cached
                } else {
                    document = try readDocument(at: source)
                    decoded[source] = document
                }
                switch document {
                case .sculpture(let sculpture):
                    imported[model.id] = .sculpture(sculpture)
                case .composition(let composition):
                    try importComposition(composition, as: model.id, into: &imported, usedIDs: &usedIDs)
                case .world: throw CommandToolError.worldRequiresModel(source)
                }
                try validateImportBudget(imported)
            }
            let bindings = try manifest.bindings.map {
                try SculptureModelBinding(
                    glyph: Array($0.glyph.utf8)[0],
                    modelID: $0.model,
                    quarterTurns: $0.quarterTurns
                )
            }
            let map = try SculptureTileMap(
                width: manifest.width,
                height: manifest.height,
                layers: manifest.layers.map { $0.flatMap { Array($0.utf8) } },
                tileSize: tileSize,
                bindings: bindings
            )
            imported["root"] = .tiles(map)
            let composition = try SculptureComposition(title: manifest.title, rootID: "root", models: imported)
            _ = try composition.expanded()
            return composition
        } catch {
            throw CommandToolError.invalidManifest(url, describe(error))
        }
    }

    /// Imported composition nodes remain self-contained. Only paths explicitly listed in the manifest are read.
    private static func importComposition(
        _ composition: SculptureComposition,
        as id: String,
        into models: inout [String: SculptureCompositionModel],
        usedIDs: inout Set<String>
    ) throws {
        var remapping = [composition.rootID: id]
        var nextID = 0
        for sourceID in composition.models.keys.sorted() where sourceID != composition.rootID {
            var targetID: String
            repeat {
                targetID = "part-\(nextID)"
                nextID += 1
            } while usedIDs.contains(targetID)
            usedIDs.insert(targetID)
            remapping[sourceID] = targetID
        }
        for sourceID in composition.models.keys.sorted() {
            guard let source = composition.models[sourceID], let targetID = remapping[sourceID] else {
                throw ManifestError("The imported composition has an unresolved model.")
            }
            switch source {
            case .sculpture(let sculpture):
                models[targetID] = .sculpture(sculpture)
            case .tiles(let map):
                let bindings = try map.bindings.map { binding in
                    guard let target = remapping[binding.modelID] else {
                        throw ManifestError("The imported composition has an unresolved binding.")
                    }
                    return try SculptureModelBinding(
                        glyph: binding.glyph,
                        modelID: target,
                        quarterTurns: binding.quarterTurns
                    )
                }
                models[targetID] = .tiles(
                    try SculptureTileMap(
                        width: map.width,
                        height: map.height,
                        layers: map.layers,
                        tileSize: map.tileSize,
                        bindings: bindings
                    )
                )
            }
        }
    }

    private static func validateImportBudget(_ models: [String: SculptureCompositionModel]) throws {
        guard models.count < SculptureComposition.maximumModels else {
            throw ManifestError("Use at most \(SculptureComposition.maximumModels) models including the root tile map.")
        }
        let voxelBytes = models.values.reduce(0) { count, model in
            switch model {
            case .sculpture(let sculpture): count + sculpture.width * sculpture.height * sculpture.depth
            case .tiles: count
            }
        }
        guard voxelBytes <= SculptureComposition.maximumResolvedVoxelBytes else {
            throw ManifestError("Imported leaf models must use at most 64 MiB of voxel storage in total.")
        }
    }

    internal static func storageFormat(for output: URL) throws -> SculptureStorageFormat {
        switch output.pathExtension.lowercased() {
        case "3md": return .readable
        case "3mdb": return .compact
        default: throw CommandToolError.unsupportedOutputExtension(output)
        }
    }

    private static func readBatch(at url: URL) throws -> SculptureCommandBatch {
        let data = try readBoundedFile(at: url, maximumBytes: 262_144)
        do {
            return try JSONDecoder().decode(SculptureCommandBatch.self, from: data)
        } catch {
            throw CommandToolError.invalidBatch(url, describe(error))
        }
    }

    private static func readBoundedFile(at url: URL, maximumBytes: Int = SculptureDocumentCodec.maximumBytes) throws
        -> Data
    {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw CommandToolError.readFailure(url, systemError()) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0 else {
            throw CommandToolError.readFailure(url, systemError())
        }
        guard information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw CommandToolError.readFailure(url, "Choose a regular file, not a directory, device, or pipe.")
        }
        guard information.st_size <= maximumBytes else {
            throw CommandToolError.readFailure(url, "Input files must be at most \(maximumBytes) bytes.")
        }
        var data = Data()
        do {
            while data.count <= maximumBytes {
                let chunk = try file.read(upToCount: min(65_536, maximumBytes + 1 - data.count)) ?? Data()
                if chunk.isEmpty { return data }
                data.append(chunk)
            }
        } catch {
            throw CommandToolError.readFailure(url, describe(error))
        }
        throw CommandToolError.readFailure(url, "Input files must be at most \(maximumBytes) bytes.")
    }

    /// Stage a complete document, then atomically publish a new hard link. linkat never replaces an existing entry.
    internal static func publishNewFile(_ data: Data, at output: URL) throws {
        let folder = output.deletingLastPathComponent()
        // Follow explicitly chosen directory aliases such as /tmp. All publication uses this opened directory FD.
        let folderDescriptor = Darwin.open(folder.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard folderDescriptor >= 0 else { throw CommandToolError.outputFailure(output, systemError()) }
        defer { Darwin.close(folderDescriptor) }
        let name = output.lastPathComponent
        var information = stat()
        if fstatat(folderDescriptor, name, &information, AT_SYMLINK_NOFOLLOW) == 0 {
            throw CommandToolError.outputExists(output)
        }
        guard errno == ENOENT else { throw CommandToolError.outputFailure(output, systemError()) }
        let stagingName = ".rook-command-\(UUID().uuidString).tmp"
        let stagingDescriptor = openat(
            folderDescriptor,
            stagingName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard stagingDescriptor >= 0 else { throw CommandToolError.outputFailure(output, systemError()) }
        defer { unlinkat(folderDescriptor, stagingName, 0) }
        let file = FileHandle(fileDescriptor: stagingDescriptor, closeOnDealloc: true)
        defer { try? file.close() }
        do {
            try file.write(contentsOf: data)
            try file.synchronize()
            try file.close()
        } catch {
            throw CommandToolError.outputFailure(output, describe(error))
        }
        guard linkat(folderDescriptor, stagingName, folderDescriptor, name, 0) == 0 else {
            if errno == EEXIST { throw CommandToolError.outputExists(output) }
            throw CommandToolError.outputFailure(output, systemError())
        }
    }

    internal static func json(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(10)
        return data
    }

    private static func systemError() -> String { String(cString: strerror(errno)) }

    private static func describe(_ error: any Error) -> String {
        if let error = error as? DecodingError {
            let context: DecodingError.Context
            switch error {
            case .dataCorrupted(let value), .keyNotFound(_, let value), .typeMismatch(_, let value),
                .valueNotFound(_, let value):
                context = value
            @unknown default: return error.localizedDescription
            }
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return context.debugDescription + (path.isEmpty ? "" : " At \(path).")
        }
        return error.localizedDescription
    }

    private struct ApplyResult: Encodable {
        let version = 1
        let operation = "apply"
        let output: String
        let appliedCommandCount: Int
        let inspection: SculptureInspection
    }

    private enum StoredDocument {
        case sculpture(Sculpture)
        case composition(SculptureComposition)
        case world(SculptureWorld)
    }

    private struct ModelResult: Encodable {
        let version = 1
        let operation = "model"
        let output: String
        let modelID: String
        let inspection: SculptureInspection
    }

    private struct WorldInspection: Encodable {
        let version = 1
        let mode = "sparse-world"
        let coordinateEncoding = "signed Int64 decimal strings"
        let title: String
        let modelCount: Int
        let instanceCount: Int
        let instances: [WorldInstanceInspection]

        init(world: SculptureWorld) {
            title = world.title
            modelCount = world.library.models.count
            instanceCount = world.instances.count
            instances = world.instances.map {
                WorldInstanceInspection(
                    id: $0.id,
                    modelID: $0.modelID,
                    x: String($0.origin.x),
                    y: String($0.origin.y),
                    z: String($0.origin.z),
                    quarterTurns: $0.quarterTurns
                )
            }
        }
    }

    private struct WorldInstanceInspection: Encodable {
        let id: String
        let modelID: String
        let x: String
        let y: String
        let z: String
        let quarterTurns: Int
    }

    private struct CompositionResult: Encodable {
        let version = 1
        let operation = "compose"
        let output: String
        let composition: CompositionInspection
    }

    private struct ExpansionResult: Encodable {
        let version = 1
        let operation = "expand"
        let input: String
        let output: String
        let sourceModelCount: Int
        let inspection: SculptureInspection
    }

    private struct CompositionInspection: Encodable {
        let version = 1
        let mode = "composition"
        let title: String
        let rootID: String
        let modelCount: Int
        let root: TileMapInspection
        let expanded: SculptureInspection

        init(composition: SculptureComposition) throws {
            guard case .tiles(let map)? = composition.models[composition.rootID] else {
                throw ManifestError("A composition needs a tile map at its root.")
            }
            title = composition.title
            rootID = composition.rootID
            modelCount = composition.models.count
            root = TileMapInspection(map: map)
            expanded = SculptureCommandEngine.inspect(try composition.expanded())
        }
    }

    private struct TileMapInspection: Encodable {
        let coordinateBase = 0
        let width: Int
        let height: Int
        let depth: Int
        let tileSize: TileSizeInspection
        let layers: [[String]]
        let bindings: [BindingInspection]

        init(map: SculptureTileMap) {
            width = map.width
            height = map.height
            depth = map.depth
            tileSize = TileSizeInspection(
                width: map.tileSize.width,
                height: map.tileSize.height,
                depth: map.tileSize.depth
            )
            layers = map.layers.map { layer in
                (0..<map.height).map { row in
                    String(decoding: layer[row * map.width..<(row + 1) * map.width], as: UTF8.self)
                }
            }
            bindings = map.bindings.map {
                BindingInspection(
                    glyph: String(decoding: [$0.glyph], as: UTF8.self),
                    modelID: $0.modelID,
                    quarterTurns: $0.quarterTurns
                )
            }
        }
    }

    private struct TileSizeInspection: Encodable {
        let width: Int
        let height: Int
        let depth: Int
    }

    private struct BindingInspection: Encodable {
        let glyph: String
        let modelID: String
        let quarterTurns: Int
    }

    private struct CompositionManifest: Decodable {
        let version: Int
        let title: String
        let width: Int
        let height: Int
        let tileWidth: Int
        let tileHeight: Int
        let tileDepth: Int
        let layers: [[String]]
        let bindings: [ManifestBinding]
        let models: [ManifestModel]

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case version, title, width, height, tileWidth, tileHeight, tileDepth, layers, bindings, models
        }

        init(from decoder: any Decoder) throws {
            try rejectUnknownFields(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            version = try fields.decode(Int.self, forKey: .version)
            title = try fields.decode(String.self, forKey: .title)
            width = try fields.decode(Int.self, forKey: .width)
            height = try fields.decode(Int.self, forKey: .height)
            tileWidth = try fields.decode(Int.self, forKey: .tileWidth)
            tileHeight = try fields.decode(Int.self, forKey: .tileHeight)
            tileDepth = try fields.decode(Int.self, forKey: .tileDepth)
            layers = try fields.decode([[String]].self, forKey: .layers)
            bindings = try fields.decode([ManifestBinding].self, forKey: .bindings)
            models = try fields.decode([ManifestModel].self, forKey: .models)
        }

        func validate() throws {
            guard version == 1 else { throw ManifestError("Use composition manifest version 1.") }
            guard !title.isEmpty, title.utf8.count <= 80, title.utf8.allSatisfy({ (32...126).contains($0) }) else {
                throw ManifestError("Use a title of 1–80 printable ASCII characters.")
            }
            let range = 1...Sculpture.maximumDimension
            guard range.contains(width), range.contains(height), range.contains(layers.count),
                range.contains(tileWidth), range.contains(tileHeight), range.contains(tileDepth),
                width * tileWidth <= Sculpture.maximumDimension,
                height * tileHeight <= Sculpture.maximumDimension,
                layers.count * tileDepth <= Sculpture.maximumDimension
            else { throw ManifestError("Tile map and expanded dimensions must fit the sculpture volume.") }
            guard
                layers.allSatisfy({ layer in
                    layer.count == height
                        && layer.allSatisfy { $0.utf8.count == width && $0.utf8.allSatisfy { (32...126).contains($0) } }
                })
            else {
                throw ManifestError("Each Z layer needs exactly height rows of width printable ASCII characters.")
            }
            guard models.count < SculptureComposition.maximumModels else {
                throw ManifestError("The manifest must leave one model slot for its root tile map.")
            }
            var ids = Set<String>()
            for model in models {
                guard Self.validModelID(model.id), model.id != "root" else {
                    throw ManifestError(
                        "Model IDs use 1–48 ASCII letters, digits, underscores or hyphens; root is reserved."
                    )
                }
                guard ids.insert(model.id).inserted else { throw ManifestError("Duplicate model ID \(model.id).") }
                guard !model.path.isEmpty, !model.path.utf8.contains(0) else {
                    throw ManifestError("Every model needs an explicit file path.")
                }
            }
            var glyphs = Set<UInt8>()
            for binding in bindings {
                let bytes = Array(binding.glyph.utf8)
                guard bytes.count == 1, let glyph = bytes.first, (32...126).contains(glyph), glyph != Sculpture.empty
                else {
                    throw ManifestError("Binding glyphs must be one printable ASCII character other than a period.")
                }
                guard glyphs.insert(glyph).inserted else {
                    throw ManifestError("Duplicate binding glyph \(binding.glyph).")
                }
                guard ids.contains(binding.model) else {
                    throw ManifestError("Binding \(binding.glyph) refers to an unlisted model \(binding.model).")
                }
                guard (0...3).contains(binding.quarterTurns) else {
                    throw ManifestError("quarterTurns must be 0, 1, 2 or 3 clockwise turns.")
                }
            }
        }

        private static func validModelID(_ value: String) -> Bool {
            let bytes = Array(value.utf8)
            let alphanumeric: (UInt8) -> Bool = {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
            }
            guard (1...48).contains(bytes.count), let first = bytes.first, alphanumeric(first) else { return false }
            return bytes.allSatisfy { alphanumeric($0) || $0 == 45 || $0 == 95 }
        }
    }

    private struct ManifestBinding: Decodable {
        let glyph: String
        let model: String
        let quarterTurns: Int

        private enum CodingKeys: String, CodingKey, CaseIterable { case glyph, model, quarterTurns }

        init(from decoder: any Decoder) throws {
            try rejectUnknownFields(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            glyph = try fields.decode(String.self, forKey: .glyph)
            model = try fields.decode(String.self, forKey: .model)
            quarterTurns = try fields.decode(Int.self, forKey: .quarterTurns)
        }
    }

    private struct ManifestModel: Decodable {
        let id: String
        let path: String

        private enum CodingKeys: String, CodingKey, CaseIterable { case id, path }

        init(from decoder: any Decoder) throws {
            try rejectUnknownFields(in: decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            id = try fields.decode(String.self, forKey: .id)
            path = try fields.decode(String.self, forKey: .path)
        }
    }

    private struct ManifestKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private static func rejectUnknownFields(in decoder: any Decoder, allowed: Set<String>) throws {
        let fields = try decoder.container(keyedBy: ManifestKey.self)
        let unknown = fields.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown fields: \(unknown.joined(separator: ", "))."
                )
            )
        }
    }

    private struct ManifestError: Error, LocalizedError {
        let reason: String
        init(_ reason: String) { self.reason = reason }
        var errorDescription: String? { reason }
    }

    private enum CommandToolError: Error, CustomStringConvertible, LocalizedError {
        case usage
        case readFailure(URL, String)
        case invalidSculpture(URL, String)
        case invalidComposition(URL, String)
        case invalidWorld(URL, String)
        case invalidManifest(URL, String)
        case invalidBatch(URL, String)
        case commandFailed(String)
        case compositionRequiresExpansion(URL)
        case compositionRequired(URL)
        case worldRequired(URL), worldRequiresModel(URL)
        case compositionOutputExtension(URL)
        case unsupportedOutputExtension(URL)
        case outputExists(URL)
        case outputFailure(URL, String)

        var errorDescription: String? { description }

        var description: String {
            switch self {
            case .usage:
                "Usage: RookTool sculpture inspect INPUT | sculpture apply INPUT COMMANDS.json NEW.3md|NEW.3mdb | sculpture compose MANIFEST.json NEW.3md | sculpture expand COMPOSITION.3md NEW.3md|NEW.3mdb | sculpture model WORLD.3md MODEL_ID NEW.3md|NEW.3mdb | sculpture math ENTRY_ID NEW.3md|NEW.3mdb"
            case .readFailure(let file, let reason): "Cannot read \(file.path): \(reason)"
            case .invalidSculpture(let file, let reason): "Invalid sculpture \(file.path): \(reason)"
            case .invalidComposition(let file, let reason): "Invalid composition \(file.path): \(reason)"
            case .invalidWorld(let file, let reason): "Invalid sparse world \(file.path): \(reason)"
            case .invalidManifest(let file, let reason): "Invalid composition manifest \(file.path): \(reason)"
            case .invalidBatch(let file, let reason): "Invalid command batch \(file.path): \(reason)"
            case .commandFailed(let reason): "No commands were written: \(reason)"
            case .compositionRequiresExpansion(let file):
                "Cannot apply voxel edits to composition \(file.path). Use sculpture expand first, then apply to the new flattened file."
            case .compositionRequired(let file):
                "sculpture expand requires a composition document within voxel bounds; \(file.path) is another document type."
            case .worldRequired(let file): "sculpture model requires a sparse world document: \(file.path)."
            case .worldRequiresModel(let file):
                "Cannot flatten sparse world \(file.path). Use sculpture model WORLD MODEL_ID NEW.3md to extract a bounded model first."
            case .compositionOutputExtension(let file):
                "Composition output \(file.path) must use .3md. Use sculpture expand for a flattened .3mdb file."
            case .unsupportedOutputExtension(let file):
                "Unsupported output extension at \(file.path). Choose .3md for readable text or .3mdb for compact storage."
            case .outputExists(let file):
                "Refusing existing output or symbolic link at \(file.path). Choose a new output file."
            case .outputFailure(let file, let reason): "Cannot publish \(file.path): \(reason)"
            }
        }
    }
}
