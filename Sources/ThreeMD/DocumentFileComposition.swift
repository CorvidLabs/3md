import Foundation

/// Caller-supplied bytes within a project. Resolving never reads the path from disk.
public struct DocumentFileSource: Equatable, Sendable {
    /// A project-relative name, normalized only when the source collection is resolved.
    public let path: String
    /// Readable or supported general binary ThreeMD bytes supplied by the host.
    public let data: Data

    /// Retains source bytes without decoding or performing resource access.
    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

/// A host-interpreted glyph and its relative filename from an ordinary document's ledger.
public struct DocumentFileReference: Equatable, Sendable {
    /// The single printable ASCII character interpreted by the consuming host.
    public let glyph: String
    /// A filename relative to the document containing this ledger.
    public let source: String

    /// Creates a reference value without resolving its filename.
    public init(glyph: String, source: String) {
        self.glyph = glyph
        self.source = source
    }
}

/// A portable, self-contained graph and the normalized files that contributed to it.
public struct DocumentFileCompositionResult: Equatable, Sendable {
    /// The normalized project-relative root filename.
    public let rootPath: String
    /// Complete bundled definitions and remapped references, independent of their source folder.
    public let composition: DocumentComposition
    /// Maps each reachable normalized filename to its bundled root definition ID.
    public let fileRootIDs: [String: String]
    /// Reachable normalized filenames ordered by Unicode scalar values.
    public let resolvedPaths: [String]

    /// Retains one resolved graph and its source-to-definition mapping.
    public init(
        rootPath: String,
        composition: DocumentComposition,
        fileRootIDs: [String: String],
        resolvedPaths: [String]
    ) {
        self.rootPath = rootPath
        self.composition = composition
        self.fileRootIDs = fileRootIDs
        self.resolvedPaths = resolvedPaths
    }
}

/// File-intake failures. Existing storage, graph and cancellation failures keep their original types.
public enum DocumentFileCompositionError: Error, Equatable, LocalizedError, Sendable {
    case invalidPath(String)
    case duplicatePath(String)
    case invalidLedger(String)
    case invalidGlyph(String)
    case missingFile(String)
    case inputLimit

    /// A human-readable explanation of the failed file intake.
    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path): "Invalid project-relative file path: \(path)."
        case .duplicatePath(let path): "More than one supplied file normalizes to \(path)."
        case .invalidLedger(let detail): "Invalid 3md-files ledger: \(detail)."
        case .invalidGlyph(let glyph): "Use one printable ASCII character for the file glyph: \(glyph)."
        case .missingFile(let path): "The supplied project is missing file \(path)."
        case .inputLimit: "The supplied file composition exceeds its input policy."
        }
    }
}

/// Resolves explicit in-memory file sources, preserving documents and nested graph references without flattening.
public enum DocumentFileComposition {
    /// Returns glyph-ordered references. No metadata means an empty ledger; duplicate JSON keys are rejected.
    public static func ledger(in document: Document) throws -> [DocumentFileReference] {
        try DocumentStorageCancellation.check()
        guard let source = document.metadata["3md-files"] else { return [] }
        guard source.utf8.count <= DocumentDecodeLimits.standard.maximumRecordBytes else {
            throw DocumentFileCompositionError.inputLimit
        }
        var scanner = DocumentFileLedgerScanner(bytes: Array(source.utf8))
        return try scanner.references()
    }

    /// Resolves POSIX dot/parent segments against a containing filename without escaping the project root.
    public static func resolvePath(_ source: String, relativeTo containingFile: String) throws -> String {
        try DocumentStorageCancellation.check()
        // The bound charges the caller's original spelling; discovery charges already normalized owners.
        try checkPathBytes(source, containingBytes: containingFile.utf8.count)
        return try normalize(source, base: ContainingFile(normalizedPath: try normalize(containingFile)))
    }

