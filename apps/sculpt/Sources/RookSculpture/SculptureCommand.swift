import Foundation

/// A flat, action-tagged command. Coordinates are zero-based document cells, independent of the camera.
public enum SculptureCommand: Equatable, Codable, Sendable {
    case paint(x: Int, y: Int, z: Int, glyph: String)
    case erase(x: Int, y: Int, z: Int)
    case fill(x: Int, y: Int, z: Int, glyph: String)
    case clearSlice(z: Int)
    case rotateSlice(z: Int, quarterTurns: Int)
    case rename(title: String)

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CommandCodingKey.self)
        let action = try fields.decode(String.self, forKey: CommandCodingKey("action"))
        switch action {
        case "paint", "fill":
            try rejectExtraFields(fields, allowed: ["action", "x", "y", "z", "glyph"])
            let x = try fields.decode(Int.self, forKey: CommandCodingKey("x"))
            let y = try fields.decode(Int.self, forKey: CommandCodingKey("y"))
            let z = try fields.decode(Int.self, forKey: CommandCodingKey("z"))
            let glyph = try fields.decode(String.self, forKey: CommandCodingKey("glyph"))
            self = action == "paint" ? .paint(x: x, y: y, z: z, glyph: glyph) : .fill(x: x, y: y, z: z, glyph: glyph)
        case "erase":
            try rejectExtraFields(fields, allowed: ["action", "x", "y", "z"])
            self = .erase(
                x: try fields.decode(Int.self, forKey: CommandCodingKey("x")),
                y: try fields.decode(Int.self, forKey: CommandCodingKey("y")),
                z: try fields.decode(Int.self, forKey: CommandCodingKey("z"))
            )
        case "clearSlice":
            try rejectExtraFields(fields, allowed: ["action", "z"])
            self = .clearSlice(z: try fields.decode(Int.self, forKey: CommandCodingKey("z")))
        case "rotateSlice":
            try rejectExtraFields(fields, allowed: ["action", "z", "quarterTurns"])
            self = .rotateSlice(
                z: try fields.decode(Int.self, forKey: CommandCodingKey("z")),
                quarterTurns: try fields.decode(Int.self, forKey: CommandCodingKey("quarterTurns"))
            )
        case "rename":
            try rejectExtraFields(fields, allowed: ["action", "title"])
            self = .rename(title: try fields.decode(String.self, forKey: CommandCodingKey("title")))
        default:
            throw SculptureCommandError.unknownAction(action)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CommandCodingKey.self)
        switch self {
        case .paint(let x, let y, let z, let glyph), .fill(let x, let y, let z, let glyph):
            let action: String
            if case .paint = self { action = "paint" } else { action = "fill" }
            try fields.encode(action, forKey: CommandCodingKey("action"))
            try fields.encode(x, forKey: CommandCodingKey("x"))
            try fields.encode(y, forKey: CommandCodingKey("y"))
            try fields.encode(z, forKey: CommandCodingKey("z"))
            try fields.encode(glyph, forKey: CommandCodingKey("glyph"))
        case .erase(let x, let y, let z):
            try fields.encode("erase", forKey: CommandCodingKey("action"))
            try fields.encode(x, forKey: CommandCodingKey("x"))
            try fields.encode(y, forKey: CommandCodingKey("y"))
            try fields.encode(z, forKey: CommandCodingKey("z"))
        case .clearSlice(let z):
            try fields.encode("clearSlice", forKey: CommandCodingKey("action"))
            try fields.encode(z, forKey: CommandCodingKey("z"))
        case .rotateSlice(let z, let quarterTurns):
            try fields.encode("rotateSlice", forKey: CommandCodingKey("action"))
            try fields.encode(z, forKey: CommandCodingKey("z"))
            try fields.encode(quarterTurns, forKey: CommandCodingKey("quarterTurns"))
        case .rename(let title):
            try fields.encode("rename", forKey: CommandCodingKey("action"))
            try fields.encode(title, forKey: CommandCodingKey("title"))
        }
    }
}

