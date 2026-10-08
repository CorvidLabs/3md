import Foundation
import ThreeMD

/// Reads one project file for linked resolution. The host owns all file access and confinement.
///
/// `path` is a normalized, NFC, project-relative path with `/` separators. Return the file's bytes. Reading at most
/// `maximumBytes + 1` bytes is enough: a result longer than `maximumBytes` is refused by name. Throw
/// `SculptureLinkedError` to refuse a file in the host's own words; a missing file may also be reported with
/// `ENOENT` or `CocoaError.fileReadNoSuchFile`. Other errors are reported without their text, which can name
/// absolute locations.
public typealias SculptureLinkedReader = @Sendable (_ path: String, _ maximumBytes: Int) async throws -> Data

/// A resolved linked composition and the facts about the files that produced it. Nothing partial is published.
public struct SculptureLinkedResolution: Equatable, Sendable {
    // MARK: - Properties

    /// The resolved composition. Model IDs are ThreeMD bundle IDs such as `file-000000`.
    public let composition: SculptureComposition
    /// The normalized project-relative root path.
    public let rootPath: String
    /// Every reachable normalized path, ordered by Unicode scalar values.
    public let resolvedPaths: [String]
    /// Model ID to the project path of the file that defines it.
    public let modelPaths: [String: String]
    /// Project path to the lowercase hexadecimal SHA256 of the exact bytes read.
    public let digests: [String: String]
    /// The self-contained ThreeMD graph used for bundles.
    internal let bundle: DocumentComposition

    /// The resolved composition as a scene.
    public var scene: SculptureScene { .composition(composition) }
}

/// Interim resolution caps. Tests lower them to check each boundary; hosts always use `standard`.
internal struct SculptureLinkedLimits: Equatable, Sendable {
    internal var pathBytes = 1_024
    internal var componentBytes = 255
    internal var files = 64
    internal var links = 512
    internal var depth = 16
    internal var definitionBytes = 16 * 1_048_576
    internal var ledgerBytes = SculptureLinkedCodec.maximumLedgerBytes

    internal static let standard = Self()

    internal func maximum(_ kind: SculptureLinkedLimit) -> Int {
        switch kind {
        case .pathBytes: pathBytes
        case .componentBytes: componentBytes
        case .files: files
        case .links: links
        case .depth: depth
        case .definitionBytes: definitionBytes
        case .ledgerBytes: ledgerBytes
        }
    }

    internal func exceeded(_ kind: SculptureLinkedLimit, at path: String) -> SculptureLinkedError {
        .limit(kind: kind, maximum: maximum(kind), path: path)
    }
}

/// Pure, reachable-only resolution of a linked root through a host-supplied reader.
public enum SculptureLinkedResolver {
    // MARK: - Properties

    /// UTF-8 bytes in one normalized project path.
    public static let maximumPathBytes = SculptureLinkedLimits.standard.pathBytes
    /// UTF-8 bytes in one path component.
    public static let maximumComponentBytes = SculptureLinkedLimits.standard.componentBytes
    /// Reachable files, including the root.
    public static let maximumFiles = SculptureLinkedLimits.standard.files
    /// Ledger entries across all reachable files.
    public static let maximumLinks = SculptureLinkedLimits.standard.links
    /// Files on one link path, including the root.
    public static let maximumDepth = SculptureLinkedLimits.standard.depth
    /// Bytes read across all reachable files, including the root.
    public static let maximumDefinitionBytes = SculptureLinkedLimits.standard.definitionBytes


    // MARK: - Public Methods

    /// Resolves `rootData`, a readable linked root at `rootPath` inside the project, reading only reachable files.
    ///
    /// The walk is depth-first in glyph order. Each file is read once, classified by content and checked against the
    /// interim caps; cancellation is checked between files. ThreeMD then resolves exactly the reachable set with
    /// Sculpt's limits. Positional bundle IDs in failures are reported as project paths.
    /// - Parameters:
    ///   - rootPath: The root's project-relative path, normalized here.
    ///   - rootData: The root's bytes, read by the host through the same confinement as `read`.
    ///   - read: Reads one reachable project file.
    /// - Returns: The resolved composition and its file facts.
    /// - Throws: `SculptureLinkedError` naming project paths, or `CancellationError`.
    public static func resolve(
        rootPath: String,
        rootData: Data,
        read: SculptureLinkedReader
    ) async throws -> SculptureLinkedResolution {
        try await resolve(rootPath: rootPath, rootData: rootData, limits: .standard, read: read)
    }

