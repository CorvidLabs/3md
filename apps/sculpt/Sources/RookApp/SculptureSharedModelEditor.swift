import Foundation
import Observation
import RookRendering
import RookSculpture
import SwiftUI

/// Child editing is isolated until a validated candidate replaces the complete parent document.
@MainActor
@Observable
internal final class SculptureSharedModelSession: Identifiable {
    let id = UUID()
    let modelID: String
    let source: Sculpture
    let parentRevision: UUID
    let workspace = SculptureWorkspace()
    var error: String?
    /// True while Apply validates a captured copy of the model. Editing and history stay locked until it ends,
    /// whether the change comes from this editor's controls or from the Edit menu.
    var isApplying = false

    init(modelID: String, source: Sculpture, parentRevision: UUID) {
        self.modelID = modelID
        self.source = source
        self.parentRevision = parentRevision
        workspace.replace(with: source, opened: true)
    }
}

/// Reuses painting components without inheriting the detached document's file and export handlers.
@MainActor
internal struct SculptureSharedModelEditor: View {
    let session: SculptureSharedModelSession
    let cancel: @MainActor () -> Void
    let apply: @MainActor () async -> Bool
    @State private var applying: Task<Void, Never>?
    private var isApplying: Bool { session.isApplying }

    var body: some View {
        @Bindable var workspace = session.workspace
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit shared model").font(.title2.weight(.semibold))
                    Text(session.modelID).font(.system(.caption, design: .monospaced)).foregroundStyle(Brand.secondary)
                }
                Spacer()
                Text("Updates every reference").font(.callout.weight(.medium)).foregroundStyle(Brand.accent)
            }
            Text(
                "Paint this model, then apply the edit to its composition or world. Cancel keeps the parent unchanged."
            )
            .font(.callout).foregroundStyle(Brand.secondary)
            HStack(spacing: 12) {
                TextField("Model name", text: $workspace.titleDraft).textFieldStyle(.roundedBorder)
                    .onSubmit { workspace.commitTitle() }.frame(maxWidth: 320)
                    .accessibilityIdentifier("shared.model.title")
                Picker("Tool", selection: $workspace.tool) {
                    ForEach(SculptureEditingTool.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 220).accessibilityIdentifier("shared.model.tool")
                Picker("Glyph", selection: $workspace.brush) {
                    ForEach(Sculpture.palette, id: \.self) { glyph in
                        Text(String(UnicodeScalar(glyph))).tag(glyph)
                    }
                }.frame(width: 110).accessibilityIdentifier("shared.model.glyph")
            }.disabled(isApplying)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Slice", selection: $workspace.layer) {
                        ForEach(0..<workspace.sculpture.depth, id: \.self) { Text("Slice \($0 + 1)").tag($0) }
                    }.accessibilityIdentifier("shared.model.slice")
                    LayerGrid(
                        sculpture: workspace.sculpture,
                        layer: workspace.layer,
                        column: workspace.column,
                        row: workspace.row,
                        showPreviousLayer: workspace.showPreviousLayer,
                        stroke: { workspace.paint($0, start: $1) },
                        finishStroke: { workspace.endStroke() }
                    )
                    Toggle("Previous slice", isOn: $workspace.showPreviousLayer).font(.caption)
                }.frame(minWidth: 260, maxWidth: 360)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("View", selection: $workspace.renderStyle) {
                            Text("Cubes").tag(SculptureRenderStyle.cubes)
                            Text("ASCII").tag(SculptureRenderStyle.ascii)
                        }.pickerStyle(.segmented).frame(width: 160)
                        Toggle("Paint in 3D", isOn: $workspace.paintsIn3D).toggleStyle(.button)
                            .disabled(workspace.renderStyle != .cubes).accessibilityIdentifier("shared.model.paint")
                    }
                    SculptureViewport(workspace: workspace, showsControls: true, fit: { workspace.camera.zoom = 1 })
                }
            }.frame(minHeight: 300, maxHeight: .infinity).disabled(isApplying)
            if let error = session.error ?? workspace.error ?? workspace.titleValidation {
                Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("shared.model.error")
            }
            Divider()
            HStack {
                Button("Cancel shared edit") {
                    applying?.cancel(); cancel()
                }
                .keyboardShortcut(.cancelAction).accessibilityIdentifier("shared.model.cancel")
                Button("Undo model edit") { workspace.undo() }.disabled(!workspace.canUndo || isApplying)
                    .keyboardShortcut("z").accessibilityIdentifier("shared.model.undo")
                Button("Redo model edit") { workspace.redo() }.disabled(!workspace.canRedo || isApplying)
                    .keyboardShortcut("z", modifiers: [.command, .shift]).accessibilityIdentifier("shared.model.redo")
                Spacer()
                if isApplying { ProgressView("Validating shared edit…").controlSize(.small) }
                Button("Apply shared edit") {
                    workspace.endStroke()
                    session.error = nil
                    applying = Task {
                        _ = await apply()
                        applying = nil
                    }
                }
                .buttonStyle(.borderedProminent).disabled(isApplying || workspace.titleValidation != nil)
                .accessibilityIdentifier("shared.model.apply")
            }
        }
        .padding(24).frame(minWidth: 840, idealWidth: 1060, minHeight: 640, idealHeight: 740)
        .background(Brand.paper).foregroundStyle(Brand.ink).tint(Brand.accent)
        .interactiveDismissDisabled()
        .onDisappear {
            applying?.cancel(); workspace.endStroke()
        }
    }
}