/// A versioned, bounded edit transaction. Every command must succeed before a result is returned.
public struct SculptureCommandBatch: Equatable, Codable, Sendable {
    public static let maximumCommands = 256
    public let version: Int
    public let commands: [SculptureCommand]

    public init(version: Int = 1, commands: [SculptureCommand]) throws {
        guard version == 1 else { throw SculptureCommandError.unsupportedVersion(version) }
        guard (1...Self.maximumCommands).contains(commands.count) else {
            throw SculptureCommandError.invalidCommandCount(commands.count)
        }
        self.version = version
        self.commands = commands
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CommandCodingKey.self)
        try rejectExtraFields(fields, allowed: ["version", "commands"])
        try self.init(
            version: fields.decode(Int.self, forKey: CommandCodingKey("version")),
            commands: fields.decode([SculptureCommand].self, forKey: CommandCodingKey("commands"))
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CommandCodingKey.self)
        try fields.encode(version, forKey: CommandCodingKey("version"))
        try fields.encode(commands, forKey: CommandCodingKey("commands"))
    }
}

/// Machine-readable document facts. Inspection does not modify the sculpture or depend on a renderer.
public struct SculptureInspection: Equatable, Codable, Sendable {
    public let version: Int
    public let title: String
    public let width: Int
    public let height: Int
    public let depth: Int
    public let occupiedCount: Int
    public let palette: [String]
    public let emptyGlyph: String
    public let coordinateBase: Int
    public let axes: [String: String]

    public init(sculpture: Sculpture) {
        version = 1
        title = sculpture.title
        width = sculpture.width
        height = sculpture.height
        depth = sculpture.depth
        occupiedCount = sculpture.occupiedCount
        palette = Sculpture.palette.map { String(decoding: [$0], as: UTF8.self) }
        emptyGlyph = String(decoding: [Sculpture.empty], as: UTF8.self)
        coordinateBase = 0
        axes = [
            "x": "column, left to right",
            "y": "row, top to bottom",
            "z": "slice index, increasing spatial depth",
        ]
    }
}

/// Pure value-based editing shared by native controls and structured callers.
public enum SculptureCommandEngine {
    public static func inspect(_ sculpture: Sculpture) -> SculptureInspection {
        SculptureInspection(sculpture: sculpture)
    }

    public static func apply(_ command: SculptureCommand, to sculpture: Sculpture) throws -> Sculpture {
        var result = sculpture
        switch command {
        case .paint(let x, let y, let z, let glyph):
            let cell = try validatedCell(x: x, y: y, z: z, in: sculpture)
            result.paint(cell, glyph: try validatedGlyph(glyph))
        case .erase(let x, let y, let z):
            result.paint(try validatedCell(x: x, y: y, z: z, in: sculpture), glyph: Sculpture.empty)
        case .fill(let x, let y, let z, let glyph):
            let cell = try validatedCell(x: x, y: y, z: z, in: sculpture)
            let replacement = try validatedGlyph(glyph)
            let previous = sculpture.layers[z][y * sculpture.width + x]
            guard previous != replacement else { return result }
            var queued = Array(repeating: false, count: sculpture.width * sculpture.height)
            var cells = [cell]
            queued[y * sculpture.width + x] = true
            var cursor = 0
            while cursor < cells.count {
                let cell = cells[cursor]
                cursor += 1
                result.paint(cell, glyph: replacement)
                let neighbors = [
                    SculptureCell(x: cell.x - 1, y: cell.y, z: z),
                    SculptureCell(x: cell.x + 1, y: cell.y, z: z),
                    SculptureCell(x: cell.x, y: cell.y - 1, z: z),
                    SculptureCell(x: cell.x, y: cell.y + 1, z: z),
                ]
                for neighbor in neighbors {
                    guard (0..<sculpture.width).contains(neighbor.x), (0..<sculpture.height).contains(neighbor.y) else {
                        continue
                    }
                    let index = neighbor.y * sculpture.width + neighbor.x
                    guard !queued[index], sculpture.layers[z][index] == previous else { continue }
                    queued[index] = true
                    cells.append(neighbor)
                }
            }
        case .clearSlice(let z):
            try validateSlice(z, in: sculpture)
            for y in 0..<sculpture.height {
                for x in 0..<sculpture.width {
                    result.paint(SculptureCell(x: x, y: y, z: z), glyph: Sculpture.empty)
                }
            }
        case .rotateSlice(let z, let quarterTurns):
            try validateSlice(z, in: sculpture)
            guard (1...3).contains(quarterTurns) else { throw SculptureCommandError.invalidRotation(quarterTurns) }
            for _ in 0..<quarterTurns { try result.rotateLayer(at: z) }
        case .rename(let title):
            try result.rename(title)
        }
        return result
    }