    /// Reads the root at `rootPath` through `read`, then resolves it as `resolve(rootPath:rootData:read:)` does.
    /// The root counts toward the same byte budget as every linked file.
    public static func resolve(
        rootPath: String,
        read: SculptureLinkedReader
    ) async throws -> SculptureLinkedResolution {
        try Task.checkCancellation()
        let root = try normalizedRoot(rootPath, limits: .standard)
        let data: Data
        do { data = try await read(root, maximumDefinitionBytes) } catch {
            throw LinkedWalk.readFailure(error, path: root, linkedFrom: nil)
        }
        return try await resolve(rootPath: root, rootData: data, limits: .standard, read: read)
    }


    // MARK: - Internal Methods

    internal static func resolve(
        rootPath: String,
        rootData: Data,
        limits: SculptureLinkedLimits,
        read: SculptureLinkedReader
    ) async throws -> SculptureLinkedResolution {
        try Task.checkCancellation()
        let root = try normalizedRoot(rootPath, limits: limits)
        var walk = LinkedWalk(limits: limits)
        try await walk.start(rootPath: root, data: rootData, read: read)
        try Task.checkCancellation()
        let ordered = walk.sources.sorted { $0.key.unicodeScalars.lexicographicallyPrecedes($1.key.unicodeScalars) }
        // Every reachable file is one ordinary document, so ThreeMD numbers them in this order.
        let predicted = Dictionary(ordered.enumerated().map { (bundleID($0.offset), $0.element.key) }) { first, _ in
            first
        }
        let result: DocumentFileCompositionResult
        do {
            result = try DocumentFileComposition.resolve(
                rootPath: root,
                sources: ordered.map { DocumentFileSource(path: $0.key, data: $0.value) },
                limits: SculptureThreeMDPolicy.composition(),
                documentLimits: SculptureThreeMDPolicy.document()
            )
        } catch {
            throw mapped(error, paths: predicted, rootPath: root, limits: limits)
        }
        let modelPaths = Dictionary(result.fileRootIDs.map { ($0.value, $0.key) }) { first, _ in first }
        let scene: SculptureScene
        do { scene = try SculptureThreeMDCodec.scene(from: result.composition) } catch {
            throw mapped(error, paths: modelPaths, rootPath: root, limits: limits)
        }
        guard case .composition(let composition) = scene else {
            throw SculptureLinkedError.file(path: root, reason: "did not resolve to a composition.")
        }
        try Task.checkCancellation()
        return SculptureLinkedResolution(
            composition: composition,
            rootPath: result.rootPath,
            resolvedPaths: result.resolvedPaths,
            modelPaths: modelPaths,
            digests: walk.sources.mapValues(digest),
            bundle: result.composition
        )
    }

