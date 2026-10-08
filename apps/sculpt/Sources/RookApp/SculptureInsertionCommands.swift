import RookSculpture
import SwiftUI
import UniformTypeIdentifiers

internal enum SculptureInsertionWording {
    /// "1 model", "2 models": counts never read as "1 models".
    static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}

/// Which importer an insertion request presents: chosen files or a model folder.
internal enum SculptureInsertionKind: String, Identifiable, Sendable {
    case files, folder
    var id: Self { self }
}

/// Where a command-palette insertion starts: a new composition or a new sparse world.
internal enum SculptureInsertionDestination: String, Sendable {
    case composition, world
}

/// The menu surface of an open composition or world sheet that can accept an insertion.
internal struct SculptureInsertionActions {
    let insertFiles: @MainActor () -> Void
    let insertFolder: @MainActor () -> Void

    /// Nil unless the draft is idle, so menu items stay unavailable while preparation or a decision is pending.
    @MainActor
    static func actions(for draft: SculptureCompositionDraft) -> Self? {
        make(canInsert: draft.canInsert) { draft.requestInsertion($0) }
    }

    @MainActor
    static func actions(for draft: SculptureWorldDraft) -> Self? {
        make(canInsert: draft.canInsert) { draft.requestInsertion($0) }
    }

    private static func make(
        canInsert: Bool,
        request: @escaping @MainActor (SculptureInsertionKind) -> Void
    ) -> Self? {
        guard canInsert else { return nil }
        return Self(insertFiles: { request(.files) }, insertFolder: { request(.folder) })
    }
}

/// Command-palette entries that open a new sheet and present its importer.
internal enum SculptureInsertionPalette {
    /// `enabled` follows the document actions: false while any sheet, save, export or open is in progress.
    @MainActor
    static func actions(
        enabled: Bool = true,
        open: @escaping @MainActor (SculptureInsertionDestination, SculptureInsertionKind) -> Void
    ) -> [SculptureEditorAction] {
        [
            entry(
                "composition.insert",
                "Insert 3md into a new composition…",
                "Choose one or more models and place them in a new tile map.",
                "square.and.arrow.down.on.square",
                "insert import add model file 3md composition map tile",
                enabled: enabled,
                open: { open(.composition, .files) }
            ),
            entry(
                "composition.insert.folder",
                "Insert a model folder into a new composition…",
                "Place every 3md file in a folder into a new tile map.",
                "folder.badge.plus",
                "insert import add model folder files 3md composition map tile",
                enabled: enabled,
                open: { open(.composition, .folder) }
            ),
            entry(
                "world.insert",
                "Insert 3md into a new world…",
                "Choose one or more models and place them in a new sparse world.",
                "square.and.arrow.down.on.square",
                "insert import add model file 3md world sparse place",
                enabled: enabled,
                open: { open(.world, .files) }
            ),
            entry(
                "world.insert.folder",
                "Insert a model folder into a new world…",
                "Place every 3md file in a folder into a new sparse world.",
                "folder.badge.plus",
                "insert import add model folder files 3md world sparse place",
                enabled: enabled,
                open: { open(.world, .folder) }
            ),
        ]
    }

    private static func entry(
        _ id: String,
        _ title: String,
        _ detail: String,
        _ symbol: String,
        _ keywords: String,
        enabled: Bool,
        open: @escaping @MainActor () -> Void
    ) -> SculptureEditorAction {
        SculptureEditorAction(
            id: id,
            title: title,
            detail: detail,
            symbol: symbol,
            keywords: keywords,
            enabled: enabled,
            perform: open
        )
    }
}

/// The sheet that covers the editor window, reduced to what command availability depends on.
internal enum SculptureSheetContext {
    case none
    case composition(SculptureCompositionDraft)
    case world(SculptureWorldDraft)
    /// A linked session: a view-only composition or its repair view. It accepts no insertion and has no history.
    case linked(SculptureLinkedSession)
    /// The examples gallery or the export studio.
    case other
}

/// Work in progress that makes the editor window refuse new document actions.
internal struct SculptureEditorActivity: Equatable {
    var isOpening = false
    var isExporting = false
    var isSaving = false
    var isGraphSaving = false
    var isPortableSaving = false
    var hasGraphSaveSession = false

