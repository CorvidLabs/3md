import SwiftUI

internal struct SculptureEditorAction: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let keywords: String
    var enabled = true
    let perform: @MainActor () -> Void
}

internal enum SculptureCommandSearch {
    static func matches(_ actions: [SculptureEditorAction], query: String) -> [SculptureEditorAction] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        return actions.filter { action in
            let searchable = "\(action.title) \(action.detail) \(action.keywords)".lowercased()
            return words.allSatisfy { searchable.contains($0) }
        }
    }
}

internal struct SculptureCommandPalette: View {
    let actions: [SculptureEditorAction]
    let close: () -> Void
    let inputReleased: () -> Void
    let executionStarted: () -> Void
    @State private var query = ""
    @State private var selection = 0

    private var matches: [SculptureEditorAction] {
        SculptureCommandSearch.matches(actions, query: query)
    }

    internal init(
        actions: [SculptureEditorAction],
        query: String = "",
        close: @escaping () -> Void,
        inputReleased: @escaping () -> Void = {},
        executionStarted: @escaping () -> Void = {}
    ) {
        self.actions = actions
        self.close = close
        self.inputReleased = inputReleased
        self.executionStarted = executionStarted
        _query = State(initialValue: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.secondary)
                SculptureCommandSearchField(
                    text: $query,
                    move: { move($0) },
                    submit: { invokeHighlighted() },
                    cancel: close,
                    inputReleased: inputReleased
                )
                .frame(height: 28)
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("editor.commands.close")
            }
            .padding(20)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, action in
                            commandRow(action, highlighted: index == selection)
                                .id(action.id)
                        }
                        if matches.isEmpty {
                            VStack(spacing: 8) {
                                Text("No matching command").font(.headline)
                                Text("Try save, draw, slice or camera.").foregroundStyle(Brand.secondary)
                            }
                            .frame(maxWidth: .infinity).padding(30)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 350)
                .onChange(of: selection) { _, index in
                    if matches.indices.contains(index) { proxy.scrollTo(matches[index].id, anchor: .center) }
                }
            }
            Divider()
            HStack(spacing: 16) {
                Text("↑ ↓ to choose")
                Text("Return to run")
                Spacer()
                Text("Escape to close")
            }
            .font(.caption).foregroundStyle(Brand.secondary)
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 570)
        .background(Brand.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Brand.secondary.opacity(0.2)) }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .foregroundStyle(Brand.ink).tint(Brand.accent)
        .onChange(of: query) { _, _ in selection = 0 }
        .onExitCommand(perform: close)
    }

    private func commandRow(_ action: SculptureEditorAction, highlighted: Bool) -> some View {
        Button {
            invoke(action)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: action.symbol)
                    .font(.system(size: 17)).frame(width: 25)
                    .foregroundStyle(highlighted ? Brand.accent : Brand.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title).font(.body.weight(.medium))
                    Text(action.detail).font(.caption).foregroundStyle(Brand.secondary)
                }
                Spacer()
                if !action.enabled { Text("Unavailable").font(.caption).foregroundStyle(Brand.secondary) }
                if highlighted && action.enabled {
                    Image(systemName: "return").font(.caption).foregroundStyle(Brand.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(highlighted ? Brand.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!action.enabled)
        .accessibilityLabel("\(action.title). \(action.detail)")
        .accessibilityIdentifier("command.\(action.id)")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private func move(_ step: Int) {
        guard !matches.isEmpty else { return }
        selection = min(matches.count - 1, max(0, selection + step))
    }

    private func invokeHighlighted() {
        guard matches.indices.contains(selection) else { return }
        invoke(matches[selection])
    }

    private func invoke(_ action: SculptureEditorAction) {
        guard action.enabled else { return }
        executionStarted()
        close()
        Task { @MainActor in
            await Task.yield()
            action.perform()
        }
    }
}
