// MARK: - ThreeMDAnchor

/// Utilities for generating stable HTML anchors for 3md planes.
///
/// ``HTMLRenderer`` uses these helpers for plane section IDs, and
/// ``MarkdownRenderer`` uses them for rendered cross-plane link targets. Apps
/// embedding rendered 3md can use the same helpers to generate matching links.
public enum ThreeMDAnchor: Sendable {
    /// Returns the stable HTML `id` used for a plane at the given Z position.
    /// - Parameter z: The plane's Z position.
    /// - Returns: An anchor ID such as `"plane-z-1.5"`.
    public static func id(forZ z: Double) -> String {
        "plane-z-\(z.formatted3MD())"
    }

    /// Returns the stable HTML fragment link used for a plane at the given Z position.
    /// - Parameter z: The plane's Z position.
    /// - Returns: An anchor href such as `"#plane-z-1.5"`.
    public static func href(forZ z: Double) -> String {
        "#\(id(forZ: z))"
    }
}