    public static func apply(_ batch: SculptureCommandBatch, to sculpture: Sculpture) throws -> Sculpture {
        var result = sculpture
        for command in batch.commands { result = try apply(command, to: result) }
        return result
    }

    private static func validatedCell(x: Int, y: Int, z: Int, in sculpture: Sculpture) throws -> SculptureCell {
        guard (0..<sculpture.width).contains(x), (0..<sculpture.height).contains(y), (0..<sculpture.depth).contains(z)
        else {
            throw SculptureCommandError.cellOutOfBounds(
                x: x,
                y: y,
                z: z,
                width: sculpture.width,
                height: sculpture.height,
                depth: sculpture.depth
            )
        }
        return SculptureCell(x: x, y: y, z: z)
    }

    private static func validateSlice(_ z: Int, in sculpture: Sculpture) throws {
        guard (0..<sculpture.depth).contains(z) else {
            throw SculptureCommandError.sliceOutOfBounds(z: z, depth: sculpture.depth)
        }
    }

    private static func validatedGlyph(_ glyph: String) throws -> UInt8 {
        guard glyph.utf8.count == 1, let value = glyph.utf8.first,
            value == Sculpture.empty || Sculpture.palette.contains(value)
        else { throw SculptureCommandError.invalidGlyph(glyph) }
        return value
    }
}

public enum SculptureCommandError: Error, LocalizedError, Equatable, Sendable {
    case unknownAction(String)
    case unexpectedFields([String])
    case unsupportedVersion(Int)
    case invalidCommandCount(Int)
    case invalidGlyph(String)
    case invalidRotation(Int)
    case cellOutOfBounds(x: Int, y: Int, z: Int, width: Int, height: Int, depth: Int)
    case sliceOutOfBounds(z: Int, depth: Int)

    public var errorDescription: String? {
        switch self {
        case .unknownAction(let action):
            "Unknown action '\(action)'. Use paint, erase, fill, clearSlice, rotateSlice, or rename."
        case .unexpectedFields(let fields):
            "Unexpected command fields: \(fields.joined(separator: ", ")). Remove fields this action does not use."
        case .unsupportedVersion(let version):
            "Command version \(version) is unsupported. Use version 1."
        case .invalidCommandCount(let count):
            "A batch must contain 1–\(SculptureCommandBatch.maximumCommands) commands; received \(count)."
        case .invalidGlyph(let glyph):
            "'\(glyph)' is not one palette character. Use # @ * + o x : = - or a period for empty."
        case .invalidRotation(let turns):
            "Use 1, 2, or 3 clockwise quarter-turns; received \(turns)."
        case .cellOutOfBounds(let x, let y, let z, let width, let height, let depth):
            "Cell (\(x), \(y), \(z)) is outside this document. Use zero-based x 0...\(width - 1), y 0...\(height - 1), z 0...\(depth - 1)."
        case .sliceOutOfBounds(let z, let depth):
            "Slice \(z) is outside this document. Use a zero-based z from 0 through \(depth - 1)."
        }
    }
}

private struct CommandCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

private func rejectExtraFields(_ fields: KeyedDecodingContainer<CommandCodingKey>, allowed: Set<String>) throws {
    let unexpected = Set(fields.allKeys.map(\.stringValue)).subtracting(allowed)
    guard unexpected.isEmpty else { throw SculptureCommandError.unexpectedFields(unexpected.sorted()) }
}
