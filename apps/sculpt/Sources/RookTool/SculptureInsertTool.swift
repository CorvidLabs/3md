import Darwin
import Foundation
import RookSculpture
import ThreeMD

/// Explicit-file insertion for people and agents. The request names every file; nothing is discovered or followed.
/// It applies the same capacity, fit, overwrite and native-budget rules as the app and never controls the app.
internal enum SculptureInsertTool {
    static let maximumRequestBytes = 262_144

    /// `portable insert INPUT REQUEST.json OUTPUT.3md|OUTPUT.3mdb`: portable input and output with identities kept.
    /// A native INPUT has no portable data to keep, so it is treated as a parent with none and its result is captured
    /// fresh. Nothing is written when the result cannot be portable.
    static func runPortable(arguments: [String], workingDirectory: URL) throws -> Data {
        guard arguments.count == 3 else { throw InsertToolError.usage(.portable) }
        let output = try SculpturePortableTool.url(arguments[2], relativeTo: workingDirectory)
        guard ["3md", "3mdb"].contains(output.pathExtension.lowercased()) else {
            throw InsertToolError.outputExtension(.portable)
        }
        try requireNewOutput(output)
        let parent = try decodeSnapshot(
            at: SculpturePortableTool.url(arguments[0], relativeTo: workingDirectory),
            named: arguments[0]
        )
        let requestURL = try SculpturePortableTool.url(arguments[1], relativeTo: workingDirectory)
        let request = try loadRequest(at: requestURL)
        guard let expectedPath = request.expectedScene else { throw InsertToolError.expectedSceneRequired }
        let expected = try decodeSnapshot(
            at: SculpturePortableTool.url(expectedPath, relativeTo: requestURL.deletingLastPathComponent()),
            named: expectedPath
        )
        // The complete exact revision is checked before any file is read or any model is placed.
        guard parent.snapshot.revision == expected.snapshot.revision else {
            throw DocumentEditError(
                .init(
                    code: .staleRevision,
                    message: "The scene differs from expectedScene.",
                    path: "expectedRevision"
                )
            )
        }
        let insertion = try insert(
            into: parent.snapshot.scene,
            preserving: parent.carriesPortableData ? parent.snapshot : nil,
            request: request,
            requestURL: requestURL,
            command: .portable
        )
        let snapshot = try portableSnapshot(of: insertion.result)
        let data = try SculpturePortableTool.encode(snapshot, to: output)
        let receipt = try SculpturePortableTool.json(
            Receipt(
                output: output.path,
                insertion: insertion,
                storage: "portable",
                bytes: data.count,
                revisionUTF8Bytes: snapshot.revision.canonicalContent.utf8.count,
                diagnostics: snapshot.diagnostics,
                portableDataNotCarried: nil
            )
        )
        try SculptureReferenceModelTool.publishNewFile(data, at: output)
        return receipt
    }

    /// `reference insert INPUT REQUEST.json NEW.3md`: native readable composition or world output. Portable data
    /// on listed children is not carried into a native file, and the receipt names those files.
    static func runReference(arguments: [String], workingDirectory: URL) throws -> Data {
        guard arguments.count == 3 else { throw InsertToolError.usage(.reference) }
        let output = try SculpturePortableTool.url(arguments[2], relativeTo: workingDirectory)
        guard output.pathExtension.lowercased() == "3md" else { throw InsertToolError.outputExtension(.reference) }
        try requireNewOutput(output)
        let input = try SculpturePortableTool.url(arguments[0], relativeTo: workingDirectory)
        let parent = try nativeScene(SculpturePortableTool.read(input), at: input, named: arguments[0])
        let requestURL = try SculpturePortableTool.url(arguments[1], relativeTo: workingDirectory)
        let request = try loadRequest(at: requestURL)
        guard request.expectedScene == nil else { throw InsertToolError.expectedSceneNotAllowed }
        let insertion = try insert(
            into: parent,
            preserving: nil,
            request: request,
            requestURL: requestURL,
            command: .reference
        )
        let data: Data
        switch insertion.result.scene {
        case .composition(let composition): data = try SculptureCompositionCodec.encode(composition)
        case .world(let world): data = try SculptureWorldCodec.encode(world)
        case .voxels: throw InsertToolError.sceneKind
        }
        let receipt = try SculpturePortableTool.json(
            Receipt(
                output: output.path,
                insertion: insertion,
                storage: "native",
                bytes: data.count,
                revisionUTF8Bytes: nil,
                diagnostics: nil,
                portableDataNotCarried: zip(insertion.files, insertion.inputs).filter { $0.1.snapshot != nil }.map(\.0)
            )
        )
        try SculptureReferenceModelTool.publishNewFile(data, at: output)
        return receipt
    }

