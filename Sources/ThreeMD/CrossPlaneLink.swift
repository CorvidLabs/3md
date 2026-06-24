// MARK: - CrossPlaneLink

/// A resolved cross-plane link extracted from a plane body.
///
/// Cross-plane links use the syntax `[[z=N]]` or `[[z=N|link text]]` inside a
/// plane body. Extraction walks every plane in source order and collects links
/// left to right within each body.
///
/// A link whose target decimal does not correspond to any plane in the document
/// is still returned; `targetExists` is `false` in that case, which lets
/// callers find dangling references without a separate pass.
public struct CrossPlaneLink: Sendable, Hashable, Codable {
    // MARK: - Properties

    /// The Z position of the plane that contains this link.
    public let sourceZ: Double

    /// The Z position named by the link target.
    public let targetZ: Double

    /// The optional link text between the pipe and `]]`, or `nil` when the
    /// pipe is absent. An explicit empty string (`[[z=N|]]`) is `""`, not `nil`.
    public let text: String?

    /// Whether a plane with `z == targetZ` exists in the document.
    ///
    /// Uses the same `Double` equality as duplicate-plane detection.
    public let targetExists: Bool

    // MARK: - Initializers

    /// Creates a cross-plane link record.
    /// - Parameters:
    ///   - sourceZ: The Z position of the containing plane.
    ///   - targetZ: The Z position named by the link.
    ///   - text: Optional display text from the `|text` suffix.
    ///   - targetExists: Whether the target plane exists in the document.
    public init(sourceZ: Double, targetZ: Double, text: String?, targetExists: Bool) {
        self.sourceZ = sourceZ
        self.targetZ = targetZ
        self.text = text
        self.targetExists = targetExists
    }
}
