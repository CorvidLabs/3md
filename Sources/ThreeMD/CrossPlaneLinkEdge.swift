// MARK: - CrossPlaneLinkEdge

/// A summarized directed edge in a document's cross-plane link graph.
///
/// Multiple `[[z=N]]` links from the same source plane to the same target plane
/// collapse into one edge with an incremented ``count``. Edges preserve first
/// encounter order from the source document.
public struct CrossPlaneLinkEdge: Sendable, Hashable, Codable {
    // MARK: - Properties

    /// The Z position of the plane that contains the link.
    public let sourceZ: Double

    /// The target Z position named by the link.
    public let targetZ: Double

    /// Whether a plane with `z == targetZ` exists in the document.
    public let targetExists: Bool

    /// Number of links collapsed into this edge.
    public let count: Int

    // MARK: - Initializers

    /// Creates a cross-plane link graph edge.
    /// - Parameters:
    ///   - sourceZ: The Z position of the containing plane.
    ///   - targetZ: The target Z position.
    ///   - targetExists: Whether the target plane exists.
    ///   - count: Number of links represented by this edge.
    public init(sourceZ: Double, targetZ: Double, targetExists: Bool, count: Int) {
        self.sourceZ = sourceZ
        self.targetZ = targetZ
        self.targetExists = targetExists
        self.count = count
    }
}
