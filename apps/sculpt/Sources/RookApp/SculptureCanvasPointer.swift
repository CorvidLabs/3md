import AppKit
import SwiftUI

internal enum SculpturePointerPhase: Equatable, Sendable {
    case down, drag, up
}

/// A transparent native event surface above the Metal view. Keyboard focus remains with the canvas controller.
@MainActor
internal struct SculptureCanvasPointer: NSViewRepresentable {
    let paint: Bool
    let event: @MainActor (SculpturePointerPhase, CGPoint) -> Void

    func makeNSView(context: Context) -> SculptureCanvasPointerView {
        let view = SculptureCanvasPointerView(frame: .zero)
        view.paint = paint
        view.event = event
        return view
    }

    func updateNSView(_ view: SculptureCanvasPointerView, context: Context) {
        view.paint = paint
        view.event = event
    }
}

@MainActor
internal final class SculptureCanvasPointerView: NSView {
    var paint = false {
        didSet {
            if paint != oldValue { window?.invalidateCursorRects(for: self) }
        }
    }
    var event: @MainActor (SculpturePointerPhase, CGPoint) -> Void = { _, _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: paint ? .crosshair : .openHand)
    }

    override func mouseDown(with event: NSEvent) { dispatch(.down, event) }
    override func mouseDragged(with event: NSEvent) { dispatch(.drag, event) }
    override func mouseUp(with event: NSEvent) { dispatch(.up, event) }

    private func dispatch(_ phase: SculpturePointerPhase, _ input: NSEvent) {
        guard let window, input.windowNumber == window.windowNumber else { return }
        event(phase, convert(input.locationInWindow, from: nil))
    }
}
