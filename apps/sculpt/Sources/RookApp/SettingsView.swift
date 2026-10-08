import RookCore
import SwiftUI

internal struct SettingsView: View {
    @AppStorage("rook.appearance") private var storedAppearance = AppAppearance.system.rawValue

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(storedValue: storedAppearance) },
            set: { storedAppearance = $0.rawValue }
        )
    }

    internal var body: some View {
        Form {
            Picker("Appearance", selection: appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 400)
        .tint(Brand.accent)
    }
}
