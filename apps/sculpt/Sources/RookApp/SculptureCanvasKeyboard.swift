import AppKit
import Observation
import SwiftUI

internal enum SculptureCanvasKey: Sendable { case left, right, up, down, apply }

@MainActor
@Observable
internal final class SculptureCanvasFocus {
    private(set) var isFocused = false
    @ObservationIgnored private weak var view: SculptureCanvasKeyboardView?
    @ObservationIgnored private var requested = false

    func attach(_ view: SculptureCanvasKeyboardView) {
        self.view = view
        if requested { acquire() }
    }

    func detach(_ view: SculptureCanvasKeyboardView) {
        guard self.view === view else { return }
        self.view = nil
        isFocused = false
    }

    func acquire() {
        requested = true
        guard let view, let window = view.window else { return }
        window.makeFirstResponder(view)
    }

    func release() {
        requested = false
        guard let view, view.window?.firstResponder === view else { return }
        view.window?.makeFirstResponder(nil)
    }

    func nativeFocusChanged(_ focused: Bool) { isFocused = focused }
}

internal struct SculptureCanvasKeyboard: NSViewRepresentable {
    let focus: SculptureCanvasFocus
    let key: (SculptureCanvasKey) -> Bool

    func makeNSView(context: Context) -> SculptureCanvasKeyboardView {
        let view = SculptureCanvasKeyboardView(frame: .zero)
        view.focus = focus
        view.key = key
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Sculpture canvas keyboard controls")
        view.setAccessibilityIdentifier("editor.canvas.keyboard")
        view.setAccessibilityHelp(
            "In Slice or cube Paint mode, arrow keys select a cell and Space applies the current tool."
        )
        focus.attach(view)
        return view
    }

    func updateNSView(_ view: SculptureCanvasKeyboardView, context: Context) {
        view.key = key
    }

    static func dismantleNSView(_ view: SculptureCanvasKeyboardView, coordinator: ()) {
        view.focus?.detach(view)
    }
}

internal final class SculptureCanvasKeyboardView: NSView {
    var focus: SculptureCanvasFocus?
    var key: (SculptureCanvasKey) -> Bool = { _ in false }

    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { focus?.attach(self) }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focus?.nativeFocusChanged(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focus?.nativeFocusChanged(false) }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        let command: SculptureCanvasKey?
        switch event.keyCode {
        case 123: command = .left
        case 124: command = .right
        case 125: command = .down
        case 126: command = .up
        case 49: command = .apply
        default: command = nil
        }
        if let command, key(command) { return }
        super.keyDown(with: event)
    }
}