    /// Classifies one file by content. Only readable voxels, uncompressed binary voxels and readable linked roots
    /// are usable; a linked root returns its validated ledger.
    internal static func classify(path: String, data: Data, limits: SculptureLinkedLimits) throws -> LinkedContent {
        try Task.checkCancellation()
        if SculptureBinaryCodec.hasMagic(data) { throw unsupported(path, .compactStorage) }
        let binary = DocumentStorageCodec.isBinary(data)
        if binary, data.count > 11, data[data.index(data.startIndex, offsetBy: 11)] != DocumentCompression.none.rawValue
        {
            throw unsupported(path, .compressedBinary)
        }
        let document: Document
        do { document = try DocumentStorageCodec.decode(data, limits: SculptureThreeMDPolicy.document()) } catch {
            if error is CancellationError { throw error }
            // Markdown without ThreeMD frontmatter, or with frontmatter but no `3md` version, is generic Markdown.
            if case DocumentStorageError.invalidText(let parse) = error,
                parse == .missingFrontmatter || parse == .missingVersion
            {
                throw unsupported(path, .markdown)
            }
            throw SculptureLinkedError.file(path: path, reason: SculptureDiagnosticMessage.describe(error))
        }
        if DocumentCompositionCodec.isComposition(document) { throw unsupported(path, .compositionProfile) }
        let schema = document.metadata["scene-schema"]
        if schema == SculptureLinkedCodec.schema {
            if binary { throw unsupported(path, .binaryLinkedComposition) }
            if let raw = document.metadata[SculptureLinkedCodec.ledgerKey], raw.utf8.count > limits.ledgerBytes {
                throw limits.exceeded(.ledgerBytes, at: path)
            }
            do { return .linked(try SculptureLinkedCodec.composition(from: document).files) } catch {
                if error is CancellationError { throw error }
                throw SculptureLinkedError.file(path: path, reason: SculptureDiagnosticMessage.describe(error))
            }
        }
        switch schema {
        case "ascii-composition-1": throw unsupported(path, .composition)
        case "ascii-world-1", "ascii-world-2": throw unsupported(path, .world)
        default: break
        }
        if document.metadata[SculptureLinkedCodec.ledgerKey] != nil {
            throw unsupported(path, .ledgerOutsideLinkedComposition)
        }
        guard schema == "ascii-sculpture-1" else { throw unsupported(path, .markdown) }
        do { _ = try SculptureThreeMDCodec.portableVoxel(document) } catch {
            if error is CancellationError { throw error }
            throw SculptureLinkedError.file(path: path, reason: SculptureDiagnosticMessage.describe(error))
        }
        return .voxel
    }


    // MARK: - Private Methods

    private static func normalizedRoot(_ path: String, limits: SculptureLinkedLimits) throws -> String {
        try checkPathCaps(path, at: path, limits: limits)
        let root: String
        do {
            // A containing file at the project root leaves `path` relative to the project folder itself.
            root = try DocumentFileComposition.resolvePath(path, relativeTo: "root.3md")
        } catch {
            if error is CancellationError { throw error }
            throw rootRefusal(path)
        }
        try checkPathCaps(root, at: root, limits: limits)
        return root
    }

    /// Explains a root path that ThreeMD refused. Only an empty, absolute or escaping root, or one that names the
    /// folder itself, is outside the project. A root inside it is named, with the character a linked path cannot
    /// hold when that is the cause.
    private static func rootRefusal(_ path: String) -> SculptureLinkedError {
        let scalars = path.precomposedStringWithCanonicalMapping.unicodeScalars
        // ThreeMD paths refuse the same scalars: controls, DEL, the backslash and the colon.
        if let refused = scalars.first(where: { $0.value < 32 || $0.value == 127 || $0 == "\\" || $0 == ":" }) {
            let character =
                switch refused {
                case ":": "a colon, which Finder shows as \"/\""
                case "\\": "a backslash"
                default: "a control character"
                }
            return .file(
                path: path,
                reason: "has a file or folder name containing \(character). Linked composition paths cannot contain "
                    + "colons, backslashes or control characters. Rename it."
            )
        }
        guard scalars.first.map({ $0 != "/" }) ?? false else { return .outsideProject }
        var depth = 0
        for segment in scalars.split(separator: "/", omittingEmptySubsequences: false) {
            switch String(segment) {
            case ".": continue
            case "..":
                depth -= 1
                if depth < 0 { return .outsideProject }
            default: depth += 1
            }
        }
        guard depth > 0 else { return .outsideProject }
        return .file(path: path, reason: "is not a valid project path.")
    }

