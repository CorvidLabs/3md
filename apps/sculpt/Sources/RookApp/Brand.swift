import AppKit
import RookCore
import SwiftUI

/// CorvidLabs palette values; the base app uses native system typography.
internal enum Brand {
    internal static let ink = color(light: 0x15181B, dark: 0xF4F3EF)
    internal static let secondary = color(light: 0x50555B, dark: 0xA3A199)
    internal static let paper = color(light: 0xFAF9F6, dark: 0x131619)
    internal static let accent = color(light: 0x0E6F66, dark: 0x45D0BC)

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1
                )
            }
        )
    }
}

extension AppAppearance {
    internal var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
