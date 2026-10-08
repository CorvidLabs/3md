import Foundation
import ThreeMD

/// An app-specific sparse scene: exact Int64 anchors and one self-contained composition library.
public enum SculptureWorldCodec {
    public static let maximumBytes = 20 * 1_048_576
    private static let schema = "ascii-world-1"

    public static func isWorld(_ data: Data) -> Bool {
        guard data.count <= maximumBytes else { return false }
        let prefix = String(decoding: data.prefix(16_384), as: UTF8.self)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var opened = false
        for raw in prefix.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" {
                if opened { return false }
                opened = true
            } else if opened, let colon = line.firstIndex(of: ":"),
                line[..<colon].trimmingCharacters(in: .whitespaces) == "scene-schema"
            {
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                return value == schema || value == "\"\(schema)\"" || value == "'\(schema)'"
            }
        }
        return false
    }

    /// Throws `tooLargeToReopen` when this world's native file would exceed a decode budget.
    public static func validateNativeCapacity(_ world: SculptureWorld) throws {
        do { _ = try encode(world) } catch SculptureWorldError.oversizedFile {
            throw SculptureCompositionError.tooLargeToReopen(lines: 0, bytes: maximumBytes + 1)
        }
    }

    public static func encode(_ world: SculptureWorld) throws -> Data {
        try Task.checkCancellation()
        let library = try SculptureCompositionCodec.encode(world.library)
        let envelope = WorldEnvelope(
            version: 1,
            library: String(decoding: library, as: UTF8.self),
            instances: world.instances.map(WorldInstanceRecord.init)
        )
        let encoder = JSONEncoder()
        // Keep the bounded instance list compact: pretty-printing 65,536 records would exceed the physical-line cap.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try encoder.encode(envelope)
        guard json.count <= maximumBytes else { throw SculptureWorldError.oversizedFile }
        let document = Document(
            version: "1.0",
            axis: .space,
            title: world.title,
            metadata: ["scene-schema": schema],
            planes: [Plane(z: 0, label: "World", body: "```json\n" + String(decoding: json, as: UTF8.self) + "\n```")]
        )
        let source = Serializer().render(document)
        guard source.utf8.count <= maximumBytes else { throw SculptureWorldError.oversizedFile }
        try Task.checkCancellation()
        return Data(source.utf8)
    }

    public static func decode(_ data: Data) throws -> SculptureWorld {
        guard data.count <= maximumBytes else { throw SculptureWorldError.oversizedFile }
        try Task.checkCancellation()
        guard let source = String(data: data, encoding: .utf8) else { throw SculptureWorldError.unsupportedSchema }
        let document: Document
        do {
            document = try SculptureCompositionCodec.checkedDocument(source, maximumPlanes: 1)
        } catch is CancellationError { throw CancellationError() } catch SculptureCompositionError.unsupportedPlane {
            throw SculptureWorldError.unsupportedPlane
        } catch { throw SculptureWorldError.unsupportedSchema }
        guard document.version == "1.0", document.axis == .space,
            document.metadata == ["scene-schema": schema], document.preamble == nil,
            let title = document.title
        else { throw SculptureWorldError.unsupportedSchema }
        guard document.planes.count == 1, let plane = document.planes.first,
            plane.z == 0, plane.label == "World", plane.x == nil, plane.y == nil, plane.attributes.isEmpty
        else { throw SculptureWorldError.unsupportedPlane }
        guard plane.body.hasPrefix("```json\n"), plane.body.hasSuffix("\n```") else {
            throw SculptureWorldError.invalidEnvelope
        }
        let json = Data(plane.body.dropFirst(8).dropLast(4).utf8)
        let envelope: WorldEnvelope
        do {
            envelope = try SculptureCompositionCodec.checkedJSON(
                WorldEnvelope.self,
                data: json,
                maximumValues: maximumJSONValues
            )
        } catch is CancellationError { throw CancellationError() } catch { throw SculptureWorldError.invalidEnvelope }
        guard envelope.version == 1 else { throw SculptureWorldError.invalidEnvelope }
        guard envelope.instances.count <= SculptureWorld.maximumInstances else {
            throw SculptureWorldError.tooManyInstances
        }
        let library: SculptureComposition
        do { library = try SculptureCompositionCodec.decode(Data(envelope.library.utf8)) } catch is CancellationError {
            throw CancellationError()
        } catch { throw SculptureWorldError.invalidLibrary }
        let instances = try envelope.instances.map { record in
            try Task.checkCancellation()
            return try SculptureWorldInstance(
                id: record.id,
                modelID: record.modelID,
                origin: SculptureWorldPoint(x: record.x, y: record.y, z: record.z),
                quarterTurns: record.quarterTurns
            )
        }
        return try SculptureWorld(title: title, library: library, instances: instances)
    }

    private static let maximumJSONValues = SculptureWorld.maximumInstances * 8 + 16
}

private struct WorldEnvelope: Codable {
    let version: Int
    let library: String
    let instances: [WorldInstanceRecord]

    init(version: Int, library: String, instances: [WorldInstanceRecord]) {
        self.version = version; self.library = library; self.instances = instances
    }

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: WorldJSONKey.self)
        guard Set(keys.allKeys.map(\.stringValue)) == ["version", "library", "instances"] else {
            throw SculptureWorldError.invalidEnvelope
        }
        version = try keys.decode(Int.self, forKey: WorldJSONKey("version"))
        library = try keys.decode(String.self, forKey: WorldJSONKey("library"))
        instances = try keys.decode([WorldInstanceRecord].self, forKey: WorldJSONKey("instances"))
    }

    func encode(to encoder: Encoder) throws {
        var keys = encoder.container(keyedBy: WorldJSONKey.self)
        try keys.encode(version, forKey: WorldJSONKey("version"))
        try keys.encode(library, forKey: WorldJSONKey("library"))
        try keys.encode(instances, forKey: WorldJSONKey("instances"))
    }
}

private struct WorldInstanceRecord: Codable {
    let id: String
    let modelID: String
    let x: Int64
    let y: Int64
    let z: Int64
    let quarterTurns: Int

    init(_ instance: SculptureWorldInstance) {
        id = instance.id; modelID = instance.modelID
        x = instance.origin.x; y = instance.origin.y; z = instance.origin.z
        quarterTurns = instance.quarterTurns
    }

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: WorldJSONKey.self)
        guard Set(keys.allKeys.map(\.stringValue)) == ["id", "modelID", "x", "y", "z", "quarterTurns"] else {
            throw SculptureWorldError.invalidEnvelope
        }
        id = try keys.decode(String.self, forKey: WorldJSONKey("id"))
        modelID = try keys.decode(String.self, forKey: WorldJSONKey("modelID"))
        x = try keys.decode(Int64.self, forKey: WorldJSONKey("x"))
        y = try keys.decode(Int64.self, forKey: WorldJSONKey("y"))
        z = try keys.decode(Int64.self, forKey: WorldJSONKey("z"))
        quarterTurns = try keys.decode(Int.self, forKey: WorldJSONKey("quarterTurns"))
    }

    func encode(to encoder: Encoder) throws {
        var keys = encoder.container(keyedBy: WorldJSONKey.self)
        try keys.encode(id, forKey: WorldJSONKey("id"))
        try keys.encode(modelID, forKey: WorldJSONKey("modelID"))
        try keys.encode(x, forKey: WorldJSONKey("x"))
        try keys.encode(y, forKey: WorldJSONKey("y"))
        try keys.encode(z, forKey: WorldJSONKey("z"))
        try keys.encode(quarterTurns, forKey: WorldJSONKey("quarterTurns"))
    }
}

private struct WorldJSONKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
