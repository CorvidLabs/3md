import Foundation
import ThreeMD

/// Explicit portable scene interchange. Existing readable and compact save codecs remain available.
public enum SculptureThreeMDCodec {
    public static let maximumBytes = SculptureCodec.maximumBytes
    private static let storageKey = "sculpt-storage"
    private static let storageValue = "portable-scene-1"
    private static let worldSchema = "ascii-world-2"

    /// Content recognition only. Recognized but malformed portable files must still fail decoding.
    public static func isPortable(_ data: Data) -> Bool {
        if DocumentStorageCodec.isBinary(data) { return true }
        var prefix = String(decoding: data.prefix(16_384), as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
        if prefix.utf8.starts(with: [0xEF, 0xBB, 0xBF]) { prefix = String(prefix.unicodeScalars.dropFirst()) }
        var opened = false
        for raw in prefix.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" {
                if opened { return false }
                opened = true
            } else if opened, let colon = line.unicodeScalars.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.unicodeScalars.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                for marker in [("profile", "3md-composition-1"), (storageKey, storageValue)] where key == marker.0 {
                    if value == marker.1 || value == "\"\(marker.1)\"" || value == "'\(marker.1)'" { return true }
                }
            }
        }
        return false
    }

    /// Returns a retained model document title without decoding or changing the scene.
    /// Missing model IDs and standalone document snapshots return nil.
    public static func modelTitle(for modelID: String, in snapshot: SculptureThreeMDSnapshot) -> String? {
        guard case .composition(let stored) = snapshot.storage else { return nil }
        return stored.composition.entry(id: modelID)?.document.title
    }

    /// Adopts identities in a separate immutable value. It does not save or migrate a user's file.
    public static func capture(
        _ scene: SculptureScene,
        preserving snapshot: SculptureThreeMDSnapshot? = nil
    ) throws -> SculptureThreeMDSnapshot {
        try Task.checkCancellation()
        if let snapshot, snapshot.scene == scene { return snapshot }
        let documentLimits = try SculptureThreeMDPolicy.document()
        switch scene {
        case .voxels(let sculpture):
            var document = SculptureCodec.document(for: sculpture)
            var metadata = document.metadata
            metadata[storageKey] = storageValue
            document = DocumentHeader(
                version: document.version,
                axis: document.axis,
                title: document.title,
                metadata: metadata
            ).documentForScene(planes: document.planes)
            if case .document(let previous)? = snapshot?.storage {
                document = preservingPlanes(document, from: previous.document)
            }
            let adopted = try DocumentIdentity.adopt(document, documentLimits: documentLimits)
            return try makeSnapshot(scene: scene, document: adopted)
        case .composition(let composition):
            let previous = previousGraph(snapshot)
            let entries = try modelEntries(composition, preserving: previous)
            let graph = try DocumentComposition(
                rootID: composition.rootID,
                entries: entries,
                limits: SculptureThreeMDPolicy.composition(),
                documentLimits: documentLimits
            )
            return try adoptedSnapshot(scene: scene, graph: graph)
        case .world(let world):
            let previous = previousGraph(snapshot)
            let rootID = worldRootID(world, preserving: previous)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let records = PortableWorldRecords(version: 1, instances: world.instances.map(PortableWorldInstance.init))
            let data = try encoder.encode(records)
            guard data.count <= maximumBytes else { throw DocumentStorageError.oversizedOutput }
            let root = Document(
                version: "1.0",
                axis: .space,
                title: world.title,
                metadata: [
                    "scene-schema": worldSchema, "library-root": world.library.rootID,
                    "library-title": world.library.title,
                ],
                planes: [
                    Plane(z: 0, label: "World", body: "```json\n" + String(decoding: data, as: UTF8.self) + "\n```")
                ]
            )
            let targets = Set(world.instances.map(\.modelID)).union([world.library.rootID]).sorted()
            let references = targets.map { DocumentReference(targetID: $0, attributes: ["role": "world-model"]) }
            let entry = preservingEntry(
                .init(id: rootID, document: root, references: references),
                from: previous?.entry(id: rootID)
            )
            let graph = try DocumentComposition(
                rootID: rootID,
                entries: modelEntries(world.library, preserving: previous) + [entry],
                limits: SculptureThreeMDPolicy.composition(),
                documentLimits: documentLimits
            )
            return try adoptedSnapshot(scene: scene, graph: graph)
        }
    }

    public static func decode(_ data: Data) throws -> SculptureThreeMDSnapshot {
        try Task.checkCancellation()
        guard data.count <= maximumBytes else { throw DocumentStorageError.oversizedInput }
        let limits = try SculptureThreeMDPolicy.document()
        // Profile records can exceed an individual plane's usual limit. The adapter still has a 20 MiB total ceiling.
        let document = try DocumentStorageCodec.decode(data, limits: limits)
        if DocumentCompositionCodec.isComposition(document) {
            let graph = try DocumentCompositionCodec.decode(
                document,
                limits: SculptureThreeMDPolicy.composition(),
                documentLimits: limits
            )
            let scene = try scene(from: graph)
            return try adoptedSnapshot(scene: scene, graph: graph)
        }
        // A linked root is readable text resolved with its project folder; a binary copy is refused by name.
        if document.metadata["scene-schema"] == SculptureLinkedCodec.schema, DocumentStorageCodec.isBinary(data) {
            throw SculptureLinkedError.binaryLinkedRoot
        }
        guard document.version == "1.0" else { throw SculptureError.unsupportedSchema }
        let sculpture = try SculptureCodec.sculpture(from: schemaDocument(document))
        var metadata = document.metadata
        metadata[storageKey] = storageValue
        let marked = Document(
            version: document.version,
            axis: document.axis,
            title: document.title,
            metadata: metadata,
            preamble: document.preamble,
            planes: document.planes
        )
        let adopted = try DocumentIdentity.adopt(marked, documentLimits: limits)
        return try makeSnapshot(scene: .voxels(sculpture), document: adopted)
    }

    public static func encode(
        _ snapshot: SculptureThreeMDSnapshot,
        format: DocumentStorageFormat = .text
    ) throws -> Data {
        try Task.checkCancellation()
        let document: Document
        switch snapshot.storage {
        case .document(let value): document = value.document
        case .composition(let value):
            document = try DocumentCompositionCodec.document(
                for: value.composition,
                limits: SculptureThreeMDPolicy.composition(),
                documentLimits: SculptureThreeMDPolicy.document()
            )
        }
        return try DocumentStorageCodec.encode(document, format: format, limits: SculptureThreeMDPolicy.document())
    }

    /// Only resource ceilings permit an explicit legacy editing fallback. Invalid schemas and identities do not.
    public static func isCapacityError(_ error: any Error) -> Bool {
        if let error = error as? DocumentStorageError {
            switch error {
            case .oversizedInput, .oversizedOutput, .tooManyLines, .tooManyPlanes, .oversizedRecord: return true
            default: return false
            }
        }
        if let error = error as? DocumentCompositionError {
            switch error {
            case .tooManyDefinitions, .tooManyReferences, .depthExceeded, .definitionBytesExceeded,
                .traversalOccurrencesExceeded, .referenceAttributesExceeded, .profileBytesExceeded:
                return true
            default: return false
            }
        }
        return (error as? DocumentEditError)?.diagnostic.code == .payloadLimit
    }

    internal static func makeSnapshot(scene: SculptureScene, document: Document) throws -> SculptureThreeMDSnapshot {
        let limits = try SculptureThreeMDPolicy.document()
        let snapshot = try DocumentSnapshot(document, limits: limits)
        let diagnostics = try DocumentDiagnostics.inspect(
            document,
            limits: SculptureThreeMDPolicy.editing(),
            documentLimits: limits
        )
        return .init(scene: scene, diagnostics: diagnostics, storage: .document(snapshot))
    }

    internal static func makeSnapshot(scene: SculptureScene, graph: DocumentComposition) throws
        -> SculptureThreeMDSnapshot
    {
        let limits = try SculptureThreeMDPolicy.document()
        let graphLimits = try SculptureThreeMDPolicy.composition()
        let snapshot = try DocumentCompositionSnapshot(graph, limits: graphLimits, documentLimits: limits)
        let diagnostics = try DocumentDiagnostics.inspect(
            graph,
            limits: SculptureThreeMDPolicy.editing(),
            compositionLimits: graphLimits,
            documentLimits: limits
        )
        return .init(scene: scene, diagnostics: diagnostics, storage: .composition(snapshot))
    }

    private static func adoptedSnapshot(scene: SculptureScene, graph: DocumentComposition) throws
        -> SculptureThreeMDSnapshot
    {
        try makeSnapshot(
            scene: scene,
            graph: DocumentIdentity.adopt(
                graph,
                limits: SculptureThreeMDPolicy.composition(),
                documentLimits: SculptureThreeMDPolicy.document()
            )
        )
    }

    private static func previousGraph(_ snapshot: SculptureThreeMDSnapshot?) -> DocumentComposition? {
        if case .composition(let value)? = snapshot?.storage { return value.composition }
        return nil
    }

    private static func modelEntries(
        _ composition: SculptureComposition,
        preserving previous: DocumentComposition?
    ) throws -> [DocumentEntry] {
        try composition.models.keys.sorted().map { id in
            try Task.checkCancellation()
            let document: Document
            let references: [DocumentReference]
            switch composition.models[id] {
            case .sculpture(let sculpture):
                document = SculptureCodec.document(for: sculpture)
                references = []
            case .tiles(let map):
                // A nested definition that was untitled stays untitled; only a new definition is titled by its ID.
                let title: String?
                if id == composition.rootID {
                    title = composition.title
                } else if let previousEntry = previous?.entry(id: id) {
                    title = previousEntry.document.title
                } else {
                    title = id
                }
                document = try SculptureCompositionCodec.document(for: map, id: id, title: title)
                references = map.bindings.map {
                    .init(
                        targetID: $0.modelID,
                        attributes: ["glyph": String($0.glyph), "quarter-turns": String($0.quarterTurns)]
                    )
                }
            case nil: throw SculptureCompositionError.unknownModel(id)
            }
            return preservingEntry(
                .init(id: id, document: document, references: references),
                from: previous?.entry(id: id)
            )
        }
    }

    internal static func preservingPlanes(_ document: Document, from previous: Document) -> Document {
        let previousPlanes = Dictionary(uniqueKeysWithValues: previous.planes.map { ($0.z, $0) })
        let generatedPlanes = Dictionary(uniqueKeysWithValues: document.planes.map { ($0.z, $0) })
        let surviving = previous.planes.compactMap { generatedPlanes[$0.z] }
        let appended = document.planes.filter { previousPlanes[$0.z] == nil }.sorted { $0.z < $1.z }
        let planes = (surviving + appended).map { plane in
            var attributes = previousPlanes[plane.z]?.attributes ?? [:]
            attributes.merge(plane.attributes) { _, new in new }
            let label = previousPlanes[plane.z].map(\.label) ?? plane.label
            return Plane(z: plane.z, label: label, x: plane.x, y: plane.y, attributes: attributes, body: plane.body)
        }
        var metadata = previous.metadata.filter {
            !geometryMetadataKey($0.key, schema: previous.metadata["scene-schema"])
        }
        metadata.merge(document.metadata) { _, new in new }
        return Document(
            version: document.version,
            axis: document.axis,
            title: document.title,
            metadata: metadata,
            preamble: previous.preamble,
            planes: planes
        )
    }

    private static func preservingEntry(_ entry: DocumentEntry, from previous: DocumentEntry?) -> DocumentEntry {
        guard let previous else { return entry }
        var used: Set<Int> = []
        var references: [DocumentReference] = []
        for old in previous.references {
            let position = entry.references.indices.first { index in
                guard !used.contains(index) else { return false }
                let reference = entry.references[index]
                // A binding keeps its annotations only for the same glyph and the same target model.
                if let glyph = reference.attributes["glyph"] {
                    return old.attributes["glyph"] == glyph && old.targetID == reference.targetID
                }
                return old.targetID == reference.targetID && old.attributes["role"] == reference.attributes["role"]
            }
            guard let position else { continue }
            used.insert(position)
            let reference = entry.references[position]
            var attributes = old.attributes
            attributes.merge(reference.attributes) { _, new in new }
            references.append(.init(targetID: reference.targetID, attributes: attributes))
        }
        references.append(contentsOf: entry.references.enumerated().filter { !used.contains($0.offset) }.map(\.element))
        return .init(
            id: entry.id,
            document: preservingPlanes(entry.document, from: previous.document),
            references: references
        )
    }

    private static func worldRootID(_ world: SculptureWorld, preserving previous: DocumentComposition?) -> String {
        if let previous, previous.rootEntry.document.metadata["scene-schema"] == worldSchema,
            world.library.models[previous.rootID] == nil
        {
            return previous.rootID
        }
        var id = "sculpt-world"
        var suffix = 1
        while world.library.models[id] != nil { id = "sculpt-world-\(suffix)"; suffix += 1 }
        return id
    }

    /// Validate only spatial fields; portable snapshots retain opaque metadata, Markdown and plane attributes.
    private static func schemaDocument(_ document: Document) throws -> Document {
        var metadata = document.metadata
        if let marker = metadata.removeValue(forKey: storageKey), marker != storageValue {
            throw SculptureThreeMDError(
                "Unsupported Sculpt portable storage profile.",
                path: "metadata[sculpt-storage]"
            )
        }
        let schema = metadata["scene-schema"]
        metadata = metadata.filter { geometryMetadataKey($0.key, schema: schema) }
        let planes = try document.planes.map { plane in
            try Task.checkCancellation()
            return Plane(
                z: plane.z,
                label: plane.label,
                x: plane.x,
                y: plane.y,
                attributes: [:],
                body: plane.body
            )
        }
        return Document(
            version: document.version,
            axis: document.axis,
            title: document.title,
            metadata: metadata,
            preamble: nil,
            planes: planes
        )
    }

    /// Validates a voxel definition exactly as portable scene mapping does, retaining opaque metadata and Markdown.
    internal static func portableVoxel(_ document: Document) throws -> Sculpture {
        let geometry = try schemaDocument(document)
        guard geometry.version == "1.0" else {
            throw SculptureThreeMDError("Portable model definitions need version 1.0 and no embedded library.")
        }
        return try SculptureCodec.sculpture(from: geometry)
    }

    internal static func scene(from graph: DocumentComposition) throws -> SculptureScene {
        let root = graph.rootEntry.document
        let isWorld = root.metadata["scene-schema"] == worldSchema
        let entries = graph.entries.filter { !isWorld || $0.id != graph.rootID }
        guard entries.count <= SculptureComposition.maximumModels else { throw SculptureCompositionError.tooManyModels }
        var models: [String: SculptureCompositionModel] = [:]
        for entry in entries {
            try Task.checkCancellation()
            let document = try schemaDocument(entry.document)
            guard document.version == "1.0", document.preamble == nil else {
                throw SculptureThreeMDError(
                    "Portable model definitions need version 1.0 and no embedded library.",
                    path: "entries[\(entry.id)]"
                )
            }
            switch document.metadata["scene-schema"] {
            case "ascii-sculpture-1":
                guard entry.references.isEmpty else { throw invalidReferences(entry.id) }
                models[entry.id] = .sculpture(try SculptureCodec.sculpture(from: document))
            case "ascii-composition-1":
                guard document.metadata["root-id"] == entry.id else { throw invalidReferences(entry.id) }
                let map = try SculptureCompositionCodec.tileMap(document)
                let expected = map.bindings.map {
                    DocumentReference(
                        targetID: $0.modelID,
                        attributes: ["glyph": String($0.glyph), "quarter-turns": String($0.quarterTurns)]
                    )
                }
                guard geometryReferences(entry.references, keys: ["glyph", "quarter-turns"]) == expected else {
                    throw invalidReferences(entry.id)
                }
                models[entry.id] = .tiles(map)
            case SculptureLinkedCodec.schema:
                models[entry.id] = .tiles(try linkedTileMap(document, references: entry.references, id: entry.id))
            default:
                throw SculptureThreeMDError("Unsupported portable model schema.", path: "entries[\(entry.id)].document")
            }
        }
        if !isWorld {
            guard let title = root.title else { throw SculptureCompositionError.invalidTitle }
            return .composition(try SculptureComposition(title: title, rootID: graph.rootID, models: models))
        }
        let document = try schemaDocument(root)
        guard document.version == "1.0", document.axis == .space, document.preamble == nil,
            Set(document.metadata.keys) == ["scene-schema", "library-root", "library-title"],
            let title = document.title, let libraryRoot = document.metadata["library-root"],
            let libraryTitle = document.metadata["library-title"], document.planes.count == 1,
            let plane = document.planes.first, plane.z == 0, plane.label == "World", plane.x == nil, plane.y == nil,
            plane.attributes.isEmpty, plane.body.hasPrefix("```json\n"), plane.body.hasSuffix("\n```")
        else { throw SculptureThreeMDError("Invalid portable sparse world envelope.", path: "root") }
        let json = Data(plane.body.dropFirst(8).dropLast(4).utf8)
        let records = try SculptureCompositionCodec.checkedJSON(
            PortableWorldRecords.self,
            data: json,
            maximumValues: SculptureWorld.maximumInstances * 8 + 16
        )
        guard records.version == 1 else { throw SculptureWorldError.invalidEnvelope }
        guard records.instances.count <= SculptureWorld.maximumInstances else {
            throw SculptureWorldError.tooManyInstances
        }
        let instances = try records.instances.map { try $0.instance() }
        let targets = Set(instances.map(\.modelID)).union([libraryRoot]).sorted()
        let expected = targets.map { DocumentReference(targetID: $0, attributes: ["role": "world-model"]) }
        guard geometryReferences(graph.rootEntry.references, keys: ["role"]) == expected else {
            throw invalidReferences(graph.rootID)
        }
        let library = try SculptureComposition(title: libraryTitle, rootID: libraryRoot, models: models)
        guard graph.entry(id: libraryRoot)?.document.title == libraryTitle else {
            throw SculptureThreeMDError(
                "The world library title disagrees with its root definition.",
                path: "root.metadata[library-title]"
            )
        }
        return .world(try SculptureWorld(title: title, library: library, instances: instances))
    }

    /// Bundled linked roots bind each reference's single-character `glyph` to its target definition.
    /// `glyph` and `source-file` are read as an unordered set, other attributes are ignored, and `source-file`
    /// is never followed: the bundle is self-contained.
    private static func linkedTileMap(
        _ document: Document,
        references: [DocumentReference],
        id: String
    ) throws -> SculptureTileMap {
        guard document.axis == .space else {
            throw SculptureThreeMDError(
                "Portable linked compositions need the space axis.",
                path: "entries[\(id)].document"
            )
        }
        let geometry = try SculptureCompositionCodec.tileGeometry(document)
        let turns = try SculptureLinkedCodec.quarterTurns(document.metadata[SculptureLinkedCodec.turnsKey])
        var glyphs: Set<UInt8> = []
        var bindings: [SculptureModelBinding] = []
        for reference in references {
            try Task.checkCancellation()
            let attributes = reference.attributes.filter { linkedReferenceKeys.contains($0.key) }
            guard Set(attributes.keys) == linkedReferenceKeys, let text = attributes["glyph"], text.utf8.count == 1,
                let glyph = text.utf8.first, SculptureLinkedComposition.isLinkGlyph(glyph),
                glyphs.insert(glyph).inserted
            else {
                throw SculptureThreeMDError(
                    "Linked references need a unique one-character glyph and a source-file each.",
                    path: "entries[\(id)].references"
                )
            }
            bindings.append(
                try SculptureModelBinding(glyph: glyph, modelID: reference.targetID, quarterTurns: turns[glyph] ?? 0)
            )
        }
        guard Set(turns.keys).isSubset(of: glyphs) else {
            throw SculptureThreeMDError(
                "sculpt-turns rotates a character without a linked reference.",
                path: "entries[\(id)].document.metadata[sculpt-turns]"
            )
        }
        let layers = try SculptureCompositionCodec.tileLayers(document, width: geometry.width, height: geometry.height)
        return try SculptureTileMap(
            width: geometry.width,
            height: geometry.height,
            layers: layers,
            tileSize: geometry.tileSize,
            bindings: bindings
        )
    }

    private static let linkedReferenceKeys: Set<String> = ["glyph", "source-file"]

    private static func geometryReferences(_ references: [DocumentReference], keys: Set<String>) -> [DocumentReference]
    {
        references.map {
            DocumentReference(targetID: $0.targetID, attributes: $0.attributes.filter { keys.contains($0.key) })
        }.sorted {
            if keys.contains("glyph") {
                let first = Int($0.attributes["glyph"] ?? "") ?? -1
                let second = Int($1.attributes["glyph"] ?? "") ?? -1
                if first != second { return first < second }
            }
            return $0.targetID < $1.targetID
        }
    }

    private static func geometryMetadataKey(_ key: String, schema: String?) -> Bool {
        switch schema {
        case "ascii-sculpture-1": ["scene-schema", "width", "height"].contains(key)
        case "ascii-composition-1":
            ["scene-schema", "root-id", "width", "height", "tile-width", "tile-height", "tile-depth"].contains(key)
                || key.hasPrefix("bind-")
        case worldSchema: ["scene-schema", "library-root", "library-title"].contains(key)
        case SculptureLinkedCodec.schema:
            [
                "scene-schema", "width", "height", "tile-width", "tile-height", "tile-depth",
                SculptureLinkedCodec.turnsKey, SculptureLinkedCodec.ledgerKey,
            ].contains(key)
        default: key == "scene-schema"
        }
    }

    private static func invalidReferences(_ id: String) -> SculptureThreeMDError {
        .init(
            "Portable references must exactly match the model's bindings or world targets.",
            path: "entries[\(id)].references"
        )
    }
}

