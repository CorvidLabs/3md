import AppKit
import SwiftUI

internal enum SculpturePointerPhase: Equatable, Sendable {
    case down, drag, up
}

internal enum SculptureCameraInput {
    case pan(SculpturePointerPhase, CGPoint)
    case panBy(CGSize)
    case zoom(Double)
}

/// A transparent native event surface above the Metal view. Keyboard focus remains with the canvas controller.
@MainActor
internal struct SculptureCanvasPointer: NSViewRepresentable {
    let paint: Bool
    let event: @MainActor (SculpturePointerPhase, CGPoint) -> Void
    var camera: @MainActor (SculptureCameraInput) -> Void = { _ in }

    func makeNSView(context: Context) -> SculptureCanvasPointerView {
        let view = SculptureCanvasPointerView(frame: .zero)
        view.paint = paint
        view.event = event
        view.camera = camera
        return view
    }

    func updateNSView(_ view: SculptureCanvasPointerView, context: Context) {
        view.paint = paint
        view.event = event
        view.camera = camera
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
    var camera: @MainActor (SculptureCameraInput) -> Void = { _ in }
    private var panning = false

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

    override func rightMouseDown(with event: NSEvent) { dispatch(.down, event) }
    override func rightMouseDragged(with event: NSEvent) { dispatch(.drag, event) }
    override func rightMouseUp(with event: NSEvent) { dispatch(.up, event) }
    override func otherMouseDown(with event: NSEvent) { dispatch(.down, event) }
    override func otherMouseDragged(with event: NSEvent) { dispatch(.drag, event) }
    override func otherMouseUp(with event: NSEvent) { dispatch(.up, event) }

    override func scrollWheel(with input: NSEvent) {
        guard let window, input.windowNumber == window.windowNumber else { return }
        let unit = input.hasPreciseScrollingDeltas ? 1.0 : 16.0
        if input.modifierFlags.contains(.shift) {
            camera(.panBy(CGSize(width: input.scrollingDeltaX * unit, height: -input.scrollingDeltaY * unit)))
        } else {
            camera(.zoom(exp(max(-500, min(500, input.scrollingDeltaY * unit)) * 0.002)))
        }
    }

    override func magnify(with input: NSEvent) {
        guard let window, input.windowNumber == window.windowNumber, input.magnification.isFinite else { return }
        camera(.zoom(exp(max(-2, min(2, Double(input.magnification))))))
    }

    private func dispatch(_ phase: SculpturePointerPhase, _ input: NSEvent) {
        guard let window, input.windowNumber == window.windowNumber else { return }
        if phase == .down {
            panning =
                input.buttonNumber != 0 || input.type == .rightMouseDown || input.type == .otherMouseDown
                || input.modifierFlags.contains(.shift)
        }
        let point = convert(input.locationInWindow, from: nil)
        if panning { camera(.pan(phase, point)) } else { event(phase, point) }
        if phase == .up { panning = false }
    }
}