    var isIdle: Bool {
        !isOpening && !isExporting && !isSaving && !isGraphSaving && !isPortableSaving && !hasGraphSaveSession
    }
}

/// One decision for each command surface, shared by the File menu, Edit menu and command palette.
internal enum SculptureEditorCommandAvailability {
    /// New, Open, Save and the palette's new-sheet entries need an uncovered window with no work in progress.
    static func documentActionsAvailable(sheet: SculptureSheetContext, activity: SculptureEditorActivity) -> Bool {
        if case .none = sheet { return activity.isIdle }
        return false
    }

    /// Insert menu items belong to an open composition or world sheet that is idle and unobstructed.
    @MainActor
    static func insertionActions(
        sheet: SculptureSheetContext,
        activity: SculptureEditorActivity
    ) -> SculptureInsertionActions? {
        guard activity.isIdle else { return nil }
        switch sheet {
        case .composition(let draft): return SculptureInsertionActions.actions(for: draft)
        case .world(let draft): return SculptureInsertionActions.actions(for: draft)
        case .linked, .none, .other: return nil
        }
    }

    /// Reload Linked Files belongs to an open linked session while the window has no other work in progress.
    @MainActor
    static func linkedActions(sheet: SculptureSheetContext, activity: SculptureEditorActivity)
        -> SculptureLinkedActions?
    {
        guard activity.isIdle, case .linked(let session) = sheet else { return nil }
        return SculptureLinkedActions.actions(for: session)
    }

    /// Nil means no sheet owns Undo and Redo, so the main sculpture's history applies.
    @MainActor
    static func sheetHistory(sheet: SculptureSheetContext, activity: SculptureEditorActivity)
        -> SculptureHistoryActions?
    {
        if activity.hasGraphSaveSession { return .unavailable }
        switch sheet {
        case .composition(let draft): return SculptureHistoryActions.actions(for: draft)
        case .world(let draft): return SculptureHistoryActions.actions(for: draft)
        case .linked, .other: return .unavailable
        case .none: return nil
        }
    }
}

/// Undo and Redo for the frontmost editing surface. The hidden main sculpture never changes under an open sheet.
internal struct SculptureHistoryActions {
    let canUndo: Bool
    let canRedo: Bool
    let undo: @MainActor () -> Void
    let redo: @MainActor () -> Void

    /// A sheet with no editable history of its own: Undo and Redo are unavailable but not forwarded.
    static let unavailable = Self(canUndo: false, canRedo: false, undo: {}, redo: {})

    @MainActor
    static func actions(for draft: SculptureCompositionDraft) -> Self {
        if draft.isViewOnly { return .unavailable }
        if let edit = draft.sharedEdit { return actions(for: edit) }
        let idle = !draft.isBusy
        return Self(
            canUndo: draft.canUndo && idle,
            canRedo: draft.canRedo && idle,
            undo: { draft.undo() },
            redo: { draft.redo() }
        )
    }

    @MainActor
    static func actions(for draft: SculptureWorldDraft) -> Self {
        if let edit = draft.sharedEdit { return actions(for: edit) }
        let idle = !draft.isOpeningModel && !draft.isMakingUnique
        return Self(
            canUndo: draft.canUndo && idle,
            canRedo: draft.canRedo && idle,
            undo: { draft.undo() },
            redo: { draft.redo() }
        )
    }

    /// A shared edit's own history. While Apply validates a captured copy it is locked, because an Undo then would
    /// make Apply publish content the person no longer sees.
    @MainActor
    private static func actions(for session: SculptureSharedModelSession) -> Self {
        guard !session.isApplying else { return .unavailable }
        let workspace = session.workspace
        return Self(
            canUndo: workspace.canUndo,
            canRedo: workspace.canRedo,
            undo: { workspace.undo() },
            redo: { workspace.redo() }
        )
    }
}

/// Menu Undo and Redo target the open sheet's history when one is focused, and never the hidden sculpture.
@MainActor
internal enum SculptureHistoryRouting {
    static func canUndo(sheet: SculptureHistoryActions?, workspace: SculptureWorkspace) -> Bool {
        sheet?.canUndo ?? (!workspace.hasOpenSheet && workspace.canUndo)
    }

