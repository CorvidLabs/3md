import AppKit
import RookCore
import SwiftUI

@main
internal struct RookApp: App {
    @NSApplicationDelegateAdaptor(RookDelegate.self) private var delegate
    @AppStorage("rook.appearance") private var storedAppearance = AppAppearance.system.rawValue
    @State private var workspace = SculptureWorkspace()

    private var appearance: AppAppearance { AppAppearance(storedValue: storedAppearance) }

    internal var body: some Scene {
        Window("Sculpt.3md", id: "main") {
            MainView(workspace: workspace)
                .onAppear { delegate.workspace = workspace }
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            SculptureDocumentCommands()
            SculptureHistoryCommands(workspace: workspace)
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }

        MenuBarExtra("Sculpt.3md", systemImage: "cube.transparent") {
            RookMenu()
        }
    }
}

internal final class RookDelegate: NSObject, NSApplicationDelegate {
    var workspace: SculptureWorkspace?

    internal func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    internal func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard workspace?.isDirty == true || workspace?.referenceDraftIsDirty == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit with unsaved changes?"
        alert.informativeText = "Cancel and save the sculpture or reference draft to keep your changes."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard and quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

internal struct RookMenu: View {
    @Environment(\.openWindow) private var openWindow

    internal var body: some View {
        Button("Show Sculpt.3md") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink()
        Divider()
        Button("Quit Sculpt.3md") {
            NSApp.terminate(nil)
        }
    }
}
