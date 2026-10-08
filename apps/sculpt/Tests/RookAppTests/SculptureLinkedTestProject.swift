import Foundation
import RookSculpture
import Testing

@testable import RookApp

/// A linked project in a fresh temporary folder, for the in-process linked session tests.
internal struct LinkedAppProject {
    // MARK: - Properties

    /// The project folder, as a person would choose it.
    internal let folder: URL


    // MARK: - Initializers

    internal init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("RookLinked-\(UUID())")
        folder = base.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }


    // MARK: - Internal Methods

    /// The temporary folder that holds the project folder, for files outside the project.
    internal var container: URL { folder.deletingLastPathComponent() }

    internal func url(_ path: String) -> URL {
        folder.appendingPathComponent(path)
    }

    @discardableResult
    internal func write(_ path: String, _ data: Data) throws -> URL {
        let url = url(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }

    internal func remove() {
        try? FileManager.default.removeItem(at: container)
    }

    /// Every regular file below the container with its bytes, to prove that a flow wrote nothing.
    internal func contents() throws -> [String: Data] {
        var files: [String: Data] = [:]
        let root = container.resolvingSymlinksInPath().path
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return files }
        while let relative = enumerator.nextObject() as? String {
            let path = root + "/" + relative
            var isDirectory: ObjCBool = false
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue
            else { continue }
            files[relative] = try Data(contentsOf: URL(fileURLWithPath: path))
        }
        return files
    }

    /// The standard nested project: a root in `scenes/`, two voxel models in nested `models/` folders, and a nested
    /// linked room that links one of the same models.
    @discardableResult
    internal func writeStandard() throws -> URL {
        try write("models/trees/oak.3md", Self.voxel("Oak", glyph: 35))
        try write("models/rocks/stone.3md", Self.voxel("Stone", glyph: 64))
        try write(
            "scenes/rooms/annex.3md",
            Self.linked("Annex", files: ["A": "../../models/trees/oak.3md"])
        )
        return try write(
            "scenes/main.3md",
            Self.linked(
                "Main hall",
                files: ["A": "../models/trees/oak.3md", "B": "../models/rocks/stone.3md", "C": "rooms/annex.3md"]
            )
        )
    }

    /// Readable `ascii-sculpture-1` bytes of a one-cell model.
    internal static func voxel(_ title: String, glyph: UInt8) throws -> Data {
        SculptureCodec.encode(try Sculpture(title: title, width: 1, height: 1, layers: [[glyph]]))
    }

    /// A readable linked root whose single row places every linked character in order, or `placed`.
    internal static func linked(
        _ title: String,
        files: [Character: String],
        placed: String? = nil,
        tile: Int = 1
    ) throws -> Data {
        let row = Array((placed ?? String(files.keys.sorted())).utf8)
        let composition = try SculptureLinkedComposition(
            title: title,
            width: row.count,
            height: 1,
            tileSize: .init(width: tile, height: tile, depth: tile),
            layers: [row],
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.key.asciiValue ?? 0, $0.value) })
        )
        return try SculptureLinkedCodec.encode(composition)
    }

    /// Opens `root` with `folder` and returns the session, recording an issue for any other outcome.
    @MainActor
    internal static func session(root: URL, folder: URL) async throws -> SculptureLinkedSession {
        switch await SculptureLinkedSession.open(root: root, folder: folder) {
        case .opened(let session): return session
        case .cancelled: throw LinkedAppProjectError.unexpected("cancelled")
        case .refused(let message): throw LinkedAppProjectError.unexpected(message)
        }
    }

    /// Waits for work the session started on its own, such as Choose Folder.
    @MainActor
    internal static func settle(_ session: SculptureLinkedSession) async {
        for _ in 0..<2_000_000 where session.isResolving { await Task.yield() }
        #expect(!session.isResolving)
    }
}

internal enum LinkedAppProjectError: Error, CustomStringConvertible {
    case unexpected(String)
    internal var description: String {
        switch self {
        case .unexpected(let outcome): "Unexpected linked open outcome: \(outcome)"
        }
    }
}
