import Foundation
import ThreeMD

/// An app-specific composition schema over 3md spatial planes, with one embedded global model library.
public enum SculptureCompositionCodec {
    public static let maximumBytes = 20 * 1_048_576
    private static let schema = "ascii-composition-1"
    /// Decoding shares this physical-line budget across the root document, its library and every child.
    internal static let maximumLines = 100_000
    private static let tileKeys: Set<String> = [
        "scene-schema", "root-id", "width", "height", "tile-width", "tile-height", "tile-depth",
    ]

    /// Lightweight content detection. Validation belongs to `decode`; an invalid composition does not become a voxel file.
    public static func isComposition(_ data: Data) -> Bool {
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

    /// Encoding refuses any composition whose file decoding would exceed the same byte and line budgets,
    /// so every accepted native save reopens.
    public static func encode(_ composition: SculptureComposition) throws -> Data {
        try Task.checkCancellation()
        guard case .tiles(let root)? = composition.models[composition.rootID] else {
            throw SculptureCompositionError.invalidRoot
        }
        let plainRoot = try renderTile(root, id: composition.rootID, title: composition.title, preamble: nil)
        var byteCount = plainRoot.utf8.count
        var lineCount = Self.lineCount(of: plainRoot)
        try requireReopenable(lines: lineCount, bytes: byteCount)
        var records: [LibraryModel] = []
        for id in composition.models.keys.sorted() where id != composition.rootID {
            try Task.checkCancellation()
            guard let model = composition.models[id] else { throw SculptureCompositionError.unknownModel(id) }
            let document: String
            switch model {
            case .sculpture(let sculpture):
                let data = SculptureCodec.encode(sculpture)
                try requireReopenable(lines: lineCount, bytes: byteCount + data.count)
                document = String(decoding: data, as: UTF8.self)
            case .tiles(let map): document = try renderTile(map, id: id, title: id, preamble: nil)
            }
            byteCount += document.utf8.count
            lineCount += Self.lineCount(of: document)
            try requireReopenable(lines: lineCount, bytes: byteCount)
            records.append(LibraryModel(id: id, document: document))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let library = try encoder.encode(LibraryEnvelope(version: 1, models: records))
        try requireReopenable(lines: lineCount, bytes: library.count)
        let preamble = "```json\n" + String(decoding: library, as: UTF8.self) + "\n```"
        let source = try renderTile(root, id: composition.rootID, title: composition.title, preamble: preamble)
        // Decoding counts the complete root source, including its preamble, plus every library document.
        let childLines = lineCount - Self.lineCount(of: plainRoot)
        try requireReopenable(lines: childLines + Self.lineCount(of: source), bytes: source.utf8.count)
        try Task.checkCancellation()
        return Data(source.utf8)
    }

    /// Throws `tooLargeToReopen` when this composition's native file would exceed a decode budget.
    public static func validateNativeCapacity(_ composition: SculptureComposition) throws {
        _ = try encode(composition)
    }

    private static func requireReopenable(lines: Int, bytes: Int) throws {
        guard lines <= maximumLines, bytes <= maximumBytes else {
            throw SculptureCompositionError.tooLargeToReopen(lines: lines, bytes: bytes)
        }
    }

    /// Counts physical lines exactly as `decode` does, so encode and decode share one budget.
    private static func lineCount(of source: String) -> Int {
        var count = 0
        source.enumerateLines { _, _ in count += 1 }
        return count
    }

    public static func decode(_ data: Data) throws -> SculptureComposition {
        guard data.count <= maximumBytes else { throw SculptureCompositionError.oversizedFile }
        try Task.checkCancellation()
        guard let source = String(data: data, encoding: .utf8) else {
            throw SculptureCompositionError.unsupportedSchema
        }
        var budget = DecodeBudget()
        let document = try parse(source, budget: &budget)
        let rootID = try modelID(document)
        guard let title = document.title, SculptureCompositionValidation.isValidTitle(title),
            let preamble = document.preamble
        else { throw SculptureCompositionError.invalidLibrary }
        let root = try tileMap(document)
        let libraryData = try fencedJSON(preamble)
        let library: LibraryEnvelope = try strictJSON(LibraryEnvelope.self, data: libraryData)
        guard library.version == 1, library.models.count < SculptureComposition.maximumModels else {
            throw SculptureCompositionError.invalidLibrary
        }
        var models: [String: SculptureCompositionModel] = [rootID: .tiles(root)]
        for record in library.models {
            try Task.checkCancellation()
            guard SculptureCompositionValidation.isValidID(record.id) else {
                throw SculptureCompositionError.invalidID(record.id)
            }
            guard models[record.id] == nil else { throw SculptureCompositionError.duplicateModel(record.id) }
            let childDocument = try parse(record.document, budget: &budget)
            guard childDocument.preamble == nil else { throw SculptureCompositionError.invalidLibrary }
            switch childDocument.metadata["scene-schema"] {
            case "ascii-sculpture-1":
                // Preflight already rejected overwritten frontmatter keys and excessive parser allocations.
                guard childDocument.version == "1.0" else { throw SculptureCompositionError.unsupportedSchema }
                do {
                    models[record.id] = .sculpture(try SculptureCodec.decode(Data(record.document.utf8)))
                } catch is CancellationError { throw CancellationError() } catch {
                    throw SculptureCompositionError.invalidLibrary
                }
            case schema:
                guard try modelID(childDocument) == record.id, childDocument.title == record.id else {
                    throw SculptureCompositionError.invalidLibrary
                }
                models[record.id] = .tiles(try tileMap(childDocument))
            default: throw SculptureCompositionError.unsupportedSchema
            }
        }
        return try SculptureComposition(title: title, rootID: rootID, models: models)
    }

    private static func renderTile(_ map: SculptureTileMap, id: String, title: String, preamble: String?) throws
        -> String
    {
        Serializer().render(try document(for: map, id: id, title: title, preamble: preamble))
    }

    internal static func document(for map: SculptureTileMap, id: String, title: String?, preamble: String? = nil) throws
        -> Document
    {
        var metadata = [
            "scene-schema": schema, "root-id": id,
            "width": "\(map.width)", "height": "\(map.height)",
            "tile-width": "\(map.tileSize.width)", "tile-height": "\(map.tileSize.height)",
            "tile-depth": "\(map.tileSize.depth)",
        ]
        for binding in map.bindings {
            metadata[bindingKey(binding.glyph)] = "\(binding.modelID):\(binding.quarterTurns)"
        }
        let planes = try tilePlanes(map.layers, width: map.width, height: map.height)
        return Document(
            version: "1.0",
            axis: .space,
            title: title,
            metadata: metadata,
            preamble: preamble,
            planes: planes
        )
    }

    /// Renders tile layers as consecutive `Tile slice` planes. Shared by tile-map schemas so their bytes agree.
    internal static func tilePlanes(_ layers: [[UInt8]], width: Int, height: Int) throws -> [Plane] {
        try layers.enumerated().map { index, layer in
            try Task.checkCancellation()
            let rows = (0..<height).map { y in
                String(decoding: layer[(y * width)..<((y + 1) * width)], as: UTF8.self)
            }
            let body: String
            if rows.contains(where: { row in
                let trimmed = row.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            }) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.withoutEscapingSlashes]
                body = "```json\n" + String(decoding: try encoder.encode(rows), as: UTF8.self) + "\n```"
            } else {
                body = (["```ascii"] + rows + ["```"]).joined(separator: "\n")
            }
            return Plane(z: Double(index), label: "Tile slice \(index + 1)", body: body)
        }
    }

