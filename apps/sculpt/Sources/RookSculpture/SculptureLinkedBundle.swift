import Foundation
import ThreeMD

/// The storage of a self-contained bundle. Both reopen without the project folder.
public enum SculptureLinkedBundleFormat: String, CaseIterable, Equatable, Sendable {
    /// Canonical readable `3md-composition-1` text.
    case readable
    /// The general ThreeMD binary container without compression.
    case binary
}

/// Self-contained bundles of a resolved linked composition. Each definition is stored once; nothing is linked.
public enum SculptureLinkedBundle {
    // MARK: - Public Methods

    /// Encodes the exact resolved graph with Sculpt's portable limits.
    /// - Parameters:
    ///   - resolution: A completed linked resolution.
    ///   - format: Readable text or uncompressed binary.
    /// - Returns: Bytes that `decode` and ordinary content-detected opening read without the project folder.
    public static func encode(
        _ resolution: SculptureLinkedResolution,
        format: SculptureLinkedBundleFormat
    ) throws -> Data {
        try Task.checkCancellation()
        let limits = try SculptureThreeMDPolicy.composition()
        let documentLimits = try SculptureThreeMDPolicy.document()
        let data: Data
        switch format {
        case .readable:
            data = try DocumentCompositionCodec.encode(
                resolution.bundle,
                limits: limits,
                documentLimits: documentLimits
            )
        case .binary:
            let document = try DocumentCompositionCodec.document(
                for: resolution.bundle,
                limits: limits,
                documentLimits: documentLimits
            )
            data = try DocumentStorageCodec.encode(
                document,
                format: .binary(compression: .none),
                limits: documentLimits
            )
        }
        try Task.checkCancellation()
        return data
    }

    /// Decodes a bundle through the existing content-detected portable path. `source-file` is never followed.
    /// - Returns: The self-contained composition and its retained portable identities.
    public static func decode(_ data: Data) throws -> SculptureThreeMDSnapshot {
        try SculptureThreeMDCodec.decode(data)
    }
}
