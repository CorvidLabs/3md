import Foundation
import ThreeMD

/// A linked root: a tile map whose characters name model files in its project folder instead of an embedded library.
///
/// Stored as the app-specific readable `ascii-linked-composition-1` ThreeMD schema. Paths are relative to the file
/// that contains them. The value is never resolved by itself; `SculptureLinkedResolver` reads the reachable files.
public struct SculptureLinkedComposition: Equatable, Sendable {
    // MARK: - Properties

    /// Printable ASCII title of 1 to 80 bytes.
    public let title: String
    /// Tile columns.
    public let width: Int
    /// Tile rows.
    public let height: Int
    /// The voxel block reserved for each placed character.
    public let tileSize: SculptureTileSize
    /// One `width * height` byte grid per tile layer. A period leaves its block empty.
    public let layers: [[UInt8]]
    /// Glyph to file path relative to this file. Every placed byte other than a period is a key.
    public let files: [UInt8: String]
    /// Glyph to clockwise quarter-turns of 1, 2 or 3. A glyph without an entry is unrotated.
    public let quarterTurns: [UInt8: Int]

    /// Tile layers.
    public var depth: Int { layers.count }


    // MARK: - Initializers

    /// Validates bounds, glyphs and placements without reading any linked file.
    /// - Throws: `SculptureLinkedError.invalid` naming the failed rule, or a `SculptureCompositionError` for bounds.
    public init(
        title: String,
        width: Int,
        height: Int,
        tileSize: SculptureTileSize,
        layers: [[UInt8]],
        files: [UInt8: String],
        quarterTurns: [UInt8: Int] = [:]
    ) throws {
        try Task.checkCancellation()
        guard SculptureCompositionValidation.isValidTitle(title) else {
            throw SculptureLinkedError.invalid(reason: "Use a title of 1 to 80 printable ASCII characters.")
        }
        guard (1...Sculpture.maximumDimension).contains(width),
            (1...Sculpture.maximumDimension).contains(height),
            (1...Sculpture.maximumDimension).contains(layers.count),
            width * tileSize.width <= Sculpture.maximumDimension,
            height * tileSize.height <= Sculpture.maximumDimension,
            layers.count * tileSize.depth <= Sculpture.maximumDimension
        else { throw SculptureCompositionError.invalidDimensions }
        for (glyph, path) in files {
            guard Self.isLinkGlyph(glyph) else {
                throw SculptureLinkedError.invalid(
                    reason: "Link character byte \(glyph) must be printable ASCII other than a space or a period."
                )
            }
            guard !path.isEmpty else {
                throw SculptureLinkedError.invalid(reason: "The link for \(Self.describe(glyph)) has no file path.")
            }
        }
        for (glyph, turns) in quarterTurns {
            guard files[glyph] != nil else {
                throw SculptureLinkedError.invalid(
                    reason: "sculpt-turns rotates \(Self.describe(glyph)), which has no linked file."
                )
            }
            guard (1...3).contains(turns) else {
                throw SculptureLinkedError.invalid(reason: "Use one, two or three clockwise quarter-turns.")
            }
        }
        var placements = 0
        for layer in layers {
            guard layer.count == width * height else { throw SculptureCompositionError.invalidGrid }
            for y in 0..<height {
                try Task.checkCancellation()
                for glyph in layer[(y * width)..<((y + 1) * width)] where glyph != Sculpture.empty {
                    guard files[glyph] != nil else {
                        throw SculptureLinkedError.invalid(
                            reason: "The map places \(Self.describe(glyph)), which has no linked file."
                        )
                    }
                    placements += 1
                    guard placements <= SculptureComposition.maximumPlacements else {
                        throw SculptureCompositionError.excessivePlacements
                    }
                }
            }
        }
        self.title = title
        self.width = width
        self.height = height
        self.tileSize = tileSize
        self.layers = layers
        self.files = files
        self.quarterTurns = quarterTurns
    }


    // MARK: - Internal Methods

    /// Linked glyphs are one printable ASCII byte other than a space or a period.
    internal static func isLinkGlyph(_ glyph: UInt8) -> Bool {
        (33...126).contains(glyph) && glyph != Sculpture.empty
    }

    internal static func describe(_ glyph: UInt8) -> String {
        isLinkGlyph(glyph) ? "'\(String(decoding: [glyph], as: UTF8.self))'" : "byte \(glyph)"
    }
}

/// Readable `ascii-linked-composition-1` storage, content detection and `3md-files` ledger building.
public enum SculptureLinkedCodec {
    // MARK: - Properties