    private static func modelID(_ document: Document) throws -> String {
        guard document.version == "1.0", document.axis == .space,
            document.metadata["scene-schema"] == schema, let id = document.metadata["root-id"]
        else { throw SculptureCompositionError.unsupportedSchema }
        guard SculptureCompositionValidation.isValidID(id) else { throw SculptureCompositionError.invalidID(id) }
        return id
    }

    internal static func tileMap(_ document: Document) throws -> SculptureTileMap {
        _ = try modelID(document)
        guard tileKeys.isSubset(of: Set(document.metadata.keys)),
            document.metadata.keys.allSatisfy({ tileKeys.contains($0) || $0.hasPrefix("bind-") })
        else { throw SculptureCompositionError.unsupportedSchema }
        let geometry = try tileGeometry(document)
        let bindings = try document.metadata.keys.sorted().filter { $0.hasPrefix("bind-") }.map { key in
            let glyph = try bindingGlyph(key)
            let parts = (document.metadata[key] ?? "").split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let turns = Int(parts[1]) else { throw SculptureCompositionError.unsupportedSchema }
            return try SculptureModelBinding(glyph: glyph, modelID: String(parts[0]), quarterTurns: turns)
        }
        let layers = try tileLayers(document, width: geometry.width, height: geometry.height)
        return try SculptureTileMap(
            width: geometry.width,
            height: geometry.height,
            layers: layers,
            tileSize: geometry.tileSize,
            bindings: bindings
        )
    }

