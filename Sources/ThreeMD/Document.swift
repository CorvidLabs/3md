// MARK: - Document

/// A parsed 3md document: Markdown extended along one free Z axis.
///
/// A document begins with a required YAML-style frontmatter block declaring the
/// format version and what the Z axis means, followed by zero or more planes.
/// A plain Markdown file with no `@plane` directives parses as a single plane
/// at `z = 0`.
public struct Document: Sendable, Hashable, Codable {
    // MARK: - Properties

    /// The declared 3md format version, for example `"0.1"`.
    public let version: String

    /// What the Z axis represents in this document.
    public let axis: Axis

    /// Optional document title from the frontmatter.
    public let title: String?

    /// Any frontmatter keys other than `3md`, `axis`, and `title`.
    public let metadata: [String: String]

    /// Markdown content that appears after the frontmatter but before the first
    /// plane, if any.
    public let preamble: String?

    /// The document's planes, in source order.
    public let planes: [Plane]

    // MARK: - Initializers

    /// Creates a document.
    /// - Parameters:
    ///   - version: The 3md format version.
    ///   - axis: What the Z axis represents.
    ///   - title: Optional document title.
    ///   - metadata: Extra frontmatter keys.
    ///   - preamble: Content before the first plane.
    ///   - planes: The document's planes, in source order.
    public init(
        version: String,
        axis: Axis,
        title: String? = nil,
        metadata: [String: String] = [:],
        preamble: String? = nil,
        planes: [Plane]
    ) {
        self.version = version
        self.axis = axis
        self.title = title
        self.metadata = metadata
        self.preamble = preamble
        self.planes = planes
    }

    // MARK: - Public Methods

    /// The planes ordered by ascending Z position.
    public var planesByZ: [Plane] {
        planes.sorted { $0.z < $1.z }
    }

    /// Returns the first plane whose `z` equals the given value.
    /// - Parameter z: The Z position to look up.
    /// - Returns: The matching plane, or `nil` if none exists.
    public func plane(atZ z: Double) -> Plane? {
        planes.first { $0.z == z }
    }
}
