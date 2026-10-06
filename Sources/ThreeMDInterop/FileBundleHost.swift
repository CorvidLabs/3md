import Foundation
import ThreeMD

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Explicit development host for the pure resolver. It reads only reachable regular files in one supplied folder.
@available(macOS 10.15.4, *)
enum FileBundleHost {
    static func run(_ arguments: [String]) throws {
        guard arguments.count == 6, arguments[0] == "--bundle", arguments[2] == "--folder", arguments[4] == "--output"
        else {
            throw InterchangeFailure.invalid(
                "Usage: threemd-interchange --bundle root.3md --folder /chosen/project --output /new/bundle.3md"
            )
        }
        guard arguments.allSatisfy({ !$0.utf8.contains(0) }) else {
            throw InterchangeFailure.invalid("File paths cannot contain NUL")
        }
        let folder = URL(fileURLWithPath: arguments[3], isDirectory: true).standardizedFileURL
        let rootDescriptor = try openDirectory(folder.path)
        defer { _ = close(rootDescriptor) }
        let rootPath = try DocumentFileComposition.resolvePath(arguments[1], relativeTo: "project-root")
        var pending = [rootPath]
        var loaded: [String: Data] = [:]
        var totalBytes = 0
        let limits = DocumentCompositionLimits.standard
        while let path = pending.popLast() {
            try Task.checkCancellation()
            if loaded[path] != nil { continue }
            guard loaded.count < limits.maximumDefinitions else { throw DocumentFileCompositionError.inputLimit }
            let bytes = try readSource(
                path,
                relativeTo: rootDescriptor,
                maximumBytes: limits.maximumProfileBytes - totalBytes
            )
            totalBytes += bytes.count
            loaded[path] = bytes
            let outer = try DocumentStorageCodec.decode(
                bytes,
                limits: .init(
                    maximumEncodedBytes: limits.maximumProfileBytes,
                    maximumDecodedBytes: limits.maximumProfileBytes,
                    maximumRecordBytes: limits.maximumProfileBytes
                )
            )
            let documents =
                try DocumentCompositionCodec.isComposition(outer)
                ? DocumentCompositionCodec.decode(bytes).entries.map(\.document) : [outer]
            for document in documents {
                for reference in try DocumentFileComposition.ledger(in: document) {
                    pending.append(try DocumentFileComposition.resolvePath(reference.source, relativeTo: path))
                }
            }
        }
        let resolved = try DocumentFileComposition.resolve(
            rootPath: rootPath,
            sources: loaded.map { .init(path: $0.key, data: $0.value) }
        )
        let destination = URL(fileURLWithPath: arguments[5]).standardizedFileURL
        guard ["3md", "3mdb"].contains(destination.pathExtension.lowercased()) else {
            throw InterchangeFailure.invalid("Use .3md or .3mdb for the new bundle")
        }
        let output: Data
        if destination.pathExtension.lowercased() == "3mdb" {
            output = try DocumentStorageCodec.encode(
                DocumentCompositionCodec.document(for: resolved.composition),
                format: .binary(compression: .none),
                limits: .init(
                    maximumEncodedBytes: limits.maximumProfileBytes,
                    maximumDecodedBytes: limits.maximumProfileBytes,
                    maximumPlanes: 1,
                    maximumRecordBytes: limits.maximumProfileBytes
                )
            )
        } else {
            output = try DocumentCompositionCodec.encode(resolved.composition)
        }
        try publish(output, to: destination)
        print(
            "Bundled \(resolved.resolvedPaths.count) files, \(resolved.composition.entries.count) definitions, \(output.count) bytes: \(destination.path)"
        )
    }

    private static func openDirectory(_ path: String, relativeTo parent: Int32 = AT_FDCWD) throws -> Int32 {
        try Task.checkCancellation()
        let descriptor = openat(parent, path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw systemFailure("Cannot open directory") }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
            information.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
        else {
            _ = close(descriptor)
            throw InterchangeFailure.invalid(
                "Choose a readable directory; the selected directory itself cannot be a symlink"
            )
        }
        return descriptor
    }