    /// Reads tile-map dimensions shared by tile schemas. Missing or out-of-range values are `unsupportedSchema`;
    /// a resolved volume above 256 cells on an axis is `invalidDimensions`.
    internal static func tileGeometry(_ document: Document) throws -> (
        width: Int, height: Int, tileSize: SculptureTileSize
    ) {
        guard let width = document.metadata["width"].flatMap(Int.init),
            let height = document.metadata["height"].flatMap(Int.init),
            let tileWidth = document.metadata["tile-width"].flatMap(Int.init),
            let tileHeight = document.metadata["tile-height"].flatMap(Int.init),
            let tileDepth = document.metadata["tile-depth"].flatMap(Int.init),
            (1...Sculpture.maximumDimension).contains(width), (1...Sculpture.maximumDimension).contains(height),
            (1...Sculpture.maximumDimension).contains(document.planes.count)
        else { throw SculptureCompositionError.unsupportedSchema }
        let tileSize = try SculptureTileSize(width: tileWidth, height: tileHeight, depth: tileDepth)
        guard width * tileSize.width <= Sculpture.maximumDimension,
            height * tileSize.height <= Sculpture.maximumDimension,
            document.planes.count * tileSize.depth <= Sculpture.maximumDimension
        else { throw SculptureCompositionError.invalidDimensions }
        return (width, height, tileSize)
    }

    /// Parses consecutive tile planes into one byte grid per layer. Shared by tile-map schemas.
    internal static func tileLayers(_ document: Document, width: Int, height: Int) throws -> [[UInt8]] {
        try document.planesByZ.enumerated().map { index, plane in
            try Task.checkCancellation()
            guard plane.z == Double(index), plane.x == nil, plane.y == nil, plane.attributes.isEmpty else {
                throw SculptureCompositionError.unsupportedPlane
            }
            let lines = plane.body.components(separatedBy: "\n")
            let rows: [String]
            if lines.first == "```ascii", lines.last == "```", lines.count == height + 2 {
                rows = Array(lines.dropFirst().dropLast())
            } else if lines.first == "```json", lines.last == "```" {
                rows = try strictJSON([String].self, data: fencedJSON(plane.body))
            } else {
                throw SculptureCompositionError.invalidGrid
            }
            guard rows.count == height else { throw SculptureCompositionError.invalidGrid }
            var cells: [UInt8] = []
            cells.reserveCapacity(width * height)
            for row in rows {
                try Task.checkCancellation()
                guard row.utf8.count == width else { throw SculptureCompositionError.invalidGrid }
                cells.append(contentsOf: row.utf8)
            }
            return cells
        }
    }

    private static func bindingKey(_ glyph: UInt8) -> String {
        // A colon separates frontmatter keys; a final space is stripped by the 3md parser.
        if glyph == 32 || glyph == 58 { return "bind-0x" + String(format: "%02X", glyph) }
        return "bind-" + String(decoding: [glyph], as: UTF8.self)
    }

    private static func bindingGlyph(_ key: String) throws -> UInt8 {
        let suffix = String(key.dropFirst("bind-".count))
        if suffix.utf8.count == 1, let byte = suffix.utf8.first { return byte }
        if suffix.hasPrefix("0x"), suffix.utf8.count == 4, let byte = UInt8(suffix.dropFirst(2), radix: 16) {
            return byte
        }
        throw SculptureCompositionError.unsupportedSchema
    }

    private struct DecodeBudget { var lines = 0 }

    /// Bound source lines, directive allocations and duplicate keys before handing input to ThreeMD.
    internal static func checkedDocument(_ source: String, maximumPlanes: Int) throws -> Document {
        var budget = DecodeBudget()
        return try parse(source, budget: &budget, maximumPlanes: maximumPlanes)
    }

