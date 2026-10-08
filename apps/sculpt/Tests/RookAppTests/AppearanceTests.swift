import RookCore
import SwiftUI
import Testing

@testable import RookApp

@Test func systemPreferenceDefersToMacAppearance() {
    #expect(AppAppearance.system.colorScheme == nil)
    #expect(AppAppearance.light.colorScheme == .light)
    #expect(AppAppearance.dark.colorScheme == .dark)
    #expect(AppAppearance(storedValue: "obsolete-value").colorScheme == nil)
}
