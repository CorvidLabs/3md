// MARK: - Plane

/// A single slice of a 3md document positioned along the Z axis.
///
/// Each plane carries a Markdown `body` plus a position. `z` is required and
/// orders planes along the document's axis; `x` and `y` are optional in-plane
/// offsets for viewers that lay content out spatially. Any additional
/// `key=value` pairs on the directive are preserved in `attributes`.
public struct Plane: Sendable, Hashable, Codable {
    // MARK: - Properties

    /// Position along the document's Z axis.
    public let z: Double

    /// Optional human-readable label, for example a weekday or frame name.
    public let label: String?

    /// Optional horizontal offset within the plane.
    public let x: Double?

    /// Optional vertical offset within the plane.
    public let y: Double?

    /// Any extra directive attributes that are not `z`, `x`, `y`, or `label`.
    public let attributes: [String: String]

    /// The Markdown content of this plane, with surrounding blank lines trimmed.
    public let body: String

    // MARK: - Initializers

    /// Creates a plane.
    /// - Parameters:
    ///   - z: Position along the Z axis.
    ///   - label: Optional human-readable label.
    ///   - x: Optional horizontal offset.
    ///   - y: Optional vertical offset.
    ///   - attributes: Extra directive attributes.
    ///   - body: Markdown content for the plane.
    public init(
        z: Double,
        label: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        attributes: [String: String] = [:],
        body: String
    ) {
        self.z = z
        self.label = label
        self.x = x
        self.y = y
        self.attributes = attributes
        self.body = body
    }
}