    internal static func checkedJSON<T: Decodable>(
        _ type: T.Type,
        data: Data,
        maximumValues: Int
    ) throws -> T {
        try strictJSON(type, data: data, maximumValues: maximumValues)
    }

    private static func parse(
        _ source: String,
        budget: inout DecodeBudget,
        maximumPlanes: Int = Sculpture.maximumDimension
    ) throws -> Document {
        guard source.utf8.count <= maximumBytes else { throw SculptureCompositionError.oversizedFile }
        var headerStarted = false
        var headerClosed = false
        var headerKeys: Set<String> = []
        var fence: Character?
        var planes = 0
        var failure: SculptureCompositionError?
        var lineCount = budget.lines
        source.enumerateLines { rawLine, stop in
            guard !Task.isCancelled else { stop = true; return }
            lineCount += 1
            guard lineCount <= maximumLines else { failure = .unsupportedSchema; stop = true; return }
            let raw = headerStarted ? rawLine : rawLine.replacingOccurrences(of: "\u{FEFF}", with: "")
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !headerClosed {
                if trimmed == "---" {
                    if headerStarted { headerClosed = true } else { headerStarted = true }
                } else if headerStarted, !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                    guard let separator = trimmed.firstIndex(of: ":") else {
                        failure = .unsupportedSchema; stop = true; return
                    }
                    let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
                    let canonical = ["3md", "axis", "title"].contains(key.lowercased()) ? key.lowercased() : key
                    guard headerKeys.count < 128, headerKeys.insert(canonical).inserted else {
                        failure = .unsupportedSchema; stop = true; return
                    }
                } else if !headerStarted, !trimmed.isEmpty {
                    failure = .unsupportedSchema; stop = true
                }
                return
            }
            if let open = fence {
                if trimmed.hasPrefix(String(repeating: open, count: 3)) { fence = nil }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = trimmed.first
            } else if raw.first != " ", raw.first != "\t",
                raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).first == "@plane"
            {
                planes += 1
                guard planes <= maximumPlanes, validDirectiveKeys(raw) else {
                    failure = .unsupportedPlane; stop = true; return
                }
            }
        }
        try Task.checkCancellation()
        budget.lines = lineCount
        if let failure { throw failure }
        guard headerStarted, headerClosed else { throw SculptureCompositionError.unsupportedSchema }
        do {
            let document = try Parser().parse(source)
            try Task.checkCancellation()
            return document
        } catch is CancellationError { throw CancellationError() } catch {
            throw SculptureCompositionError.unsupportedSchema
        }
    }

    private static func validDirectiveKeys(_ line: String) -> Bool {
        guard line.utf8.count <= 512 else { return false }
        var quote: Character?
        var escaped = false
        var token = ""
        var tokens: [String] = []
        for character in line {
            if let active = quote {
                token.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == active {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character; token.append(character)
            } else if character == " " || character == "\t" {
                if !token.isEmpty { tokens.append(token); token = "" }
            } else {
                token.append(character)
            }
        }
        if !token.isEmpty { tokens.append(token) }
        guard quote == nil, tokens.first == "@plane" else { return false }
        var keys: Set<String> = []
        for field in tokens.dropFirst() {
            guard let separator = field.firstIndex(of: "=") else { return false }
            let key = field[..<separator].lowercased()
            guard ["z", "label"].contains(key), keys.insert(key).inserted else { return false }
        }
        return keys.contains("z")
    }

    private static func fencedJSON(_ source: String) throws -> Data {
        guard source.hasPrefix("```json\n"), source.hasSuffix("\n```") else {
            throw SculptureCompositionError.invalidLibrary
        }
        return Data(source.dropFirst(8).dropLast(4).utf8)
    }

    private static func strictJSON<T: Decodable>(
        _ type: T.Type,
        data: Data,
        maximumValues: Int = 512
    ) throws -> T {
        try Task.checkCancellation()
        var scanner = CompositionJSONPreflight(bytes: Array(data), maximumValues: maximumValues)
        try scanner.validate()
        do {
            let value = try JSONDecoder().decode(type, from: data)
            try Task.checkCancellation()
            return value
        } catch is CancellationError { throw CancellationError() } catch {
            throw SculptureCompositionError.invalidLibrary
        }
    }
}

