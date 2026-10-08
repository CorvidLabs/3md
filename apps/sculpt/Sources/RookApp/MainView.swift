import SwiftUI

internal struct MainView: View {
    let workspace: SculptureWorkspace
    internal var body: some View {
        SculptureEditor(workspace: workspace)
    }
}
