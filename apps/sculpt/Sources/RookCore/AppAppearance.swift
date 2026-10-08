/// A non-sensitive preference shared by the main window and Settings.
public enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .system
    }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
