import AppKit
import SwiftUI

internal struct SculptureCommandSearchField: NSViewRepresentable {
    @Binding var text: String
    let move: (Int) -> Void
    let submit: () -> Void
    let cancel: () -> Void
    var inputReleased: () -> Void = {}

    func makeNSView(context: Context) -> SculptureCommandTextField {
        let field = SculptureCommandTextField(frame: .zero)
        field.stringValue = text
        field.placeholderString = "What would you like to do?"
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.font = .systemFont(ofSize: 20)
        field.textColor = .labelColor
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.inputReleased = inputReleased
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Search editor commands")
        field.setAccessibilityIdentifier("editor.commands.search")
        field.setAccessibilityHelp("Type a command. Use Up and Down to choose, Return to run, or Escape to close.")
        return field
    }

    func updateNSView(_ field: SculptureCommandTextField, context: Context) {
        context.coordinator.owner = self
        field.inputReleased = inputReleased
        if field.stringValue != text { field.stringValue = text }
    }

    static func dismantleNSView(_ field: SculptureCommandTextField, coordinator: Coordinator) {
        field.cancelFocusRequest()
        field.delegate = nil
        let release = field.inputReleased
        DispatchQueue.main.async { release() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    internal final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: SculptureCommandSearchField

        init(_ owner: SculptureCommandSearchField) { self.owner = owner }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            owner.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)): owner.move(1)
            case #selector(NSResponder.moveUp(_:)): owner.move(-1)
            case #selector(NSResponder.insertNewline(_:)): owner.submit()
            case #selector(NSResponder.cancelOperation(_:)): owner.cancel()
            default: return false
            }
            return true
        }
    }
}

internal final class SculptureCommandTextField: NSTextField {
    private var focusRequest: Task<Void, Never>?
    var inputReleased: () -> Void = {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelFocusRequest()
        guard let window else { return }
        window.makeFirstResponder(self)
        focusRequest = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    func cancelFocusRequest() {
        focusRequest?.cancel()
        focusRequest = nil
    }
}
