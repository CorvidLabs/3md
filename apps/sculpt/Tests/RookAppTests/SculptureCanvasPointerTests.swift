import AppKit
import Testing

@testable import RookApp

@Suite(.serialized)
struct SculptureCanvasPointerTests {
    @MainActor
    @Test func nativePointerDispatchesTopLeftCoordinatesAndAllMousePhases() throws {
        _ = NSApplication.shared
        let window = pointerWindow()
        defer { window.close() }
        let content = try #require(window.contentView)
        let pointer = SculptureCanvasPointerView(frame: CGRect(x: 40, y: 60, width: 200, height: 100))
        content.addSubview(pointer)
        var events: [PointerSample] = []
        pointer.event = { events.append(PointerSample(phase: $0, point: $1)) }
        pointer.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 75, y: 70), in: window))
        pointer.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 120, y: 110), in: window))
        pointer.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 140, y: 130), in: window))
        #expect(
            events == [
                PointerSample(phase: .down, point: CGPoint(x: 35, y: 90)),
                PointerSample(phase: .drag, point: CGPoint(x: 80, y: 50)),
                PointerSample(phase: .up, point: CGPoint(x: 100, y: 30)),
            ]
        )
        #expect(pointer.isFlipped && !pointer.isOpaque)
        #expect(!pointer.isAccessibilityElement())
        #expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow)
    }

    @MainActor
    @Test func pointerEventsStayWithinTheirOwnWindow() throws {
        _ = NSApplication.shared
        let first = pointerWindow()
        let second = pointerWindow()
        defer { first.close(); second.close() }
        let firstPointer = SculptureCanvasPointerView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let secondPointer = SculptureCanvasPointerView(frame: firstPointer.frame)
        try #require(first.contentView).addSubview(firstPointer)
        try #require(second.contentView).addSubview(secondPointer)
        var firstEvents: [SculpturePointerPhase] = []
        var secondEvents: [SculpturePointerPhase] = []
        firstPointer.event = { phase, _ in firstEvents.append(phase) }
        secondPointer.event = { phase, _ in secondEvents.append(phase) }
        let input = try mouse(.leftMouseDown, at: CGPoint(x: 20, y: 30), in: first)
        firstPointer.mouseDown(with: input)
        secondPointer.mouseDown(with: input)
        #expect(firstEvents == [.down])
        #expect(secondEvents.isEmpty)
        secondPointer.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 40, y: 50), in: second))
        #expect(firstEvents == [.down])
        #expect(secondEvents == [.up])
    }

    @MainActor
    @Test func mouseInputDoesNotStealTheExistingKeyboardResponder() throws {
        _ = NSApplication.shared
        let window = pointerWindow()
        defer { window.close() }
        let content = try #require(window.contentView)
        let keyboard = SculptureCanvasKeyboardView(frame: content.bounds)
        let pointer = SculptureCanvasPointerView(frame: content.bounds)
        content.addSubview(keyboard)
        content.addSubview(pointer)
        #expect(window.makeFirstResponder(keyboard))
        #expect(!pointer.acceptsFirstResponder)
        #expect(pointer.acceptsFirstMouse(for: nil))
        var called = false
        pointer.event = { _, _ in called = true }
        pointer.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 20, y: 30), in: window))
        pointer.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 40, y: 50), in: window))
        pointer.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 60, y: 70), in: window))
        #expect(called)
        #expect(window.firstResponder === keyboard)
        #expect(content.hitTest(CGPoint(x: 40, y: 50)) === pointer)
        pointer.paint = true
        pointer.resetCursorRects()
        pointer.paint = false
        pointer.resetCursorRects()
        #expect(window.firstResponder === keyboard)
    }

    @MainActor
    private func pointerWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        return window
    }

    @MainActor
    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: 1,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
    }
}

private struct PointerSample: Equatable {
    let phase: SculpturePointerPhase
    let point: CGPoint
}
