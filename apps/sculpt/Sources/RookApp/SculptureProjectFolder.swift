import Darwin
import Foundation
import RookSculpture

/// The project folder a linked composition was opened with. The grant lives in memory for one linked session only:
/// nothing about it is stored, and it needs no entitlement beyond user-selected files.
internal struct SculptureProjectFolder: Equatable, Sendable {
    // MARK: - Properties

    /// The URL the folder panel returned. It carries the security scope for the session.
    internal let grant: URL
    /// The folder's standardized path with symbolic links resolved, where every confined read starts.
    internal let path: String

    /// The folder's name for messages. Absolute locations are never shown.
    internal var name: String { grant.lastPathComponent }


    // MARK: - Initializers

    internal init(_ grant: URL) {
        self.grant = grant
        path = grant.resolvingSymlinksInPath().standardizedFileURL.path
    }


    // MARK: - Internal Methods

    /// The NFC project path of `root`, which must lie inside this folder. Paths are compared by their standardized,
    /// symlink-resolved components while both security scopes are held.
    /// - Throws: `SculptureLinkedError.outsideProject` when `root` is not strictly inside the folder.
    internal func projectPath(of root: URL) throws -> String {
        let rootScoped = root.startAccessingSecurityScopedResource()
        defer { if rootScoped { root.stopAccessingSecurityScopedResource() } }
        let folderScoped = grant.startAccessingSecurityScopedResource()
        defer { if folderScoped { grant.stopAccessingSecurityScopedResource() } }
        let folderComponents = Self.components(grant)
        let rootComponents = Self.components(root)
        guard rootComponents.count > folderComponents.count,
            Array(rootComponents.prefix(folderComponents.count)) == folderComponents
        else { throw SculptureLinkedError.outsideProject }
        return rootComponents.dropFirst(folderComponents.count).joined(separator: "/")
    }