    /// The app-specific scene schema of a linked root.
    public static let schema = "ascii-linked-composition-1"
    /// Bytes of a file searched for a linked root's frontmatter. The canonical writer sorts `3md-files` first.
    public static let maximumDetectionBytes = 256 * 1_024
    /// Raw UTF-8 bytes allowed in one `3md-files` value, checked before the ledger is parsed.
    public static let maximumLedgerBytes = 128 * 1_024
    /// Raw UTF-8 bytes allowed in one `sculpt-turns` value.
    internal static let maximumTurnsBytes = 4_096
    internal static let ledgerKey = "3md-files"
    internal static let turnsKey = "sculpt-turns"
    internal static let requiredKeys: Set<String> = [
        "scene-schema", "width", "height", "tile-width", "tile-height", "tile-depth", ledgerKey,
    ]


    // MARK: - Public Methods

    /// Content recognition within the first 256 KiB of readable text. A binary container is never a linked root.
    /// Recognized but malformed files must still fail decoding.
    public static func isLinked(_ data: Data) -> Bool {
        guard !DocumentStorageCodec.isBinary(data) else { return false }
        let prefix = String(decoding: data.prefix(maximumDetectionBytes), as: UTF8.self)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var opened = false
        for raw in prefix.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" {
                if opened { return false }
                opened = true
            } else if !opened {
                if !line.isEmpty { return false }
            } else if let colon = line.firstIndex(of: ":"),
                line[..<colon].trimmingCharacters(in: .whitespaces) == "scene-schema"
            {
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                return value == schema || value == "\"\(schema)\"" || value == "'\(schema)'"
            }
        }
        return false
    }

    /// Decodes a readable linked root. A general binary document declaring the linked schema is refused by name.
    /// - Throws: `SculptureLinkedError` for linked rules, or a ThreeMD storage error for unreadable text.
    public static func decode(_ data: Data) throws -> SculptureLinkedComposition {
        try Task.checkCancellation()
        guard data.count <= SculptureCodec.maximumBytes else { throw DocumentStorageError.oversizedInput }
        let document = try DocumentStorageCodec.decode(data, limits: SculptureThreeMDPolicy.document())
        guard document.metadata["scene-schema"] == schema else {
            throw SculptureLinkedError.invalid(reason: "The file does not declare scene-schema \(schema).")
        }
        guard !DocumentStorageCodec.isBinary(data) else { throw SculptureLinkedError.binaryLinkedRoot }
        return try composition(from: document)
    }

    /// Encodes canonical readable ThreeMD text with a ledger built by `ledgerValue(for:)`.
    public static func encode(_ composition: SculptureLinkedComposition) throws -> Data {
        try Task.checkCancellation()
        var metadata = [
            "scene-schema": schema,
            "width": "\(composition.width)", "height": "\(composition.height)",
            "tile-width": "\(composition.tileSize.width)", "tile-height": "\(composition.tileSize.height)",
            "tile-depth": "\(composition.tileSize.depth)",
        ]
        metadata[ledgerKey] = try ledgerValue(for: stringKeyed(composition.files))
        if !composition.quarterTurns.isEmpty {
            metadata[turnsKey] = try singleLineJSON(stringKeyed(composition.quarterTurns))
        }
        let document = Document(
            version: "1.0",
            axis: .space,
            title: composition.title,
            metadata: metadata,
            planes: try SculptureCompositionCodec.tilePlanes(
                composition.layers,
                width: composition.width,
                height: composition.height
            )
        )
        let data = try DocumentStorageCodec.encode(document, format: .text, limits: SculptureThreeMDPolicy.document())
        try Task.checkCancellation()
        return data
    }

    /// Builds a `3md-files` value: single-line JSON with sorted keys and unescaped slashes, never concatenated.
    ///
    /// Keys are single link characters (printable ASCII other than a space or a period); values are paths relative to
    /// the containing file. The result is verified to round-trip through ThreeMD's ledger reader.
    public static func ledgerValue(for files: [String: String]) throws -> String {
        for (glyph, path) in files {
            guard glyph.utf8.count == 1, let byte = glyph.utf8.first, SculptureLinkedComposition.isLinkGlyph(byte)
            else {
                throw SculptureLinkedError.invalid(
                    reason: "Use one printable ASCII character other than a space or a period for each link."
                )
            }
            guard !path.isEmpty else {
                throw SculptureLinkedError.invalid(reason: "The link for '\(glyph)' has no file path.")
            }
        }
        let value = try singleLineJSON(files)
        guard value.utf8.count <= maximumLedgerBytes else {
            throw SculptureLinkedError.invalid(reason: "The 3md-files ledger exceeds 128 KiB.")
        }
        let probe = Document(version: "1.0", axis: .space, metadata: [ledgerKey: value], planes: [])
        let references = try DocumentFileComposition.ledger(in: probe)
        guard references.count == files.count, references.allSatisfy({ files[$0.glyph] == $0.source }) else {
            throw SculptureLinkedError.invalid(reason: "The 3md-files ledger did not round-trip.")
        }
        return value
    }


    // MARK: - Internal Methods

    /// Strict validation of a parsed linked root: exact metadata, a title, no preamble and tile planes.
    internal static func composition(from document: Document) throws -> SculptureLinkedComposition {
        try Task.checkCancellation()
        let keys = Set(document.metadata.keys)
        guard document.version == "1.0", document.axis == .space, document.preamble == nil,
            document.metadata["scene-schema"] == schema,
            requiredKeys.isSubset(of: keys), keys.subtracting(requiredKeys).isSubset(of: [turnsKey])
        else {
            throw SculptureLinkedError.invalid(
                reason:
                    "Use a version 1.0 space document with exactly scene-schema, width, height, tile-width, "
                    + "tile-height, tile-depth, 3md-files and optional sculpt-turns, and no preamble."
            )
        }
        guard let title = document.title else {
            throw SculptureLinkedError.invalid(reason: "Use a title of 1 to 80 printable ASCII characters.")
        }
        let files = try ledger(in: document)
        let turns = try quarterTurns(document.metadata[turnsKey])
        let geometry: (width: Int, height: Int, tileSize: SculptureTileSize)
        let layers: [[UInt8]]
        do {
            geometry = try SculptureCompositionCodec.tileGeometry(document)
            layers = try SculptureCompositionCodec.tileLayers(document, width: geometry.width, height: geometry.height)
        } catch SculptureCompositionError.unsupportedSchema {
            throw SculptureLinkedError.invalid(
                reason: "Use positive integer width, height and tile sizes and 1 to 256 tile planes."
            )
        } catch SculptureCompositionError.invalidLibrary {
            throw SculptureCompositionError.invalidGrid
        }
        return try SculptureLinkedComposition(
            title: title,
            width: geometry.width,
            height: geometry.height,
            tileSize: geometry.tileSize,
            layers: layers,
            files: files,
            quarterTurns: turns
        )
    }

    /// Reads the ledger after checking its raw size. Duplicate keys and invalid characters are refused.
    internal static func ledger(in document: Document) throws -> [UInt8: String] {
        guard let raw = document.metadata[ledgerKey] else { return [:] }
        guard raw.utf8.count <= maximumLedgerBytes else {
            throw SculptureLinkedError.invalid(reason: "The 3md-files ledger exceeds 128 KiB.")
        }
        let references: [DocumentFileReference]
        do { references = try DocumentFileComposition.ledger(in: document) } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SculptureLinkedError.invalid(reason: error.localizedDescription)
        }
        var files: [UInt8: String] = [:]
        for reference in references {
            guard let glyph = reference.glyph.utf8.first, SculptureLinkedComposition.isLinkGlyph(glyph) else {
                throw SculptureLinkedError.invalid(reason: "A period cannot link a file; it leaves a tile empty.")
            }
            files[glyph] = reference.source
        }
        return files
    }

    /// Reads optional `sculpt-turns` JSON mapping a link character to 1, 2 or 3.
    internal static func quarterTurns(_ raw: String?) throws -> [UInt8: Int] {
        guard let raw else { return [:] }
        guard raw.utf8.count <= maximumTurnsBytes, !raw.contains("\n") else {
            throw SculptureLinkedError.invalid(reason: "sculpt-turns must be one short line of JSON.")
        }
        let values: [String: Int]
        do {
            values = try SculptureCompositionCodec.checkedJSON(
                [String: Int].self,
                data: Data(raw.utf8),
                maximumValues: 128
            )
        } catch is CancellationError { throw CancellationError() } catch {
            throw SculptureLinkedError.invalid(reason: "sculpt-turns must map link characters to 1, 2 or 3.")
        }
        var turns: [UInt8: Int] = [:]
        for (key, value) in values {
            guard key.utf8.count == 1, let glyph = key.utf8.first, SculptureLinkedComposition.isLinkGlyph(glyph),
                (1...3).contains(value)
            else { throw SculptureLinkedError.invalid(reason: "sculpt-turns must map link characters to 1, 2 or 3.") }
            turns[glyph] = value
        }
        return turns
    }


    // MARK: - Private Methods

    /// Validated link characters are distinct ASCII bytes, so their one-character strings are distinct too.
    private static func stringKeyed<Value>(_ values: [UInt8: Value]) -> [String: Value] {
        Dictionary(values.map { (String(decoding: [$0.key], as: UTF8.self), $0.value) }) { first, _ in first }
    }

    private static func singleLineJSON<Value>(_ object: [String: Value]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard let value = String(data: data, encoding: .utf8), !value.contains("\n"), !value.contains("\r") else {
            throw SculptureLinkedError.invalid(reason: "A linked composition value must be one line of JSON.")
        }
        return value
    }
}