    /// Only reachable sources decode. Re-resolving after supplied child bytes change refreshes the snapshot.
    public static func resolve(
        rootPath: String,
        sources: [DocumentFileSource],
        limits: DocumentCompositionLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> DocumentFileCompositionResult {
        try DocumentStorageCancellation.check()
        guard sources.count <= limits.maximumDefinitions else { throw DocumentFileCompositionError.inputLimit }
        guard rootPath.utf8.count <= limits.maximumProfileBytes else { throw DocumentFileCompositionError.inputLimit }
        var pathBytes = rootPath.utf8.count
        for source in sources {
            try DocumentStorageCancellation.check()
            guard source.path.utf8.count <= limits.maximumProfileBytes - pathBytes else {
                throw DocumentFileCompositionError.inputLimit
            }
            pathBytes += source.path.utf8.count
        }
        let normalizedRoot = try normalize(rootPath)
        var indexed: [String: Data] = [:]
        for source in sources {
            try DocumentStorageCancellation.check()
            let path = try normalize(source.path)
            guard indexed.updateValue(source.data, forKey: path) == nil else {
                throw DocumentFileCompositionError.duplicatePath(path)
            }
        }
        var resolver = FileResolver(sources: indexed, limits: limits, documentLimits: documentLimits)
        _ = try resolver.discover(normalizedRoot, depth: 1)
        return try resolver.bundle(rootPath: normalizedRoot)
    }

    /// A normalized containing filename whose directory boundaries are located once and reused for every reference.
    private struct ContainingFile {
        /// The normalized containing filename.
        let path: String
        /// UTF-8 bytes in the containing filename, charged against each reference's record bound.
        let pathBytes: Int
        /// The end of each directory segment: the scalar index of every separator in `path`.
        let directoryEnds: [String.UnicodeScalarView.Index]

        /// A project root with no containing directory.
        static let projectRoot = ContainingFile(path: "", pathBytes: 0, directoryEnds: [])

        private init(path: String, pathBytes: Int, directoryEnds: [String.UnicodeScalarView.Index]) {
            self.path = path
            self.pathBytes = pathBytes
            self.directoryEnds = directoryEnds
        }

        /// Records separator positions in an already normalized filename.
        init(normalizedPath: String) {
            path = normalizedPath
            pathBytes = normalizedPath.utf8.count
            directoryEnds = normalizedPath.unicodeScalars.indices.filter { normalizedPath.unicodeScalars[$0] == "/" }
        }

        /// The first `count` directory segments, joined by their original separators.
        func directory(keeping count: Int) -> Substring.UnicodeScalarView {
            path.unicodeScalars[path.unicodeScalars.startIndex..<directoryEnds[count - 1]]
        }
    }

    /// The standalone record bound: the containing filename and reference together fit one record.
    private static func checkPathBytes(_ source: String, containingBytes: Int) throws {
        let maximum = DocumentDecodeLimits.standard.maximumRecordBytes
        guard containingBytes <= maximum, source.utf8.count <= maximum - containingBytes else {
            throw DocumentFileCompositionError.inputLimit
        }
    }

    /// Resolves one reference against a containing file whose path was normalized once.
    private static func resolve(_ source: String, in containing: ContainingFile) throws -> String {
        try DocumentStorageCancellation.check()
        try checkPathBytes(source, containingBytes: containing.pathBytes)
        return try normalize(source, base: containing)
    }

    private static func normalize(_ source: String, base: ContainingFile = .projectRoot) throws -> String {
        try DocumentStorageCancellation.check()
        let normalized = source.precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty, normalized.unicodeScalars.first?.value != 47,
            normalized.unicodeScalars.last?.value != 47,
            !normalized.unicodeScalars.contains(where: {
                $0.value < 32 || $0.value == 127 || $0.value == 92 || $0.value == 58
            })
        else { throw DocumentFileCompositionError.invalidPath(source) }
        // One stack: the kept base directory segments followed by the source's own segments.
        var kept = base.directoryEnds.count
        var components: [Substring.UnicodeScalarView] = []
        for segment in normalized.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false) {
            try DocumentStorageCancellation.check()
            guard !segment.isEmpty else { throw DocumentFileCompositionError.invalidPath(source) }
            if segment.elementsEqual(".".unicodeScalars) { continue }
            if segment.elementsEqual("..".unicodeScalars) {
                if !components.isEmpty {
                    components.removeLast()
                } else if kept > 0 {
                    kept -= 1
                } else {
                    throw DocumentFileCompositionError.invalidPath(source)
                }
            } else {
                components.append(segment)
            }
        }
        guard kept > 0 || !components.isEmpty else { throw DocumentFileCompositionError.invalidPath(source) }
        var result = kept > 0 ? String(base.directory(keeping: kept)) : ""
        for component in components {
            if !result.isEmpty { result.unicodeScalars.append("/") }
            result.unicodeScalars.append(contentsOf: component)
        }
        return result
    }