    /// Decodes a file and names it in every refusal. A native file has no portable data, so it is captured fresh.
    private static func decodeSnapshot(
        at url: URL,
        named name: String
    ) throws -> (snapshot: SculptureThreeMDSnapshot, carriesPortableData: Bool) {
        let data = try SculpturePortableTool.read(url)
        do {
            let opened = try SculptureSceneReader.decode(data)
            if let snapshot = opened.snapshot { return (snapshot, true) }
            return (try SculptureThreeMDCodec.capture(opened.scene), false)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SculptureLinkedError {
            throw SculptureLinkedInput.naming(error, file: name)
        } catch let error where SculptureThreeMDCodec.isCapacityError(error) {
            throw SculptureInsertionError.source(
                name: name,
                reason:
                    "This native file is too large to be copied as portable ThreeMD. Use sculpture reference insert to write a native result."
            )
        } catch {
            throw SculptureInsertionError.source(name: name, reason: SculptureDiagnosticMessage.describe(error))
        }
    }

    /// A portable insertion always yields a snapshot unless the portable limit forced native values.
    private static func portableSnapshot(of result: SculptureInsertionResult) throws -> SculptureThreeMDSnapshot {
        if let snapshot = result.snapshot { return snapshot }
        guard !result.usedNativeFallback else { throw InsertToolError.portableOutputUnavailable }
        do { return try SculptureThreeMDCodec.capture(result.scene) } catch let error
            where SculptureThreeMDCodec.isCapacityError(error)
        {
            throw InsertToolError.portableOutputUnavailable
        }
    }

    // MARK: - Insertion

    private struct Insertion {
        let result: SculptureInsertionResult
        let inputs: [SculptureInsertionInput]
        let files: [String]
        let cells: [SculptureInsertionTarget]
    }

    /// Places the listed files with the app's rules. A portable parent keeps its identities and metadata.
    private static func insert(
        into scene: SculptureScene,
        preserving snapshot: SculptureThreeMDSnapshot?,
        request: Request,
        requestURL: URL,
        command: Command
    ) throws -> Insertion {
        switch (scene, request.target) {
        case (.composition(let parent), .cell(let cell)):
            var plan = try SculptureInsertionPlan(composition: parent, at: cell)
            // Count, cell and glyph limits and overwrite permission are decided before any file is read.
            try plan.admitFileCount(request.files.count)
            let cells = try SculptureSceneInsertion.targets(in: parent, count: request.files.count, at: cell)
            let occupied = cells.filter(\.isOccupied)
            if !occupied.isEmpty && !request.replaceOccupied {
                throw InsertToolError.occupied(
                    occupied.map { "\(location(of: $0.cell)) holds \(String(UnicodeScalar($0.currentGlyph)))" }
                )
            }
            let inputs = try readSources(request, requestURL: requestURL, plan: &plan)
            let result = try refusingByFile(request.files) {
                command == .reference
                    ? try SculptureSceneInsertion.intoCompositionNatively(parent, inputs: inputs, at: cell)
                    : try SculptureSceneInsertion.intoComposition(
                        parent,
                        preserving: snapshot,
                        inputs: inputs,
                        at: cell
                    )
            }
            return Insertion(result: result, inputs: inputs, files: request.files, cells: cells)
        case (.world(let parent), .focus(let focus)):
            var plan = SculptureInsertionPlan(world: parent)
            try plan.admitFileCount(request.files.count)
            let inputs = try readSources(request, requestURL: requestURL, plan: &plan)
            let result = try refusingByFile(request.files) {
                command == .reference
                    ? try SculptureSceneInsertion.intoWorldNatively(parent, inputs: inputs, at: focus)
                    : try SculptureSceneInsertion.intoWorld(parent, preserving: snapshot, inputs: inputs, at: focus)
            }
            return Insertion(result: result, inputs: inputs, files: request.files, cells: [])
        case (.composition, .focus):
            throw InsertToolError.targetKind("A composition places models in tiles. Use \"cell\".")
        case (.world, .cell):
            throw InsertToolError.targetKind("A sparse world places models at a position. Use \"focus\".")
        case (.voxels, _): throw InsertToolError.sceneKind
        }
    }

    /// Reads the listed files in request order. Each is size-checked before it is read and fit-checked after it
    /// is decoded, so an oversized batch is refused by filename before the remaining files are touched.
    private static func readSources(
        _ request: Request,
        requestURL: URL,
        plan: inout SculptureInsertionPlan
    ) throws -> [SculptureInsertionInput] {
        let directory = requestURL.deletingLastPathComponent()
        var inputs: [SculptureInsertionInput] = []
        for path in request.files {
            try Task.checkCancellation()
            let url = try SculpturePortableTool.url(path, relativeTo: directory)
            let data = try readSource(url, named: path, plan: &plan)
            // A linked child would need its own project folder. Its links are never followed here.
            try SculptureLinkedInput.refuseLinkedRoot(data, file: path)
            inputs.append(try plan.admit(data, source: path))
        }
        return inputs
    }

    private static func readSource(
        _ url: URL,
        named name: String,
        plan: inout SculptureInsertionPlan
    ) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            let reason =
                errno == ELOOP ? "Choose a regular file, not a symbolic link." : String(cString: strerror(errno))
            throw SculptureInsertionError.source(name: name, reason: reason)
        }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0, information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw SculptureInsertionError.source(
                name: name,
                reason: "Choose a regular file, not a directory, device or pipe."
            )
        }
        let size = Int(information.st_size)
        try plan.admitBytes(size, source: name)
        var data = Data()
        while data.count <= size {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount: min(65_536, size + 1 - data.count)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw SculptureInsertionError.aggregateBytesExceeded(source: name, maximum: SculptureInsertionPlan.maximumBytes)
    }

    // MARK: - Parent and request

    /// A graph limit hit after the files were read is refused naming every listed file, not a generated model.
    private static func refusingByFile<Output>(
        _ files: [String],
        _ operation: () throws -> Output
    ) throws -> Output {
        do { return try operation() } catch let error as SculptureCompositionError {
            throw InsertToolError.graphRefused(files: files, reason: error.localizedDescription)
        } catch let error as SculptureWorldError {
            throw InsertToolError.graphRefused(files: files, reason: error.localizedDescription)
        }
    }

    private static func nativeScene(_ data: Data, at url: URL, named name: String) throws -> SculptureScene {
        if SculptureThreeMDCodec.isPortable(data) {
            try SculptureLinkedInput.refuseBinaryLinkedRoot(data, file: name)
            throw InsertToolError.portableParent(name)
        }
        do {
            if SculptureWorldCodec.isWorld(data) { return .world(try SculptureWorldCodec.decode(data)) }
            if SculptureCompositionCodec.isComposition(data) {
                return .composition(try SculptureCompositionCodec.decode(data))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SculptureInsertionError.source(name: name, reason: SculptureDiagnosticMessage.describe(error))
        }
        try SculptureLinkedInput.refuseLinkedRoot(data, file: name)
        throw InsertToolError.referenceDocumentRequired(url.path)
    }

    private static func loadRequest(at url: URL) throws -> Request {
        let data = try SculptureReferenceModelTool.readFile(at: url, maximumBytes: maximumRequestBytes)
        try PortableRequestJSON.validate(data)
        do { return try JSONDecoder().decode(Request.self, from: data) } catch let error as DecodingError {
            throw InsertToolError.requestMalformed(describe(error))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case .typeMismatch(_, let value), .valueNotFound(_, let value), .keyNotFound(_, let value),
            .dataCorrupted(let value):
            context = value
        @unknown default: return error.localizedDescription
        }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        // Foundation reports an unrepresentable number as corrupted data with the reason underneath.
        let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
        let detail = underlying.map { "\(context.debugDescription) \($0)" } ?? context.debugDescription
        return path.isEmpty ? detail : "\(path): \(detail)"
    }

    /// An existing output or symbolic link is refused up front. Publication refuses it again if one appears later.
    private static func requireNewOutput(_ output: URL) throws {
        var information = stat()
        if lstat(output.path, &information) == 0 { throw InsertToolError.outputExists(output.path) }
    }

    private static func location(of cell: SculptureCell) -> String {
        "column \(cell.x + 1), row \(cell.y + 1), layer \(cell.z + 1)"
    }

    private struct Request: Decodable {
        enum Target {
            case cell(SculptureCell)
            case focus(SculptureWorldPoint)
        }

        let files: [String]
        let target: Target
        let replaceOccupied: Bool
        let expectedScene: String?

        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: Key.self)
            let allowed: Set<String> = ["version", "files", "cell", "focus", "replaceOccupied", "expectedScene"]
            let unexpected = Set(fields.allKeys.map(\.stringValue)).subtracting(allowed)
            guard unexpected.isEmpty else { throw InsertToolError.unexpectedFields(unexpected.sorted()) }
            guard try fields.decode(Int.self, forKey: Key("version")) == 1 else { throw InsertToolError.requestVersion }
            files = try fields.decode([String].self, forKey: Key("files"))
            guard !files.isEmpty else { throw InsertToolError.filesRequired }
            for path in files {
                guard !path.isEmpty, !path.utf8.contains(0) else { throw InsertToolError.invalidPath }
            }
            let hasCell = fields.contains(Key("cell"))
            guard hasCell != fields.contains(Key("focus")) else { throw InsertToolError.targetRequired }
            if hasCell {
                let cell = try fields.nestedContainer(keyedBy: Key.self, forKey: Key("cell"))
                guard Set(cell.allKeys.map(\.stringValue)) == ["x", "y", "z"] else { throw InsertToolError.cellFields }
                target = .cell(
                    SculptureCell(
                        x: try cell.decode(Int.self, forKey: Key("x")),
                        y: try cell.decode(Int.self, forKey: Key("y")),
                        z: try cell.decode(Int.self, forKey: Key("z"))
                    )
                )
            } else {
                let focus = try fields.nestedContainer(keyedBy: Key.self, forKey: Key("focus"))
                guard Set(focus.allKeys.map(\.stringValue)) == ["x", "y", "z"] else {
                    throw InsertToolError.focusFields
                }
                target = .focus(
                    SculptureWorldPoint(
                        x: try Self.coordinate(focus, "x"),
                        y: try Self.coordinate(focus, "y"),
                        z: try Self.coordinate(focus, "z")
                    )
                )
            }
            replaceOccupied = try fields.decodeIfPresent(Bool.self, forKey: Key("replaceOccupied")) ?? false
            expectedScene = try fields.decodeIfPresent(String.self, forKey: Key("expectedScene"))
        }

        /// Exact Int64 as a canonical decimal string, so no coordinate passes through a lossy JSON number.
        private static func coordinate(_ container: KeyedDecodingContainer<Key>, _ axis: String) throws -> Int64 {
            let text = try container.decode(String.self, forKey: Key(axis))
            guard let value = Int64(text), String(value) == text else { throw InsertToolError.invalidCoordinate(axis) }
            return value
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }

    // MARK: - Receipt

    private struct Receipt: Encodable {
        let version = 1
        let action = "insert"
        let output: String
        let kind: String
        let title: String
        let storage: String
        let bytes: Int
        let placed: [Placement]
        let replacedGlyphs: [String]
        let revisionUTF8Bytes: Int?
        let diagnostics: DocumentDiagnosticReport?
        /// Reference insertion only: listed files whose portable data a native result cannot carry.
        let portableDataNotCarried: [String]?

        init(
            output: String,
            insertion: Insertion,
            storage: String,
            bytes: Int,
            revisionUTF8Bytes: Int?,
            diagnostics: DocumentDiagnosticReport?,
            portableDataNotCarried: [String]?
        ) {
            self.output = output
            self.portableDataNotCarried = portableDataNotCarried
            self.storage = storage
            self.bytes = bytes
            self.revisionUTF8Bytes = revisionUTF8Bytes
            self.diagnostics = diagnostics
            title = insertion.result.scene.title
            replacedGlyphs = insertion.cells.filter(\.isOccupied).map { String(UnicodeScalar($0.currentGlyph)) }
            switch insertion.result.scene {
            case .composition:
                kind = "composition"
                placed = zip(insertion.files.indices, insertion.result.placedRootIDs).map { index, modelID in
                    let cell = insertion.cells[index].cell
                    return Placement(
                        file: insertion.files[index],
                        title: insertion.inputs[index].scene.title,
                        modelID: modelID,
                        cell: .init(x: cell.x, y: cell.y, z: cell.z),
                        instanceID: nil,
                        origin: nil
                    )
                }
            case .world(let world):
                kind = "world"
                let added = Array(world.instances.suffix(insertion.files.count))
                placed = zip(insertion.files.indices, added).map { index, instance in
                    Placement(
                        file: insertion.files[index],
                        title: insertion.inputs[index].scene.title,
                        modelID: instance.modelID,
                        cell: nil,
                        instanceID: instance.id,
                        origin: .init(
                            x: String(instance.origin.x),
                            y: String(instance.origin.y),
                            z: String(instance.origin.z)
                        )
                    )
                }
            case .voxels:
                kind = "voxels"
                placed = []
            }
        }
    }

    private struct Placement: Encodable {
        struct Cell: Encodable {
            let x: Int
            let y: Int
            let z: Int
        }

        struct Origin: Encodable {
            let x: String
            let y: String
            let z: String
        }

        let file: String
        let title: String
        let modelID: String
        let cell: Cell?
        let instanceID: String?
        let origin: Origin?
    }

    // MARK: - Errors

    private enum Command {
        case portable, reference
    }

    private enum InsertToolError: LocalizedError {
        case usage(Command), outputExtension(Command), outputExists(String)
        case requestVersion, filesRequired, invalidPath, targetRequired, cellFields, focusFields
        case invalidCoordinate(String), unexpectedFields([String]), targetKind(String)
        case expectedSceneRequired, expectedSceneNotAllowed, portableOutputUnavailable, sceneKind
        case occupied([String]), referenceDocumentRequired(String), portableParent(String)
        case graphRefused(files: [String], reason: String), requestMalformed(String)

        var errorDescription: String? {
            switch self {
            case .usage(.portable):
                "Usage: RookTool sculpture portable insert INPUT REQUEST.json OUTPUT.3md|OUTPUT.3mdb"
            case .usage(.reference): "Usage: RookTool sculpture reference insert INPUT.3md REQUEST.json NEW.3md"
            case .outputExtension(.portable): "Portable insertion output must use .3md or .3mdb."
            case .outputExtension(.reference): "Reference insertion output must use .3md."
            case .outputExists(let path):
                "Refusing existing output or symbolic link at \(path). Choose a new output file."
            case .requestVersion: "Insertion requests require version 1."
            case .filesRequired: "An insertion request needs at least one file."
            case .invalidPath: "File paths must be nonempty and contain no null byte."
            case .targetRequired: "An insertion request needs exactly one of \"cell\" or \"focus\"."
            case .cellFields: "\"cell\" requires exactly integer x, y and z."
            case .focusFields: "\"focus\" requires exactly decimal string x, y and z."
            case .invalidCoordinate(let axis):
                "Focus \(axis) must be an exact Int64 written as a canonical decimal string, such as \"-12\"."
            case .unexpectedFields(let fields):
                "Unexpected insertion request fields: \(fields.joined(separator: ", ")). Use version, files, cell or focus, replaceOccupied and expectedScene."
            case .targetKind(let message): message
            case .expectedSceneRequired: "A portable insertion request requires expectedScene."
            case .expectedSceneNotAllowed:
                "A reference insertion request has no expectedScene. Use sculpture portable insert for revision checks."
            case .portableOutputUnavailable:
                "The inserted scene exceeds ThreeMD's portable limit, so no portable output can be written. Use sculpture reference insert to write a native result."
            case .portableParent(let name):
                "\(name) is a portable ThreeMD file. Use sculpture portable insert, or choose a native Sculpt composition or sparse world."
            case .graphRefused(let files, let reason):
                "Refusing to insert \(files.joined(separator: ", ")): \(reason)"
            case .requestMalformed(let detail): "The insertion request is malformed: \(detail)"
            case .sceneKind: "Insertion needs a composition or sparse world input."
            case .occupied(let cells):
                "Refusing to replace occupied tiles without \"replaceOccupied\": true. \(cells.joined(separator: "; "))."
            case .referenceDocumentRequired(let path):
                "Choose a self-contained composition or sparse world document: \(path)."
            }
        }
    }
}