    private static func readSource(_ path: String, relativeTo root: Int32, maximumBytes: Int) throws -> Data {
        try Task.checkCancellation()
        // POSIX separators are scalar bytes, including when a combining mark follows a slash.
        let components = path.utf8.split(separator: 47, omittingEmptySubsequences: false).map {
            String(decoding: $0, as: UTF8.self)
        }
        guard let filename = components.last,
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.utf8.contains(0) })
        else { throw DocumentFileCompositionError.invalidPath(path) }
        var parent = root
        var ownsParent = false
        defer { if ownsParent { _ = close(parent) } }
        for component in components.dropLast() {
            let next = try openDirectory(component, relativeTo: parent)
            if ownsParent { _ = close(parent) }
            parent = next
            ownsParent = true
        }
        let descriptor = openat(parent, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)
        guard descriptor >= 0 else { throw systemFailure("Cannot open source: " + path) }
        defer { _ = close(descriptor) }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
            information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
        else { throw InterchangeFailure.invalid("Choose regular source files without symlinks: " + path) }
        guard information.st_size >= 0, information.st_size <= maximumBytes else {
            throw DocumentFileCompositionError.inputLimit
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count <= maximumBytes {
            try Task.checkCancellation()
            let allowance = min(buffer.count, maximumBytes + 1 - data.count)
            let count = buffer.withUnsafeMutableBytes { bytes in
                read(descriptor, bytes.baseAddress, allowance)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw systemFailure("Cannot read source: " + path)
            }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
        throw DocumentFileCompositionError.inputLimit
    }

    private static func publish(_ data: Data, to destination: URL) throws {
        let parent = try openDirectory(destination.deletingLastPathComponent().path)
        defer { _ = close(parent) }
        let name = destination.lastPathComponent
        let staging = ".3md-bundle-" + UUID().uuidString
        let descriptor = openat(
            parent,
            staging,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw systemFailure("Cannot create staging file") }
        defer { _ = close(descriptor) }
        var identity = stat()
        guard fstat(descriptor, &identity) == 0,
            identity.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
        else { throw InterchangeFailure.invalid("Invalid staging file") }
        defer { removeStaging(staging, relativeTo: parent, matching: identity) }
        var offset = 0
        while offset < data.count {
            try Task.checkCancellation()
            let count = data.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return write(descriptor, base.advanced(by: offset), min(65_536, data.count - offset))
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw systemFailure("Cannot write staging file")
            }
            guard count > 0 else { throw InterchangeFailure.invalid("Staging write made no progress") }
            offset += count
        }
        while fsync(descriptor) != 0 {
            try Task.checkCancellation()
            if errno != EINTR { throw systemFailure("Cannot synchronize staging file") }
        }
        try Task.checkCancellation()
        guard sameRegularFile(staging, relativeTo: parent, matching: identity) else {
            throw InterchangeFailure.invalid("Staging file changed before publication")
        }
        // linkat atomically refuses existing destinations and publishes a complete written file.
        // Darwin cannot link directly from this file descriptor. Before/after identity checks detect
        // replacement, but cannot promise verified-inode atomicity against a concurrent same-user rename.
        guard linkat(parent, staging, parent, name, 0) == 0 else { throw systemFailure("Cannot publish new bundle") }
        guard sameRegularFile(name, relativeTo: parent, matching: identity) else {
            // Do not delete an output inode that we cannot establish belongs to this operation.
            throw InterchangeFailure.invalid("Output identity changed during publication")
        }
    }

    private static func sameRegularFile(_ name: String, relativeTo parent: Int32, matching expected: stat) -> Bool {
        var actual = stat()
        return fstatat(parent, name, &actual, AT_SYMLINK_NOFOLLOW) == 0
            && actual.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
            && actual.st_dev == expected.st_dev && actual.st_ino == expected.st_ino
    }

    private static func removeStaging(_ name: String, relativeTo parent: Int32, matching identity: stat) {
        guard sameRegularFile(name, relativeTo: parent, matching: identity) else { return }
        // unlinkat without AT_REMOVEDIR cannot recursively remove a swapped directory or its contents.
        _ = unlinkat(parent, name, 0)
    }

    private static func systemFailure(_ operation: String) -> InterchangeFailure {
        let code = errno
        let explanation = strerror(code).map { String(cString: $0) } ?? "POSIX error \(code)"
        return .invalid(operation + ": " + explanation)
    }
}