    /// UTF-8 code unit order is Unicode scalar order; comparison stops at the first difference without copying.
    private static func pathPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    private struct LocalFile {
        let rootID: String
        let entries: [DocumentEntry]
        let ledgers: [String: [DocumentFileReference]]
        let depth: Int
    }

    private struct FileResolver {
        // File dependencies can originate in disconnected imported entries. This fixed safety cap
        // bounds discovery recursion; the caller's graph depth is validated after entry remapping.
        private static let maximumDiscoveryDepth = DocumentCompositionLimits.standard.maximumDepth
        let sources: [String: Data]
        let limits: DocumentCompositionLimits
        let documentLimits: DocumentDecodeLimits
        private var files: [String: LocalFile] = [:]
        private var visiting: Set<String> = []
        private var encodedBytes = 0
        private var definitions = 0
        private var references = 0

        init(sources: [String: Data], limits: DocumentCompositionLimits, documentLimits: DocumentDecodeLimits) {
            self.sources = sources
            self.limits = limits
            self.documentLimits = documentLimits
        }

        mutating func discover(_ path: String, depth: Int) throws -> LocalFile {
            try DocumentStorageCancellation.check()
            guard !visiting.contains(path) else { throw DocumentCompositionError.cycle(path) }
            guard depth <= Self.maximumDiscoveryDepth else { throw DocumentCompositionError.depthExceeded }
            if let file = files[path] {
                guard file.depth <= Self.maximumDiscoveryDepth - depth + 1 else {
                    throw DocumentCompositionError.depthExceeded
                }
                return file
            }
            guard let data = sources[path] else { throw DocumentFileCompositionError.missingFile(path) }
            guard data.count <= limits.maximumProfileBytes - encodedBytes else {
                throw DocumentFileCompositionError.inputLimit
            }
            encodedBytes += data.count
            visiting.insert(path)
            // A composition envelope has its own profile record ceiling. Its child definitions retain
            // the caller's stricter document policy; ordinary sources are decoded again under that policy.
            let intakeLimits = try DocumentDecodeLimits(
                maximumEncodedBytes: limits.maximumProfileBytes,
                maximumDecodedBytes: limits.maximumProfileBytes,
                maximumLines: DocumentDecodeLimits.standard.maximumLines,
                maximumPlanes: DocumentDecodeLimits.standard.maximumPlanes,
                maximumRecordBytes: limits.maximumProfileBytes
            )
            let document = try DocumentStorageCodec.decode(data, limits: intakeLimits)
            let entries: [DocumentEntry]
            let rootID: String
            if DocumentCompositionCodec.isComposition(document) {
                let composition = try DocumentCompositionCodec.decode(
                    document,
                    limits: limits,
                    documentLimits: documentLimits
                )
                entries = composition.entries
                rootID = composition.rootID
            } else {
                rootID = "root"
                entries = [.init(id: rootID, document: try DocumentStorageCodec.decode(data, limits: documentLimits))]
            }
            guard entries.count <= limits.maximumDefinitions - definitions else {
                throw DocumentCompositionError.tooManyDefinitions
            }
            definitions += entries.count
            var ledgers: [String: [DocumentFileReference]] = [:]
            var fileDepth = 1
            let containing = ContainingFile(normalizedPath: path)
            for entry in entries.sorted(by: { $0.id < $1.id }) {
                try DocumentStorageCancellation.check()
                let ledger = try DocumentFileComposition.ledger(in: entry.document)
                guard entry.references.count <= limits.maximumReferences - references else {
                    throw DocumentCompositionError.tooManyReferences
                }
                references += entry.references.count
                guard ledger.count <= limits.maximumReferences - references else {
                    throw DocumentCompositionError.tooManyReferences
                }
                references += ledger.count
                var resolved: [DocumentFileReference] = []
                for reference in ledger {
                    let target = try DocumentFileComposition.resolve(reference.source, in: containing)
                    let child = try discover(target, depth: depth + 1)
                    fileDepth = max(fileDepth, child.depth + 1)
                    guard fileDepth <= Self.maximumDiscoveryDepth else { throw DocumentCompositionError.depthExceeded }
                    resolved.append(.init(glyph: reference.glyph, source: target))
                }
                ledgers[entry.id] = resolved
            }
            visiting.remove(path)
            let file = LocalFile(rootID: rootID, entries: entries, ledgers: ledgers, depth: fileDepth)
            files[path] = file
            return file
        }

