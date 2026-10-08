import Foundation
import RookSculpture

/// User-selected file access stays in the native host. Decoding, fit and capacity rules live in RookSculpture
/// so the development tools apply the same checks.
internal enum SculptureInsertionFiles {
    static let maximumFiles = SculptureInsertionPlan.maximumFiles
    static let maximumBytes = SculptureInsertionPlan.maximumBytes
    static let maximumDiscoveryEntries = SculptureInsertionPlan.maximumDiscoveryEntries

    /// Reads chosen files in natural filename order in two passes. The admit pass checks the batch against `plan`
    /// and sums every file's size, so a later oversized file is refused by name before any earlier file is read or
    /// decoded. The read pass then reads each file and checks its fit right after it is decoded.
    static func read(_ urls: [URL], plan: SculptureInsertionPlan = .init()) throws -> [SculptureInsertionInput] {
        try Task.checkCancellation()
        var plan = plan
        try plan.admitFileCount(urls.count)
        let ordered = urls.sorted { SculptureInsertionPlan.precedes($0.path, $1.path) }
        var sizes: [Int] = []
        for url in ordered {
            do {
                try Task.checkCancellation()
                let size = try withAccess(to: url) {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
                        size >= 0
                    else { throw Failure.regularFile }
                    return size
                }
                try plan.admitBytes(size, source: url.lastPathComponent)
                sizes.append(size)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw sourceFailure(error, at: url)
            }
        }
        var inputs: [SculptureInsertionInput] = []
        for (url, size) in zip(ordered, sizes) {
            do {
                try Task.checkCancellation()
                let bytes = try withAccess(to: url) {
                    try SculptureOpenedScene.readData(url, maximumBytes: max(size, 1))
                }
                inputs.append(try plan.admit(bytes, source: url.lastPathComponent))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw sourceFailure(error, at: url)
            }
        }
        return inputs
    }

    private static func withAccess<Output>(to url: URL, _ body: () throws -> Output) rethrows -> Output {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    /// Folder selection grants this folder only. Symlinks, packages and hidden entries are skipped.
    static func readFolder(_ folder: URL, plan: SculptureInsertionPlan = .init()) throws -> [SculptureInsertionInput] {
        try Task.checkCancellation()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let root: URLResourceValues
        do { root = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) } catch {
            throw sourceFailure(error, at: folder)
        }
        guard root.isDirectory == true, root.isSymbolicLink != true else {
            throw sourceFailure(Failure.folder, at: folder)
        }
        var enumerationFailure: (any Error)?
        guard
            let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    enumerationFailure = sourceFailure(error, at: url); return false
                }
            )
        else { throw sourceFailure(Failure.folder, at: folder) }
        var visited = 0
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            visited += 1
            guard visited <= maximumDiscoveryEntries else {
                throw SculptureInsertionError.source(
                    name: folder.lastPathComponent,
                    reason: SculptureInsertionError.tooManyDiscoveredEntries(maximum: maximumDiscoveryEntries)
                        .localizedDescription
                )
            }
            let values: URLResourceValues
            do { values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) } catch {
                throw sourceFailure(error, at: url)
            }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true, SculptureInsertionPlan.isSupportedFile(pathExtension: url.pathExtension) {
                files.append(url)
            }
        }
        if let enumerationFailure { throw enumerationFailure }
        guard !files.isEmpty else { throw sourceFailure(Failure.emptyFolder, at: folder) }
        do { try plan.admitFileCount(files.count) } catch let error as SculptureInsertionError {
            throw SculptureInsertionError.source(name: folder.lastPathComponent, reason: error.localizedDescription)
        }
        return try read(files, plan: plan)
    }

    private static func sourceFailure(_ error: any Error, at url: URL) -> any Error {
        // Refusals from the shared plan already name their file and limit.
        if let error = error as? SculptureInsertionError { return error }
        let reason: String
        if error is CocoaError || (error as NSError).domain == NSPOSIXErrorDomain {
            reason = "This file could not be read. Choose a readable model file."
        } else {
            reason = SculptureDiagnosticMessage.describe(error)
                .replacingOccurrences(of: url.path, with: url.lastPathComponent)
                .replacingOccurrences(of: url.absoluteString, with: url.lastPathComponent)
        }
        return SculptureInsertionError.source(name: url.lastPathComponent, reason: reason)
    }

    /// Host-level refusals. Capacity, fit and naming refusals are `SculptureInsertionError` values.
    enum Failure: Error, LocalizedError, Sendable {
        case regularFile, folder, emptyFolder, parentChanged
        var errorDescription: String? {
            switch self {
            case .regularFile: "Choose regular 3md or 3mdb files, without symbolic links."
            case .folder: "Choose a readable model folder."
            case .emptyFolder: "This folder has no regular 3md or 3mdb files."
            case .parentChanged: "The parent changed while insertion was preparing. Insert the files again."
            }
        }
    }
}
