import SwiftUI

internal struct SculptureDocumentActions {
    let newDocument: @MainActor () -> Void
    let newComposition: @MainActor () -> Void
    let newWorld: @MainActor () -> Void
    let openDocument: @MainActor () -> Void
    let saveDocument: @MainActor () -> Void
    let saveReadableDocument: @MainActor () -> Void
}

internal struct SculpturePortableActions {
    let exportReadable: @MainActor () -> Void
    let exportBinary: @MainActor () -> Void
}

/// Reload Linked Files for an open linked session. Nil while a resolution is already in progress.
internal struct SculptureLinkedActions {
    let reload: @MainActor () -> Void

    @MainActor
    static func actions(for session: SculptureLinkedSession) -> Self? {
        guard session.canReload else { return nil }
        return Self(reload: { session.reload() })
    }
}

private struct SculptureLinkedActionsKey: FocusedValueKey {
    typealias Value = SculptureLinkedActions
}

private struct SculpturePortableActionsKey: FocusedValueKey {
    typealias Value = SculpturePortableActions
}

private struct SculptureDocumentActionsKey: FocusedValueKey {
    typealias Value = SculptureDocumentActions
}

extension FocusedValues {
    internal var sculptureLinkedActions: SculptureLinkedActions? {
        get { self[SculptureLinkedActionsKey.self] }
        set { self[SculptureLinkedActionsKey.self] = newValue }
    }

    internal var sculpturePortableActions: SculpturePortableActions? {
        get { self[SculpturePortableActionsKey.self] }
        set { self[SculpturePortableActionsKey.self] = newValue }
    }

    internal var sculptureDocumentActions: SculptureDocumentActions? {
        get { self[SculptureDocumentActionsKey.self] }
        set { self[SculptureDocumentActionsKey.self] = newValue }
    }
}

internal struct SculptureDocumentCommands: Commands {
    @FocusedValue(\.sculptureDocumentActions) private var actions
    @FocusedValue(\.sculpturePortableActions) private var portable
    @FocusedValue(\.sculptureInsertionActions) private var insertion
    @FocusedValue(\.sculptureLinkedActions) private var linked

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New empty sculpture") { actions?.newDocument() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
            Button("Open sculpture…") { actions?.openDocument() }
                .keyboardShortcut("o")
                .disabled(actions == nil)
            Button("New composition…") { actions?.newComposition() }
                .disabled(actions == nil)
            Button("New sparse world…") { actions?.newWorld() }
                .disabled(actions == nil)
            Divider()
            Button("Insert 3md…") { insertion?.insertFiles() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(insertion == nil)
            Button("Insert model folder…") { insertion?.insertFolder() }
                .keyboardShortcut("i", modifiers: [.command, .shift, .option])
                .disabled(insertion == nil)
            Divider()
            Button("Reload Linked Files") { linked?.reload() }
                .keyboardShortcut("r")
                .disabled(linked == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save compact 3md…") { actions?.saveDocument() }
                .keyboardShortcut("s")
                .disabled(actions == nil)
            Button("Save readable 3md…") { actions?.saveReadableDocument() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Menu("Export portable ThreeMD") {
                Button("Readable 3md copy…") { portable?.exportReadable() }
                Button("Binary 3mdb copy…") { portable?.exportBinary() }
            }
            .disabled(portable == nil)
        }
    }
}

/// Undo and Redo follow the frontmost editing surface. An open composition or world sheet owns them, so the
/// hidden main sculpture never changes while it is covered.
internal struct SculptureHistoryCommands: Commands {
    let workspace: SculptureWorkspace
    @FocusedValue(\.sculptureSheetHistory) private var sheet

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { SculptureHistoryRouting.undo(sheet: sheet, workspace: workspace) }
                .keyboardShortcut("z")
                .disabled(!SculptureHistoryRouting.canUndo(sheet: sheet, workspace: workspace))
            Button("Redo") { SculptureHistoryRouting.redo(sheet: sheet, workspace: workspace) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!SculptureHistoryRouting.canRedo(sheet: sheet, workspace: workspace))
        }
    }
}