        func bundle(rootPath: String) throws -> DocumentFileCompositionResult {
            let paths = files.keys.sorted(by: DocumentFileComposition.pathPrecedes)
            // One map per file, keyed by local ID, so remapping never hashes or copies a full path per reference.
            var ordered: [(file: LocalFile, entries: [DocumentEntry], ids: [String: String])] = []
            var roots: [String: String] = [:]
            var nextID = 0
            for path in paths {
                try DocumentStorageCancellation.check()
                guard let file = files[path] else { continue }
                let sorted = file.entries.sorted(by: { $0.id < $1.id })
                var ids: [String: String] = [:]
                for entry in sorted {
                    let digits = String(nextID)
                    let id = "file-" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
                    ids[entry.id] = id
                    if entry.id == file.rootID { roots[path] = id }
                    nextID += 1
                }
                ordered.append((file, sorted, ids))
            }
            var entries: [DocumentEntry] = []
            for (file, sorted, ids) in ordered {
                for entry in sorted {
                    try DocumentStorageCancellation.check()
                    guard let id = ids[entry.id] else {
                        throw DocumentCompositionError.missingRoot(entry.id)
                    }
                    var references = try entry.references.map { reference in
                        guard let target = ids[reference.targetID] else {
                            throw DocumentCompositionError.missingTarget(from: entry.id, target: reference.targetID)
                        }
                        return DocumentReference(targetID: target, attributes: reference.attributes)
                    }
                    for reference in file.ledgers[entry.id] ?? [] {
                        guard let target = roots[reference.source] else {
                            throw DocumentFileCompositionError.missingFile(reference.source)
                        }
                        references.append(
                            .init(
                                targetID: target,
                                attributes: ["glyph": reference.glyph, "source-file": reference.source]
                            )
                        )
                    }
                    var metadata = entry.document.metadata
                    metadata.removeValue(forKey: "3md-files")
                    let document = Document(
                        version: entry.document.version,
                        axis: entry.document.axis,
                        title: entry.document.title,
                        metadata: metadata,
                        preamble: entry.document.preamble,
                        planes: entry.document.planes
                    )
                    entries.append(.init(id: id, document: document, references: references))
                }
            }
            guard let rootID = roots[rootPath] else { throw DocumentFileCompositionError.missingFile(rootPath) }
            let composition = try DocumentComposition(
                rootID: rootID,
                entries: entries,
                limits: limits,
                documentLimits: documentLimits
            )
            // Construction validates graph work; the existing writer additionally validates the complete profile budget.
            _ = try DocumentCompositionCodec.encode(composition, limits: limits, documentLimits: documentLimits)
            try DocumentStorageCancellation.check()
            return .init(rootPath: rootPath, composition: composition, fileRootIDs: roots, resolvedPaths: paths)
        }
    }
}
