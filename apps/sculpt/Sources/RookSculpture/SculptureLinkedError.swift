import Foundation

/// An interim cap on linked resolution. Each holds until a tagged ThreeMD release bounds file intake itself.
public enum SculptureLinkedLimit: String, CaseIterable, Equatable, Sendable {
    /// UTF-8 bytes in one normalized project path.
    case pathBytes
    /// UTF-8 bytes in one path component.
    case componentBytes
    /// Reachable files, including the root.
    case files
    /// `3md-files` ledger entries across all reachable files.
    case links
    /// Files on one link path, including the root.
    case depth
    /// Bytes read across all reachable files, including the root.
    case definitionBytes
    /// Raw UTF-8 bytes in one `3md-files` value.
    case ledgerBytes

    /// A short phrase naming the limit and its unit for `maximum`.
    public func describe(_ maximum: Int) -> String {
        switch self {
        case .pathBytes: "\(Self.grouped(maximum)) bytes in a project path"
        case .componentBytes: "\(Self.grouped(maximum)) bytes in a file or folder name"
        case .files: "\(Self.grouped(maximum)) linked files"
        case .links: "\(Self.grouped(maximum)) links across all files"
        case .depth: "\(Self.grouped(maximum)) files on one link path"
        case .definitionBytes: "\(Self.size(maximum)) of linked files"
        case .ledgerBytes: "\(Self.size(maximum)) in one 3md-files ledger"
        }
    }

    /// `value` with comma thousands separators, independent of the locale.
    internal static func grouped(_ value: Int) -> String {
        var grouped = ""
        for (index, digit) in String(value).reversed().enumerated() {
            if index > 0, index.isMultiple(of: 3) { grouped.append(",") }
            grouped.append(digit)
        }
        return String(grouped.reversed())
    }

    private static func size(_ bytes: Int) -> String {
        if bytes >= 1_048_576, bytes.isMultiple(of: 1_048_576) { return "\(bytes / 1_048_576) MiB" }
        if bytes >= 1_024, bytes.isMultiple(of: 1_024) { return "\(bytes / 1_024) KiB" }
        return "\(grouped(bytes)) bytes"
    }
}

/// A file kind that a linked composition cannot use as a child. Detected by content, never by extension.
public enum SculptureLinkedFileKind: String, CaseIterable, CustomStringConvertible, Equatable, Sendable {
    /// Sculpt's native compact `.3mdb` voxel storage.
    case compactStorage
    /// A general ThreeMD binary container with compression.
    case compressedBinary
    /// A general ThreeMD binary container declaring the linked schema. Linked compositions are readable text.
    case binaryLinkedComposition
    /// A self-contained `ascii-composition-1` composition with an embedded library.
    case composition
    /// A sparse `ascii-world-1` or portable sparse world.
    case world
    /// A `3md-composition-1` profile, including self-contained bundles.
    case compositionProfile
    /// A Markdown or ThreeMD document without a Sculpt model schema.
    case markdown
    /// A document other than a linked composition that carries a `3md-files` ledger.
    case ledgerOutsideLinkedComposition

    /// A short noun phrase for messages.
    public var description: String {
        switch self {
        case .compactStorage: "a Sculpt compact 3mdb file"
        case .compressedBinary: "a compressed binary 3md file"
        case .binaryLinkedComposition: "a binary linked composition"
        case .composition: "an ascii-composition-1 composition with an embedded library"
        case .world: "a sparse world"
        case .compositionProfile: "a composition profile or self-contained bundle"
        case .markdown: "a Markdown document without a Sculpt model"
        case .ledgerOutsideLinkedComposition: "a file with a 3md-files ledger that is not a linked composition"
        }
    }
}

/// Linked composition and file-composition failures. Messages name project-relative paths only.
public enum SculptureLinkedError: Error, Equatable, LocalizedError, Sendable {
    /// Plain decoding found a readable linked root, which can only be read with its project folder.
    case needsProjectFolder
    /// A general binary document declares the linked schema. Linked roots are readable text only.
    case binaryLinkedRoot
    /// The root file is not inside the chosen project folder.
    case outsideProject
    /// A linked root breaks a schema rule. Resolution reports this through `file(path:reason:)`.
    case invalid(reason: String)
    /// A project file could not be read, decoded or used.
    case file(path: String, reason: String)
    /// `linkedFrom` links `path`, which the project folder does not contain.
    case missingFile(path: String, linkedFrom: String)
    /// `linkedFrom` links `link`, which is not a valid path inside the project folder.
    case invalidPath(link: String, linkedFrom: String)
    /// A reachable file has a kind that a linked composition cannot use.
    case unsupportedChild(path: String, kind: SculptureLinkedFileKind)
    /// Resolution exceeded an interim cap at `path`.
    case limit(kind: SculptureLinkedLimit, maximum: Int, path: String)
    /// Linked files form a cycle, listed from the first repeated file back to itself.
    case cycle([String])

    /// A human-readable explanation naming project-relative paths only.
    public var errorDescription: String? {
        switch self {
        case .needsProjectFolder:
            "This linked composition reads its models from files in a project folder. Open it and choose that folder."
        case .binaryLinkedRoot:
            "This binary file declares a linked composition. Linked compositions are read only from readable 3md text."
        case .outsideProject:
            "The linked composition is not inside the chosen project folder. Choose a folder that contains it."
        case .invalid(let reason): "Invalid linked composition. \(reason)"
        case .file(let path, let reason): "\(path): \(reason)"
        case .missingFile(let path, let linkedFrom):
            "\(linkedFrom) links \(path), which is not in the project folder."
        case .invalidPath(let link, let linkedFrom):
            "\(linkedFrom) links \"\(link)\", which is not a valid path inside the project folder."
        case .unsupportedChild(let path, let kind):
            "\(path) is \(kind.description). Link readable ascii-sculpture-1 voxel files, uncompressed binary voxel "
                + "files or other linked compositions."
        case .limit(let kind, let maximum, let path):
            "Linked composition limit reached at \(path): at most \(kind.describe(maximum))."
        case .cycle(let paths): "Linked files form a cycle: \(paths.joined(separator: " → "))."
        }
    }
}
