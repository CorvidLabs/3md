@preconcurrency import Foundation


// MARK: - Axis

/// The meaning assigned to a 3md document's third (Z) axis.
///
/// A 3md document is Markdown extended along a single free axis. That axis can
/// represent anything: the passage of time, stacked depth, named layers,
/// animation frames, or literal spatial position. `Axis` records the author's
/// intent so a viewer knows how to lay planes out.
public struct Axis: RawRepresentable, Sendable, Hashable, Codable {
    // MARK: - Properties

    /// The raw axis identifier, for example `"time"` or `"layer"`.
    public let rawValue: String

    // MARK: - Initializers

    /// Creates an axis from a raw identifier.
    /// - Parameter rawValue: The axis identifier. Leading and trailing
    ///   whitespace is trimmed; the value is lowercased for consistency.
    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // MARK: - Known Axes

    /// Z advances through time (planners, meeting agendas, timelines).
    public static let time = Axis(rawValue: "time")

    /// Z advances through stacked depth (foreground to background).
    public static let depth = Axis(rawValue: "depth")

    /// Z selects a named overlay layer (annotations, translations, variants).
    public static let layer = Axis(rawValue: "layer")

    /// Z advances through animation frames (art, motion, reveals).
    public static let frame = Axis(rawValue: "frame")

    /// Z is a literal spatial coordinate (scene authoring).
    public static let space = Axis(rawValue: "space")
}
