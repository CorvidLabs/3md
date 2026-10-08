import Foundation
import ThreeMD

/// The same editable scene values used by Sculpt, independent of the selected storage format.
public enum SculptureScene: Equatable, Sendable {
    case voxels(Sculpture)
    case composition(SculptureComposition)
    case world(SculptureWorld)

    public var title: String {
        switch self {
        case .voxels(let value): value.title
        case .composition(let value): value.title
        case .world(let value): value.title
        }
    }
}

/// An immutable portable scene retaining the original plane and reference identities.
public struct SculptureThreeMDSnapshot: Equatable, Sendable {
    public let scene: SculptureScene
    public let diagnostics: DocumentDiagnosticReport
    internal let storage: Storage

    public var revision: DocumentRevision {
        switch storage {
        case .document(let value): value.revision
        case .composition(let value): value.revision
        }
    }

    internal enum Storage: Equatable, Sendable {
        case document(DocumentSnapshot)
        case composition(DocumentCompositionSnapshot)
    }
}

/// Application schema failures retain structured evidence for native and development callers.
public struct SculptureThreeMDError: Error, LocalizedError, Equatable, Sendable {
    public let diagnostic: DocumentDiagnostic
    public var errorDescription: String? { diagnostic.message }

    internal init(_ message: String, path: String? = nil) {
        diagnostic = .init(code: .invalidComposition, message: message, path: path)
    }
}

internal enum SculptureThreeMDPolicy {
    static func document() throws -> DocumentDecodeLimits {
        try .init(
            maximumEncodedBytes: SculptureCodec.maximumBytes,
            maximumDecodedBytes: SculptureCodec.maximumBytes,
            maximumLines: 100_000,
            maximumPlanes: Sculpture.maximumDimension,
            maximumRecordBytes: SculptureCodec.maximumBytes
        )
    }

    static func composition() throws -> DocumentCompositionLimits {
        try .init(
            maximumDefinitions: SculptureComposition.maximumModels + 1,
            maximumReferences: 8_192,
            maximumDepth: SculptureComposition.maximumDepth + 1
        )
    }

    static func editing() throws -> DocumentEditLimits {
        try .init(maximumPayloadBytes: SculptureCodec.maximumBytes, maximumDiagnosticBytes: SculptureCodec.maximumBytes)
    }
}