    fileprivate static func checkPathCaps(_ value: String, at path: String, limits: SculptureLinkedLimits) throws {
        guard value.utf8.count <= limits.pathBytes else { throw limits.exceeded(.pathBytes, at: path) }
        for component in value.utf8.split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: false)
        where component.count > limits.componentBytes {
            throw limits.exceeded(.componentBytes, at: path)
        }
    }

    private static func unsupported(_ path: String, _ kind: SculptureLinkedFileKind) -> SculptureLinkedError {
        .unsupportedChild(path: path, kind: kind)
    }

    private static func bundleID(_ index: Int) -> String {
        let digits = String(index)
        return "file-" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    private static func digest(_ data: Data) -> String {
        SculptureSHA256.hex(data)
    }

    /// Reports ThreeMD and scene failures by project path. Positional bundle IDs are replaced by their files.
    private static func mapped(
        _ error: any Error,
        paths: [String: String],
        rootPath: String,
        limits: SculptureLinkedLimits
    ) -> any Error {
        if error is CancellationError || error is SculptureLinkedError { return error }
        let path = { (id: String) in paths[id] ?? id }
        if let error = error as? DocumentCompositionError {
            switch error {
            case .cycle(let id): return SculptureLinkedError.cycle([path(id)])
            case .missingTarget(let source, let target):
                return SculptureLinkedError.missingFile(path: path(target), linkedFrom: path(source))
            case .tooManyDefinitions: return limits.exceeded(.files, at: rootPath)
            case .tooManyReferences: return limits.exceeded(.links, at: rootPath)
            case .depthExceeded: return limits.exceeded(.depth, at: rootPath)
            case .definitionBytesExceeded, .profileBytesExceeded: return limits.exceeded(.definitionBytes, at: rootPath)
            case .traversalOccurrencesExceeded: return occurrencesExceeded(at: rootPath)
            default: break
            }
        }
        if case DocumentFileCompositionError.missingFile(let missing) = error {
            return SculptureLinkedError.missingFile(path: missing, linkedFrom: rootPath)
        }
        if let error = error as? SculptureCompositionError {
            switch error {
            case .childDoesNotFit(let id):
                return SculptureLinkedError.file(
                    path: path(id),
                    reason: "does not fit the tile block that links it, including any quarter-turns. "
                        + "Enlarge that composition's tiles or link a smaller model."
                )
            case .cyclicReference(let id): return SculptureLinkedError.cycle([path(id)])
            case .tooManyModels: return limits.exceeded(.files, at: rootPath)
            case .excessiveDepth: return limits.exceeded(.depth, at: rootPath)
            default: break
            }
        }
        var reason = SculptureDiagnosticMessage.describe(error)
        var named = rootPath
        var earliest: String.Index?
        for (id, file) in paths {
            guard let range = reason.range(of: id) else { continue }
            if earliest.map({ range.lowerBound < $0 }) ?? true {
                earliest = range.lowerBound
                named = file
            }
        }
        for (id, file) in paths { reason = reason.replacingOccurrences(of: id, with: file) }
        return SculptureLinkedError.file(path: named, reason: reason)
    }

    /// ThreeMD counts every ledger entry along every nested link path, placed or not, so links repeated through
    /// several levels can exceed its occurrence limit while every interim cap holds. No portable save applies.
    private static func occurrencesExceeded(at rootPath: String) -> SculptureLinkedError {
        let maximum =
            (try? SculptureThreeMDPolicy.composition().maximumTraversalOccurrences)
            ?? DocumentCompositionLimits.standard.maximumTraversalOccurrences
        return .file(
            path: rootPath,
            reason: "reaches more than \(SculptureLinkedLimit.grouped(maximum)) nested link occurrences. Each "
                + "3md-files entry counts once on every link path that reaches its file, placed or not. Remove "
                + "repeated or unplaced links, or link fewer levels."
        )
    }
}

/// The usable content of one reachable file.
internal enum LinkedContent: Equatable, Sendable {
    case voxel
    case linked([UInt8: String])
}

/// Depth-first discovery state. Each reachable file is read once and kept for the single ThreeMD resolution.
private struct LinkedWalk {
    fileprivate let limits: SculptureLinkedLimits
    fileprivate private(set) var sources: [String: Data] = [:]
    private var heights: [String: Int] = [:]
    private var visiting: [String] = []
    private var bytes = 0
    private var links = 0

    fileprivate init(limits: SculptureLinkedLimits) { self.limits = limits }

    fileprivate mutating func start(rootPath: String, data: Data, read: SculptureLinkedReader) async throws {
        try charge(data.count, path: rootPath)
        let files: [UInt8: String]
        do {
            guard
                case .linked(let ledger) = try SculptureLinkedResolver.classify(
                    path: rootPath,
                    data: data,
                    limits: limits
                )
            else {
                throw SculptureLinkedError.file(path: rootPath, reason: "is a voxel model, not a linked composition.")
            }
            files = ledger
        } catch SculptureLinkedError.unsupportedChild(_, let kind) {
            let reason =
                kind == .binaryLinkedComposition
                ? SculptureLinkedError.binaryLinkedRoot.localizedDescription
                : "is \(kind.description), not a linked composition."
            throw SculptureLinkedError.file(path: rootPath, reason: reason)
        }
        sources[rootPath] = data
        _ = try await visit(rootPath, files: files, depth: 1, read: read)
    }

