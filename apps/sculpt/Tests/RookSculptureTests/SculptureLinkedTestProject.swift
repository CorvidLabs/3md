import Foundation
import ThreeMD

@testable import RookSculpture

/// In-memory project files for linked resolution tests. Every read is recorded in order.
internal actor LinkedTestProject {
    // MARK: - Properties

    internal nonisolated let files: [String: Data]
    internal private(set) var reads: [String] = []


    // MARK: - Initializers

    internal init(_ files: [String: Data]) {
        self.files = files
    }


    // MARK: - Internal Methods

    internal func read(_ path: String, maximumBytes: Int) throws -> Data {
        reads.append(path)
        guard let data = files[path] else { throw CocoaError(.fileReadNoSuchFile) }
        return data
    }

    /// Resolves `rootPath` with its bytes from this project and an in-memory reader.
    internal nonisolated func resolve(
        _ rootPath: String,
        limits: SculptureLinkedLimits = .standard
    ) async throws -> SculptureLinkedResolution {
        try await SculptureLinkedResolver.resolve(
            rootPath: rootPath,
            rootData: files[rootPath] ?? Data(),
            limits: limits,
            read: { path, maximum in try await self.read(path, maximumBytes: maximum) }
        )
    }
}

/// Deterministic linked roots, voxels and other file kinds.
internal enum LinkedFixture {
    // MARK: - Internal Methods

    internal static func voxel(
        _ title: String = "Leaf",
        glyph: UInt8 = 35,
        width: Int = 1,
        height: Int = 1,
        depth: Int = 1
    ) throws -> Sculpture {
        try Sculpture(
            title: title,
            width: width,
            height: height,
            layers: Array(repeating: Array(repeating: glyph, count: width * height), count: depth)
        )
    }

    internal static func voxelData(_ title: String = "Leaf", glyph: UInt8 = 35, size: Int = 1) throws -> Data {
        SculptureCodec.encode(try voxel(title, glyph: glyph, width: size, height: size, depth: size))
    }

    internal static func binaryVoxel(
        _ sculpture: Sculpture,
        compression: DocumentCompression = .none
    ) throws -> Data {
        try DocumentStorageCodec.encode(
            SculptureCodec.document(for: sculpture),
            format: .binary(compression: compression)
        )
    }

    /// A linked root whose single row places `placed`, or every linked character in order when nil.
    internal static func linked(
        _ title: String = "Linked room",
        files: [Character: String],
        turns: [Character: Int] = [:],
        placed: String? = nil,
        tile: Int = 1
    ) throws -> SculptureLinkedComposition {
        let row = Array((placed ?? String(files.keys.sorted())).utf8)
        return try SculptureLinkedComposition(
            title: title,
            width: max(row.count, 1),
            height: 1,
            tileSize: .init(width: tile, height: tile, depth: tile),
            layers: [row.isEmpty ? [Sculpture.empty] : row],
            files: Dictionary(uniqueKeysWithValues: files.map { (byte($0.key), $0.value) }),
            quarterTurns: Dictionary(uniqueKeysWithValues: turns.map { (byte($0.key), $0.value) })
        )
    }

    internal static func linkedData(
        _ title: String = "Linked room",
        files: [Character: String],
        turns: [Character: Int] = [:],
        placed: String? = nil,
        tile: Int = 1
    ) throws -> Data {
        try SculptureLinkedCodec.encode(linked(title, files: files, turns: turns, placed: placed, tile: tile))
    }

    /// A readable document with exactly the supplied metadata, title and planes, validated by the canonical writer.
    internal static func document(
        title: String? = "Linked room",
        metadata: [String: String],
        planes: [Plane],
        preamble: String? = nil
    ) throws -> Data {
        try DocumentStorageCodec.encode(
            Document(
                version: "1.0",
                axis: .space,
                title: title,
                metadata: metadata,
                preamble: preamble,
                planes: planes
            )
        )
    }

    internal static func byte(_ character: Character) -> UInt8 {
        character.asciiValue ?? 0
    }

    /// Positional ThreeMD bundle IDs for an ordinary-document project, keyed by project path.
    internal static func bundleIDs(_ paths: [String]) -> [String: String] {
        let sorted = paths.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
        return Dictionary(
            uniqueKeysWithValues: sorted.enumerated().map { index, path in
                let digits = String(index)
                return (path, "file-" + String(repeating: "0", count: 6 - digits.count) + digits)
            }
        )
    }
}