// Public ThreeMD headers deliberately expose values rather than a document factory.
internal extension DocumentHeader {
    func documentForScene(planes: [Plane]) -> Document {
        Document(version: version, axis: axis, title: title, metadata: metadata, preamble: preamble, planes: planes)
    }
}

private struct PortableWorldRecords: Codable {
    let version: Int
    let instances: [PortableWorldInstance]
    init(version: Int, instances: [PortableWorldInstance]) { self.version = version; self.instances = instances }
    private enum CodingKeys: String, CodingKey { case version, instances }
    init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: PortableWorldKey.self)
        guard Set(keys.allKeys.map(\.stringValue)) == ["version", "instances"] else {
            throw SculptureWorldError.invalidEnvelope
        }
        version = try keys.decode(Int.self, forKey: .init("version"))
        instances = try keys.decode([PortableWorldInstance].self, forKey: .init("instances"))
    }
}

private struct PortableWorldInstance: Codable {
    let id: String
    let modelID: String
    let x: Int64
    let y: Int64
    let z: Int64
    let quarterTurns: Int
    init(_ value: SculptureWorldInstance) {
        id = value.id; modelID = value.modelID; x = value.origin.x; y = value.origin.y; z = value.origin.z
        quarterTurns = value.quarterTurns
    }
    private enum CodingKeys: String, CodingKey { case id, modelID, x, y, z, quarterTurns }
    init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: PortableWorldKey.self)
        guard Set(keys.allKeys.map(\.stringValue)) == ["id", "modelID", "x", "y", "z", "quarterTurns"] else {
            throw SculptureWorldError.invalidEnvelope
        }
        id = try keys.decode(String.self, forKey: .init("id"))
        modelID = try keys.decode(String.self, forKey: .init("modelID"))
        x = try keys.decode(Int64.self, forKey: .init("x"))
        y = try keys.decode(Int64.self, forKey: .init("y"))
        z = try keys.decode(Int64.self, forKey: .init("z"))
        quarterTurns = try keys.decode(Int.self, forKey: .init("quarterTurns"))
    }
    func instance() throws -> SculptureWorldInstance {
        try Task.checkCancellation()
        return try .init(id: id, modelID: modelID, origin: .init(x: x, y: y, z: z), quarterTurns: quarterTurns)
    }
}

private struct PortableWorldKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