    /// Returns the number of files on the longest link path starting at `path`, including itself.
    private mutating func visit(
        _ path: String,
        files: [UInt8: String],
        depth: Int,
        read: SculptureLinkedReader
    ) async throws -> Int {
        try Task.checkCancellation()
        guard files.count <= limits.links - links else { throw limits.exceeded(.links, at: path) }
        links += files.count
        visiting.append(path)
        var height = 1
        for glyph in files.keys.sorted() {
            guard let source = files[glyph] else { continue }
            let target = try targetPath(source, linkedFrom: path)
            let childHeight: Int
            if let index = visiting.firstIndex(of: target) {
                throw SculptureLinkedError.cycle(Array(visiting[index...]) + [target])
            } else if let known = heights[target] {
                guard depth + known <= limits.depth else { throw limits.exceeded(.depth, at: target) }
                childHeight = known
            } else {
                childHeight = try await discover(target, linkedFrom: path, depth: depth + 1, read: read)
            }
            height = max(height, childHeight + 1)
        }
        visiting.removeLast()
        heights[path] = height
        return height
    }

    private mutating func discover(
        _ path: String,
        linkedFrom parent: String,
        depth: Int,
        read: SculptureLinkedReader
    ) async throws -> Int {
        guard sources.count < limits.files else { throw limits.exceeded(.files, at: path) }
        guard depth <= limits.depth else { throw limits.exceeded(.depth, at: path) }
        let remaining = limits.definitionBytes - bytes
        guard remaining > 0 else { throw limits.exceeded(.definitionBytes, at: path) }
        try Task.checkCancellation()
        let data: Data
        do { data = try await read(path, remaining) } catch {
            throw Self.readFailure(error, path: path, linkedFrom: parent)
        }
        try Task.checkCancellation()
        try charge(data.count, path: path)
        sources[path] = data
        switch try SculptureLinkedResolver.classify(path: path, data: data, limits: limits) {
        case .voxel:
            heights[path] = 1
            return 1
        case .linked(let files):
            return try await visit(path, files: files, depth: depth, read: read)
        }
    }

    private mutating func charge(_ count: Int, path: String) throws {
        guard count <= limits.definitionBytes - bytes else { throw limits.exceeded(.definitionBytes, at: path) }
        bytes += count
    }

    /// Applies the path caps to the raw link before ThreeMD normalizes it, then to the normalized project path.
    private func targetPath(_ source: String, linkedFrom path: String) throws -> String {
        try SculptureLinkedResolver.checkPathCaps(source, at: path, limits: limits)
        let target: String
        do { target = try DocumentFileComposition.resolvePath(source, relativeTo: path) } catch {
            if error is CancellationError { throw error }
            throw SculptureLinkedError.invalidPath(link: source, linkedFrom: path)
        }
        try SculptureLinkedResolver.checkPathCaps(target, at: path, limits: limits)
        return target
    }

    /// Maps a host reader failure. A missing root, which no file links, is reported as a file failure.
    fileprivate static func readFailure(_ error: any Error, path: String, linkedFrom parent: String?) -> any Error {
        if error is CancellationError || error is SculptureLinkedError { return error }
        let failure = error as NSError
        if isMissing(failure) {
            guard let parent else {
                return SculptureLinkedError.file(path: path, reason: "is not in the project folder.")
            }
            return SculptureLinkedError.missingFile(path: path, linkedFrom: parent)
        }
        // System descriptions can name absolute locations, so only the POSIX reason is kept.
        if failure.domain == NSPOSIXErrorDomain, let code = Int32(exactly: failure.code) {
            return SculptureLinkedError.file(
                path: path,
                reason: "could not be read: \(String(cString: strerror(code)))."
            )
        }
        return SculptureLinkedError.file(path: path, reason: "could not be read.")
    }

    private static func isMissing(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) { return true }
        if error.domain == NSCocoaErrorDomain,
            [CocoaError.fileReadNoSuchFile.rawValue, CocoaError.fileNoSuchFile.rawValue].contains(error.code)
        {
            return true
        }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return isMissing(underlying)
    }
}
