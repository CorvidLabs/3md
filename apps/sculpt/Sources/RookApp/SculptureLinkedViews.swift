import RookSculpture
import SwiftUI
import UniformTypeIdentifiers

/// The sheet of a linked session: the view-only composition once it resolves, or the repair view.
internal struct SculptureLinkedSessionView: View {
    // MARK: - Properties

    internal let session: SculptureLinkedSession

    internal var body: some View {
        // A stack, not a group, so the lifecycle and focus modifiers below belong to the sheet rather than to
        // whichever child is showing. Moving from the repair view to the composition never cancels anything.
        ZStack {
            if let draft = session.draft {
                SculptureCompositionEditor(
                    draft: draft,
                    linked: session,
                    onOpen: { _, _ in },
                    onSave: { _ in },
                    onWorld: { _ in }
                )
            } else if let repair = session.repair {
                SculptureLinkedRepairView(session: session, repair: repair)
            } else {
                VStack(spacing: 12) {
                    ProgressView("Reading linked files…")
                    Button("Cancel") { session.cancel() }.accessibilityIdentifier("linked.resolve.cancel")
                }
                .padding(40)
            }
        }
        // Reload Linked Files in the File menu reaches the session whichever scope owns focus.
        .focusedSceneValue(\.sculptureLinkedActions, SculptureLinkedActions.actions(for: session))
        .onDisappear { session.cancel() }
    }
}

/// Reload progress, the latest reload failure and the latest result of a shown linked composition.
internal struct SculptureLinkedStatus: View {
    // MARK: - Properties

    internal let session: SculptureLinkedSession

    internal var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.isResolving {
                HStack(spacing: 10) {
                    ProgressView("Reloading linked files…").controlSize(.small)
                    Button("Cancel reload") { session.cancel() }
                        .accessibilityIdentifier("composition.linked.reload.cancel")
                }
            } else if let error = session.error {
                Text("Reload failed. The scene below is unchanged. \(error)")
                    .font(.callout).foregroundStyle(.red)
                    .accessibilityIdentifier("composition.linked.error")
            } else if let notice = session.notice {
                Text(notice).font(.callout).foregroundStyle(Brand.secondary)
                    .accessibilityIdentifier("composition.linked.status")
            }
        }
    }
}

/// Shown when a linked root does not resolve at open. It lists each failing link with its file and reason,
/// offers Reload and Choose Folder, and writes nothing.
internal struct SculptureLinkedRepairView: View {
    // MARK: - Properties

    internal let session: SculptureLinkedSession
    internal let repair: SculptureLinkedRepair
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false

    internal var body: some View {
        let actions = SculptureLinkedRepairActions.actions(for: session)
        VStack(alignment: .leading, spacing: 16) {
            Text("Linked files need attention").font(.callout).foregroundStyle(Brand.secondary)
            Text(repair.title).font(.system(size: 26, weight: .semibold))
                .accessibilityIdentifier("linked.repair.title")
            Text(
                "\(repair.rootPath) in \(session.folder.name) could not be resolved. Nothing was opened for editing "
                    + "and no file was changed. Fix the files below, then Reload, or choose the folder that holds them."
            )
            .font(.callout).foregroundStyle(Brand.secondary)
            .accessibilityIdentifier("linked.repair.summary")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(repair.failures.enumerated()), id: \.element.id) { index, failure in
                        failureRow(failure).accessibilityIdentifier("linked.repair.failure.\(index)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 340)
            if repair.uncheckedLinks > 0 {
                Text(
                    "\(SculptureInsertionWording.count(repair.uncheckedLinks, "more link")) "
                        + "\(repair.uncheckedLinks == 1 ? "was" : "were") not checked. Reload after fixing these."
                )
                .font(.caption).foregroundStyle(Brand.secondary)
                .accessibilityIdentifier("linked.repair.unchecked")
            }
            if session.isResolving {
                ProgressView("Reading linked files…").controlSize(.small)
            } else if let error = session.error {
                Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("linked.repair.error")
            }
            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("linked.repair.close")
                Spacer()
                Button("Choose Folder…") { choosingFolder = true }
                    .disabled(!actions.canChooseFolder)
                    .help("Choose the project folder that contains \(session.fileName) and its linked files.")
                    .accessibilityIdentifier("linked.repair.choose-folder")
                Button("Reload") { session.reload() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!actions.canReload)
                    .accessibilityIdentifier("linked.repair.reload")
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 420)
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
        .tint(Brand.accent)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { session.chooseFolder(folder) }
        }
        .fileDialogMessage("Choose the project folder that contains \(session.fileName).")
    }

    private func failureRow(_ failure: SculptureLinkedRepairFailure) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(failure.link.map { "Link \($0)" } ?? "Linked composition")
                .font(.caption).foregroundStyle(Brand.secondary)
            Text(failure.file).font(.body.monospaced().weight(.medium)).textSelection(.enabled)
            Text(failure.reason).font(.callout)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            (failure.link.map { "Link \($0): " } ?? "") + "\(failure.file) \(failure.reason)"
        )
    }
}
