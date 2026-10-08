import RookCore
import Testing

@Test func unknownOrMissingStoredAppearanceUsesSystem() {
    #expect(AppAppearance(storedValue: nil) == .system)
    #expect(AppAppearance(storedValue: "removed-preference") == .system)
    #expect(AppAppearance(storedValue: "") == .system)
}

@Test func knownAppearanceValuesSurviveStorageRoundTrip() {
    for appearance in AppAppearance.allCases {
        #expect(AppAppearance(storedValue: appearance.rawValue) == appearance)
    }
}