    /// One resolution attempt with its own confined reader. The folder's security scope is held until the detached
    /// work finishes or is cancelled. The root is read through the same reader as every linked file.
    /// - Parameters:
    ///   - rootPath: The root's project path.
    ///   - diagnose: Whether a failure is examined link by link for the repair view.
    /// - Returns: The resolution, or the failure with its diagnosis when one was requested.
    /// - Throws: `CancellationError` only.
    internal func attempt(rootPath: String, diagnose: Bool) async throws -> SculptureLinkedAttempt {
        let scoped = grant.startAccessingSecurityScopedResource()
        defer { if scoped { grant.stopAccessingSecurityScopedResource() } }
        let reader = SculptureProjectReader(folderPath: path)
        let worker = Task.detached(priority: .userInitiated) { () async throws -> SculptureLinkedAttempt in
            do {
                return .resolved(try await SculptureLinkedResolver.resolve(rootPath: rootPath, read: reader.reader))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let message = SculptureDiagnosticMessage.describe(error)
                guard diagnose else { return .failed(message: message, repair: nil) }
                let repair = try await SculptureLinkedRepair.diagnose(
                    rootPath: rootPath,
                    failure: error,
                    reader: reader
                )
                return .failed(message: message, repair: repair)
            }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }


    // MARK: - Private Methods

    private static func components(_ url: URL) -> [String] {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents.map(\.precomposedStringWithCanonicalMapping)
    }
}

/// The outcome of one resolution attempt.
internal enum SculptureLinkedAttempt: Sendable {
    case resolved(SculptureLinkedResolution)
    /// `message` names the failing project file. `repair` is present when a diagnosis was requested.
    case failed(message: String, repair: SculptureLinkedRepair?)
}

/// The identity of an opened file, used to catch a second spelling of a file already read.
private struct SculptureFileIdentity: Hashable, Sendable {
    let device: dev_t
    let inode: ino_t
}

/// Reads project files for linked resolution, confined to one folder.
///
/// Each read opens the folder and every directory component with `O_DIRECTORY | O_NOFOLLOW`, then the file with
/// `O_NOFOLLOW`, so no symbolic link is followed anywhere below the folder. Paths are split on the `/` byte, never on
/// Swift characters, so every `openat` receives exactly one component. Only regular files with one link are read,
/// components whose first byte is a period are refused, and a file reached under a second spelling (a case alias)
/// is refused by device and inode. Reads are bounded by the remaining budget the resolver passes. One reader serves
/// one resolution attempt.
internal actor SculptureProjectReader {
    // MARK: - Properties

    private let folderPath: String
    private var identities: [SculptureFileIdentity: String] = [:]
    private var totalBytes = 0

    /// The reader to hand to `SculptureLinkedResolver`.
    internal nonisolated var reader: SculptureLinkedReader {
        { path, maximumBytes in try await self.read(path, maximumBytes: maximumBytes) }
    }

    /// Bytes returned by this reader so far.
    internal var bytesRead: Int { totalBytes }


    // MARK: - Initializers

    internal init(folderPath: String) {
        self.folderPath = folderPath
    }


    // MARK: - Internal Methods

    /// Reads `path` under the folder, returning at most `maximumBytes + 1` bytes.
    /// - Throws: `SculptureLinkedError.file` naming `path` for a confinement refusal, `POSIXError(.ENOENT)` for a
    ///   missing file, another `POSIXError` for a failed read, or `CancellationError`.
    internal func read(_ path: String, maximumBytes: Int) throws -> Data {
        try Task.checkCancellation()
        let components = try Self.components(of: path)
        let budget = min(max(maximumBytes, 0), SculptureLinkedResolver.maximumDefinitionBytes)
        var directory = Darwin.open(folderPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else {
            throw SculptureLinkedError.file(
                path: path,
                reason: "could not be read because the project folder is unavailable."
            )
        }
        defer { Darwin.close(directory) }
        for component in components.dropLast() {
            let next = try Self.openComponent(
                component,
                in: directory,
                flags: O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
                path: path,
                isFolder: true
            )
            Darwin.close(directory)
            directory = next
        }
        guard let name = components.last else { throw Self.invalid(path) }
        let descriptor = try Self.openComponent(
            name,
            in: directory,
            flags: O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW,
            path: path,
            isFolder: false
        )
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0 else { throw Self.posix(errno) }
        guard information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw SculptureLinkedError.file(path: path, reason: "is not a regular file.")
        }
        guard information.st_nlink == 1 else {
            throw SculptureLinkedError.file(
                path: path,
                reason: "has more than one hard link. Linked files must have exactly one name."
            )
        }
        let identity = SculptureFileIdentity(device: information.st_dev, inode: information.st_ino)
        if let other = identities[identity], other != path {
            throw SculptureLinkedError.file(
                path: path,
                reason: "names the same file as \(other). Use one spelling for each linked file."
            )
        }
        identities[identity] = path
        guard information.st_size <= budget else {
            throw SculptureLinkedError.limit(
                kind: .definitionBytes,
                maximum: SculptureLinkedResolver.maximumDefinitionBytes,
                path: path
            )
        }
        var data = Data()
        while data.count <= budget {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: min(65_536, budget + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        totalBytes += data.count
        return data
    }


    // MARK: - Private Methods

    /// Splits a normalized project path on the `/` byte. Splitting by Swift character would let a scalar that joins
    /// its neighbor, such as a prepended U+0600 before `/` or a combining mark after it, hide a separator inside one
    /// component. Empty components, NUL bytes and components whose first byte is a period are refused.
    private static func components(of path: String) throws -> [String] {
        let parts = path.utf8.split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && !$0.contains(0) }) else { throw invalid(path) }
        if let hidden = parts.first(where: { $0.first == UInt8(ascii: ".") }) {
            throw SculptureLinkedError.file(
                path: path,
                reason: "is in or is the hidden item \"\(String(decoding: hidden, as: UTF8.self))\". "
                    + "Hidden files and folders are not read."
            )
        }
        // Each part ends at an ASCII separator, so it is whole UTF-8 and decodes to exactly its own bytes.
        return parts.map { String(decoding: $0, as: UTF8.self) }
    }

    /// Opens exactly one component below `directory`. A name holding a `/` or NUL byte could reach past one
    /// component, so it is refused before the system call.
    /// - Returns: The open descriptor.
    /// - Throws: `SculptureLinkedError.file` for an invalid name or a refused item, or a `POSIXError`.
    private static func openComponent(
        _ component: String,
        in directory: Int32,
        flags: Int32,
        path: String,
        isFolder: Bool
    ) throws -> Int32 {
        guard !component.isEmpty, !component.utf8.contains(UInt8(ascii: "/")), !component.utf8.contains(0) else {
            throw invalid(path)
        }
        let descriptor = Darwin.openat(directory, component, flags)
        guard descriptor >= 0 else {
            throw refusal(errno, component: component, in: directory, path: path, isFolder: isFolder)
        }
        return descriptor
    }

    private static func invalid(_ path: String) -> SculptureLinkedError {
        .file(path: path, reason: "is not a valid project path.")
    }

    /// Explains a failed open. A symbolic link is named; a missing item or a file where a folder was expected is
    /// reported as missing, so the resolver names the file that links it.
    private static func refusal(
        _ code: Int32,
        component: String,
        in directory: Int32,
        path: String,
        isFolder: Bool
    ) -> any Error {
        var information = stat()
        if fstatat(directory, component, &information, AT_SYMLINK_NOFOLLOW) == 0 {
            if information.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) {
                let item = isFolder ? "goes through the symbolic link \"\(component)\"" : "is a symbolic link"
                return SculptureLinkedError.file(
                    path: path,
                    reason: "\(item). Linked files are read without following symbolic links."
                )
            }
            if isFolder, information.st_mode & mode_t(S_IFMT) != mode_t(S_IFDIR) { return posix(ENOENT) }
            if !isFolder, information.st_mode & mode_t(S_IFMT) != mode_t(S_IFREG) {
                return SculptureLinkedError.file(path: path, reason: "is not a regular file.")
            }
        }
        return posix(code == ENOTDIR ? ENOENT : code)
    }

    private static func posix(_ code: Int32) -> any Error {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