private struct LibraryEnvelope: Codable {
    let version: Int
    let models: [LibraryModel]

    init(version: Int, models: [LibraryModel]) { self.version = version; self.models = models }

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: CompositionJSONKey.self)
        guard Set(keys.allKeys.map(\.stringValue)) == ["version", "models"] else {
            throw SculptureCompositionError.invalidLibrary
        }
        version = try keys.decode(Int.self, forKey: CompositionJSONKey("version"))
        models = try keys.decode([LibraryModel].self, forKey: CompositionJSONKey("models"))
    }

    func encode(to encoder: Encoder) throws {
        var keys = encoder.container(keyedBy: CompositionJSONKey.self)
        try keys.encode(version, forKey: CompositionJSONKey("version"))
        try keys.encode(models, forKey: CompositionJSONKey("models"))
    }
}

private struct LibraryModel: Codable {
    let id: String
    let document: String

    init(id: String, document: String) { self.id = id; self.document = document }

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: CompositionJSONKey.self)
        guard Set(keys.allKeys.map(\.stringValue)) == ["id", "document"] else {
            throw SculptureCompositionError.invalidLibrary
        }
        id = try keys.decode(String.self, forKey: CompositionJSONKey("id"))
        document = try keys.decode(String.self, forKey: CompositionJSONKey("document"))
    }

    func encode(to encoder: Encoder) throws {
        var keys = encoder.container(keyedBy: CompositionJSONKey.self)
        try keys.encode(id, forKey: CompositionJSONKey("id"))
        try keys.encode(document, forKey: CompositionJSONKey("document"))
    }
}

private struct CompositionJSONKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// Prevents deep/large JSON allocations and rejects duplicate object keys before JSONDecoder can overwrite them.
private struct CompositionJSONPreflight {
    let bytes: [UInt8]
    let maximumValues: Int
    private var index = 0
    private var values = 0

    init(bytes: [UInt8], maximumValues: Int) {
        self.bytes = bytes
        self.maximumValues = maximumValues
    }

    mutating func validate() throws {
        try value(depth: 0)
        try whitespace()
        guard index == bytes.count else { throw SculptureCompositionError.invalidLibrary }
    }

    private mutating func value(depth: Int) throws {
        try Task.checkCancellation()
        values += 1
        guard depth <= 4, values <= maximumValues else { throw SculptureCompositionError.invalidLibrary }
        try whitespace()
        guard index < bytes.count else { throw SculptureCompositionError.invalidLibrary }
        switch bytes[index] {
        case 123:
            index += 1; try whitespace()
            if take(125) { return }
            var keys: Set<String> = []
            while true {
                try whitespace()
                let start = index
                try string()
                guard index - start <= 128 else { throw SculptureCompositionError.invalidLibrary }
                let key: String
                do { key = try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) } catch {
                    throw SculptureCompositionError.invalidLibrary
                }
                guard keys.insert(key).inserted else { throw SculptureCompositionError.invalidLibrary }
                try whitespace()
                guard take(58) else { throw SculptureCompositionError.invalidLibrary }
                try value(depth: depth + 1)
                try whitespace()
                if take(125) { break }
                guard take(44) else { throw SculptureCompositionError.invalidLibrary }
            }
        case 91:
            index += 1; try whitespace()
            if take(93) { return }
            while true {
                try value(depth: depth + 1)
                try whitespace()
                if take(93) { break }
                guard take(44) else { throw SculptureCompositionError.invalidLibrary }
            }
        case 34: try string()
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) {
                index += 1
                if (index - start).isMultiple(of: 16_384) { try Task.checkCancellation() }
            }
            guard index > start else { throw SculptureCompositionError.invalidLibrary }
        }
    }

    private mutating func string() throws {
        guard take(34) else { throw SculptureCompositionError.invalidLibrary }
        let start = index
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 { return }
            if byte == 92 {
                guard index < bytes.count else { throw SculptureCompositionError.invalidLibrary }
                index += 1
            }
            if (index - start).isMultiple(of: 16_384) { try Task.checkCancellation() }
        }
        throw SculptureCompositionError.invalidLibrary
    }

    private mutating func whitespace() throws {
        var checkpoint = index + 16_384
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) {
            index += 1
            if index >= checkpoint {
                try Task.checkCancellation()
                checkpoint = index + 16_384
            }
        }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
}
