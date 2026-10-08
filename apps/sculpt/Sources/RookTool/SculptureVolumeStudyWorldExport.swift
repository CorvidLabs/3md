import CryptoKit
import Darwin
import Foundation
import RookSculpture
import ThreeMD

/// Explicit development fixtures. A world domain is distinct from a dense editable volume.
internal enum SculptureVolumeStudyWorldExport {
    internal struct Hooks: Sendable {
        var didCreateStaging: (@Sendable (URL) throws -> Void)? = nil
        var willPublish: (@Sendable (URL, URL) throws -> Void)? = nil
    }

    static func run(arguments: [String], hooks: Hooks = .init()) throws -> Data {
        try Task.checkCancellation()
        guard arguments.count == 2, arguments[0] == "--output", arguments[1].hasPrefix("/"),
            !arguments[1].utf8.contains(0)
        else { throw StudyError.usage }
        let output = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        guard output.lastPathComponent != "/" else { throw StudyError.usage }
        var directory = try StudyDirectory(output: output)
        var complete = false
        defer { directory.close(removeFiles: !complete) }
        try hooks.didCreateStaging?(directory.stagingURL)
        try Task.checkCancellation()
        try directory.verifyOwnership()
        let factories: [(String, () throws -> SculptureWorld)] = [
            ("solid-1024", SculptureVolumeStudyExamples.denseEquivalentWorld),
            ("landscape-1024", SculptureVolumeStudyExamples.landscapeWorld),
        ]
        var records: [WorldRecord] = []
        for (id, factory) in factories {
            try Task.checkCancellation()
            let (world, preparationMilliseconds) = try measured(factory)
            var files: [FileRecord] = []
            let (native, nativeEncodeMilliseconds) = try measured { try SculptureWorldCodec.encode(world) }
            let (nativeDecoded, nativeDecodeMilliseconds) = try measured { try SculptureWorldCodec.decode(native) }
            guard nativeDecoded == world else { throw StudyError.roundTrip }
            try directory.write(native, name: id + ".3md")
            files.append(
                .init(
                    name: id + ".3md",
                    format: "ascii-world-1",
                    data: native,
                    encodeMilliseconds: nativeEncodeMilliseconds,
                    decodeMilliseconds: nativeDecodeMilliseconds
                )
            )
            let (snapshot, captureMilliseconds) = try measured { try SculptureThreeMDCodec.capture(.world(world)) }
            for (suffix, format, name) in [
                ("portable.3md", DocumentStorageFormat.text, "ThreeMD portable text"),
                ("portable.3mdb", DocumentStorageFormat.binary(compression: .none), "ThreeMD binary uncompressed"),
            ] {
                let (data, encodeMilliseconds) = try measured {
                    try SculptureThreeMDCodec.encode(snapshot, format: format)
                }
                let (decoded, decodeMilliseconds) = try measured { try SculptureThreeMDCodec.decode(data) }
                guard decoded.scene == .world(world), decoded.revision == snapshot.revision else {
                    throw StudyError.roundTrip
                }
                let filename = id + "." + suffix
                try directory.write(data, name: filename)
                files.append(
                    .init(
                        name: filename,
                        format: name,
                        data: data,
                        encodeMilliseconds: encodeMilliseconds,
                        decodeMilliseconds: decodeMilliseconds
                    )
                )
            }
            let uniqueBytes = world.library.models.values.reduce(0) { total, model in
                if case .sculpture(let value) = model { return total + value.width * value.height * value.depth }
                return total
            }
            var occupancy: [String: Int64] = [:]
            for modelID in Set(world.instances.map(\.modelID)) {
                occupancy[modelID] = Int64(try world.library.expanded(modelID: modelID).occupiedCount)
            }
            let occupied = world.instances.reduce(Int64(0)) { $0 + (occupancy[$1.modelID] ?? 0) }
            records.append(
                .init(
                    id: id,
                    modelCount: world.library.models.count,
                    instanceCount: world.instances.count,
                    uniqueVoxelBytes: uniqueBytes,
                    repeatedOccupiedCells: occupied,
                    preparationMilliseconds: preparationMilliseconds,
                    captureMilliseconds: captureMilliseconds,
                    files: files
                )
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var receipt = try encoder.encode(Receipt(worlds: records))
        receipt.append(10)
        try directory.write(receipt, name: "worlds.json")
        try hooks.willPublish?(directory.stagingURL, directory.targetURL)
        try Task.checkCancellation()
        try directory.publish()
        complete = true
        return receipt
    }

    /// A complete staging tree is renamed once. Neither publication nor cleanup follows a replacement path.
    internal struct StudyDirectory {
        let parentDescriptor: Int32
        let descriptor: Int32
        let stagingName: String
        let targetName: String
        let stagingURL: URL
        let targetURL: URL
        let identity: stat
        private var ownedFiles: [OwnedFile] = []

        private struct OwnedFile {
            let name: String
            let identity: stat
        }

        init(output: URL) throws {
            let parent = output.deletingLastPathComponent().resolvingSymlinksInPath()
            let parentDescriptor = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard parentDescriptor >= 0 else { throw StudyError.destination }
            do {
                let targetName = output.lastPathComponent
                var existing = stat()
                guard fstatat(parentDescriptor, targetName, &existing, AT_SYMLINK_NOFOLLOW) != 0,
                    errno == ENOENT
                else { throw StudyError.destination }
                let stagingName = ".rook-world-study-\(UUID().uuidString)"
                guard mkdirat(parentDescriptor, stagingName, 0o700) == 0 else { throw StudyError.destination }
                let descriptor = openat(parentDescriptor, stagingName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard descriptor >= 0 else { throw StudyError.destination }
                var identity = stat()
                guard fstat(descriptor, &identity) == 0 else {
                    Darwin.close(descriptor)
                    throw StudyError.destination
                }
                self.parentDescriptor = parentDescriptor
                self.descriptor = descriptor
                self.stagingName = stagingName
                self.targetName = targetName
                stagingURL = parent.appendingPathComponent(stagingName, isDirectory: true)
                targetURL = parent.appendingPathComponent(targetName, isDirectory: true)
                self.identity = identity
            } catch {
                Darwin.close(parentDescriptor)
                throw error
            }
        }

        mutating func write(_ data: Data, name: String) throws {
            try Task.checkCancellation()
            try verifyOwnership()
            guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 128,
                !name.utf8.contains(0), !name.contains("/"), data.count <= SculptureWorldCodec.maximumBytes
            else { throw StudyError.destination }
            let fileDescriptor = openat(
                descriptor,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
            guard fileDescriptor >= 0 else { throw StudyError.destination }
            var fileIdentity = stat()
            guard fstat(fileDescriptor, &fileIdentity) == 0 else {
                Darwin.close(fileDescriptor)
                throw StudyError.destination
            }
            ownedFiles.append(.init(name: name, identity: fileIdentity))
            let file = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
            defer { try? file.close() }
            try Task.checkCancellation()
            try file.write(contentsOf: data)
            try file.synchronize()
            try file.close()
            try Task.checkCancellation()
        }

        func publish() throws {
            try Task.checkCancellation()
            try verifyOwnership()
            // RENAME_EXCL fails if a file, directory or link appeared at the target during preparation.
            guard renameatx_np(parentDescriptor, stagingName, parentDescriptor, targetName, UInt32(RENAME_EXCL)) == 0
            else {
                throw StudyError.destination
            }
        }

        func verifyOwnership() throws {
            guard stillOwnsStagingName() else { throw StudyError.destination }
        }

        func close(removeFiles: Bool) {
            if removeFiles {
                for file in ownedFiles {
                    var current = stat()
                    if fstatat(descriptor, file.name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                        current.st_dev == file.identity.st_dev, current.st_ino == file.identity.st_ino
                    {
                        _ = unlinkat(descriptor, file.name, 0)
                    }
                }
                if stillOwnsStagingName() { _ = unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR) }
            }
            Darwin.close(descriptor)
            Darwin.close(parentDescriptor)
        }

        private func stillOwnsStagingName() -> Bool {
            var current = stat()
            return fstatat(parentDescriptor, stagingName, &current, AT_SYMLINK_NOFOLLOW) == 0
                && current.st_dev == identity.st_dev && current.st_ino == identity.st_ino
                && current.st_mode & S_IFMT == S_IFDIR
        }
    }

    private static func measured<T>(_ body: () throws -> T) rethrows -> (T, Double) {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try body()
        let duration = start.duration(to: clock.now).components
        return (result, Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
    }

    private struct Receipt: Encodable {
        let schema = "sculpt-volume-world-study-1"
        let domainDimensions = [1024, 1024, 1024]
        let domainCellCount: Int64 = 1_073_741_824
        let individualEditingLimit = Sculpture.maximumDimension
        let note =
            "Address domain and repeated occupancy are distinct from a dense editable model. Single-run encode/decode measurements are CPU wall times."
        let worlds: [WorldRecord]
    }

    private struct WorldRecord: Encodable {
        let id: String
        let modelCount: Int
        let instanceCount: Int
        let uniqueVoxelBytes: Int
        let repeatedOccupiedCells: Int64
        let preparationMilliseconds: Double
        let captureMilliseconds: Double
        let files: [FileRecord]
    }

    private struct FileRecord: Encodable {
        let name: String
        let format: String
        let bytes: Int
        let sha256: String
        let encodeMilliseconds: Double
        let decodeMilliseconds: Double

        init(name: String, format: String, data: Data, encodeMilliseconds: Double, decodeMilliseconds: Double) {
            self.name = name
            self.format = format
            bytes = data.count
            sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            self.encodeMilliseconds = encodeMilliseconds
            self.decodeMilliseconds = decodeMilliseconds
        }
    }

    internal enum StudyError: Error, LocalizedError, Equatable {
        case usage, destination, roundTrip
        var errorDescription: String? {
            switch self {
            case .usage: "Usage: RookTool volume-worlds --output /absolute/new-directory"
            case .destination:
                "Choose a new study directory under an existing writable parent. Existing entries are never replaced."
            case .roundTrip: "A study world failed an exact supported-format round trip."
            }
        }
    }
}