    static func canRedo(sheet: SculptureHistoryActions?, workspace: SculptureWorkspace) -> Bool {
        sheet?.canRedo ?? (!workspace.hasOpenSheet && workspace.canRedo)
    }

    static func undo(sheet: SculptureHistoryActions?, workspace: SculptureWorkspace) {
        guard canUndo(sheet: sheet, workspace: workspace) else { return }
        if let sheet { sheet.undo() } else { workspace.undo() }
    }

    static func redo(sheet: SculptureHistoryActions?, workspace: SculptureWorkspace) {
        guard canRedo(sheet: sheet, workspace: workspace) else { return }
        if let sheet { sheet.redo() } else { workspace.redo() }
    }
}

private struct SculptureInsertionActionsKey: FocusedValueKey {
    typealias Value = SculptureInsertionActions
}

private struct SculptureHistoryActionsKey: FocusedValueKey {
    typealias Value = SculptureHistoryActions
}

extension FocusedValues {
    internal var sculptureInsertionActions: SculptureInsertionActions? {
        get { self[SculptureInsertionActionsKey.self] }
        set { self[SculptureInsertionActionsKey.self] = newValue }
    }

    internal var sculptureSheetHistory: SculptureHistoryActions? {
        get { self[SculptureHistoryActionsKey.self] }
        set { self[SculptureHistoryActionsKey.self] = newValue }
    }
}

/// What an importer request should do now: present the panel, drop a request that can no longer run, or wait.
internal enum SculptureInsertionPresentation: Equatable {
    case present(SculptureInsertionKind)
    case discard
    case idle

    static func decide(
        request: SculptureInsertionKind?,
        canPresent: Bool,
        isPresenting: Bool
    ) -> Self {
        guard let request, !isPresenting else { return .idle }
        return canPresent ? .present(request) : .discard
    }
}

/// One importer for the sheet buttons, the File menu and the command palette. A request may already be pending
/// when the sheet first appears, as it is after choosing "Insert 3md into a new composition…".
internal struct SculptureInsertionImporter: ViewModifier {
    let request: SculptureInsertionKind?
    /// Reads the live request and busy state when the delayed presentation fires, never a stale copy.
    let current: @MainActor () -> SculptureInsertionKind?
    let canPresent: @MainActor () -> Bool
    let finish: @MainActor () -> Void
    let importFiles: @MainActor ([URL]) -> Void
    let importFolder: @MainActor (URL) -> Void
    let report: @MainActor (any Error) -> Void
    @State private var presenting = false
    @State private var kind = SculptureInsertionKind.files

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $presenting,
                allowedContentTypes: kind == .folder ? [.folder] : [.sculpture, .compactSculpture, .plainText],
                allowsMultipleSelection: kind != .folder
            ) { result in
                switch result {
                case .success(let urls):
                    if kind == .folder, let folder = urls.first {
                        importFolder(folder)
                    } else {
                        importFiles(urls)
                    }
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled { report(error) }
                }
            }
            .onChange(of: request) { _, _ in present() }
            .onChange(of: presenting) { _, isPresenting in
                if !isPresenting { finish() }
            }
            .task {
                guard request != nil else { return }
                // Let the sheet finish presenting before the file panel attaches to it. Leaving cancels the wait.
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                present()
            }
            .onDisappear {
                // A request that never reached the panel must not survive the sheet.
                if !presenting { finish() }
            }
    }

    private func present() {
        switch SculptureInsertionPresentation.decide(
            request: current(),
            canPresent: canPresent(),
            isPresenting: presenting
        ) {
        case .present(let requested):
            kind = requested
            presenting = true
        case .discard: finish()
        case .idle: break
        }
    }
}

extension View {
    internal func insertionImporter(
        request: SculptureInsertionKind?,
        current: @escaping @MainActor () -> SculptureInsertionKind?,
        canPresent: @escaping @MainActor () -> Bool,
        finish: @escaping @MainActor () -> Void,
        importFiles: @escaping @MainActor ([URL]) -> Void,
        importFolder: @escaping @MainActor (URL) -> Void,
        report: @escaping @MainActor (any Error) -> Void
    ) -> some View {
        modifier(
            SculptureInsertionImporter(
                request: request,
                current: current,
                canPresent: canPresent,
                finish: finish,
                importFiles: importFiles,
                importFolder: importFolder,
                report: report
            )
        )
    }
}
