import AppKit
import Observation
import RookSculpture
import SwiftUI
import Testing

@testable import RookApp

@Suite(.serialized)
struct SculptureCommandFocusTests {
    @MainActor
    @Test func nativeSearchTakesPriorTitleResponderAndReturnRunsFilteredAction() async throws {
        _ = NSApplication.shared
        var selected = ""
        var closeCount = 0
        let actions = [
            SculptureEditorAction(
                id: "view.sculpt",
                title: "Show Sculpt mode",
                detail: "3D canvas",
                symbol: "cube",
                keywords: "view",
                perform: { selected = "sculpt" }
            ),
            SculptureEditorAction(
                id: "view.slice",
                title: "Show Slice mode",
                detail: "Edit a layer",
                symbol: "square.grid.3x3",
                keywords: "grid",
                perform: { selected = "slice" }
            ),
        ]
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 610, height: 500))
        let title = NSTextField(string: "Woven torus")
        title.frame = CGRect(x: 20, y: 465, width: 300, height: 25)
        container.addSubview(title)
        let window = focusWindow(content: container)
        defer { window.contentView = nil; window.close() }
        #expect(window.makeFirstResponder(title))
        let hosting = NSHostingView(rootView: SculptureCommandPalette(actions: actions, close: { closeCount += 1 }))
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 20, y: 10, width: 570, height: 440)
        container.addSubview(hosting)
        try await settleFocus(hosting)
        let search = try #require(nativeSearch(in: hosting))
        let editor = try #require(search.currentEditor())
        #expect(window.firstResponder === editor)
        #expect(search.accessibilityIdentifier() == "editor.commands.search")
        #expect(search.accessibilityLabel() == "Search editor commands")
        try typeQuery("show slice", into: window)
        try await settleFocus(hosting)
        #expect(search.stringValue == "show slice")
        #expect(title.stringValue == "Woven torus")
        try sendFocusKey("\r", code: 36, into: window)
        try await settleFocus(hosting)
        #expect(selected == "slice", "Return must run the filtered match rather than the first catalog action.")
        #expect(closeCount == 1)
        try sendFocusKey("\u{1B}", code: 53, into: window)
        #expect(closeCount == 2)
        #expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow)
    }

    @MainActor
    @Test func nativeSearchReturnHandsMountedCanvasRealArrowAndSpaceEvents() async throws {
        _ = NSApplication.shared
        let model = NativeCommandLifecycle()
        let canvas = SculptureCanvasFocus()
        let workspace = SculptureWorkspace()
        workspace.replace(with: .blank(), opened: true)
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 610, height: 150))
        let window = focusWindow(content: container)
        let hosting = NSHostingView(
            rootView: NativeCommandLifecycleView(model: model, canvas: canvas, workspace: workspace) {
                canvas.acquire()
            }
        )
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 20, y: 20, width: 570, height: 60)
        container.addSubview(hosting)
        defer { window.contentView = nil; window.close() }
        try await settleFocus(hosting)
        let search = try #require(nativeSearch(in: hosting))
        #expect(window.firstResponder === search.currentEditor())
        try typeQuery("show slice", into: window)
        try sendFocusKey("\r", code: 36, into: window)
        try await settleFocus(hosting)
        #expect(model.submittedQuery == "show slice")
        #expect(model.releases == 1)
        let nativeCanvas = try #require(
            nativeViews(in: hosting).compactMap { $0 as? SculptureCanvasKeyboardView }.first
        )
        #expect(window.firstResponder === nativeCanvas)
        #expect(canvas.isFocused)
        #expect(search.currentEditor() == nil)
        #expect(nativeCanvas.hitTest(.zero) == nil, "The keyboard bridge must not intercept canvas pointer input.")
        #expect(nativeCanvas.accessibilityIdentifier() == "editor.canvas.keyboard")
        try sendFocusKey("\u{F703}", code: 124, into: window)
        try sendFocusKey("\u{F701}", code: 125, into: window)
        #expect(workspace.column == 1 && workspace.row == 1)
        try sendFocusKey("\u{F703}", code: 124, modifiers: .command, into: window)
        #expect(workspace.column == 1, "Modified arrow shortcuts must follow the normal responder chain.")
        try sendFocusKey(" ", code: 49, into: window)
        #expect(workspace.sculpture.glyph(at: SculptureCell(x: 1, y: 1, z: 0)) == 35)
        #expect(workspace.sculpture.occupiedCount == 1)
        workspace.undo()
        #expect(workspace.sculpture.occupiedCount == 0)
        #expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow)
    }

    @MainActor
    @Test func nativeSearchEscapeUnmountsAndDoesNotRetakeRestoredTitleResponder() async throws {
        _ = NSApplication.shared
        let model = NativeCommandLifecycle()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 610, height: 150))
        let title = NSTextField(string: "Woven torus")
        title.frame = CGRect(x: 20, y: 110, width: 300, height: 25)
        container.addSubview(title)
        let window = focusWindow(content: container)
        #expect(window.makeFirstResponder(title))
        let hosting = NSHostingView(
            rootView: NativeCommandLifecycleView(model: model) {
                window.makeFirstResponder(title)
            }
        )
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 20, y: 20, width: 570, height: 60)
        container.addSubview(hosting)
        defer { window.contentView = nil; window.close() }
        try await settleFocus(hosting)
        let search = try #require(nativeSearch(in: hosting))
        #expect(window.firstResponder === search.currentEditor())
        try typeQuery("show slice", into: window)
        try sendFocusKey("\u{1B}", code: 53, into: window)
        try await settleFocus(hosting)
        #expect(model.cancelled)
        #expect(model.submittedQuery == nil)
        #expect(model.releases == 1)
        #expect(search.currentEditor() == nil)
        #expect(title.stringValue == "Woven torus")
        let restoredEditor = try #require(title.currentEditor())
        #expect(window.firstResponder === restoredEditor)
        try typeQuery("x", into: window)
        #expect(title.stringValue.hasSuffix("x"))
        #expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow)
    }
}

@MainActor
@Observable
private final class NativeCommandLifecycle {
    var presented = true
    var query = ""
    var submittedQuery: String?
    var cancelled = false
    var releases = 0
}

private struct NativeCommandLifecycleView: View {
    @Bindable var model: NativeCommandLifecycle
    var canvas: SculptureCanvasFocus?
    var workspace: SculptureWorkspace?
    let restore: () -> Void

    var body: some View {
        ZStack {
            if let canvas, let workspace {
                SculptureCanvasKeyboard(focus: canvas) { key in
                    switch key {
                    case .right: workspace.column += 1
                    case .left: workspace.column -= 1
                    case .down: workspace.row += 1
                    case .up: workspace.row -= 1
                    case .apply:
                        workspace.paint(
                            SculptureCell(x: workspace.column, y: workspace.row, z: workspace.layer),
                            start: true
                        )
                        workspace.endStroke()
                    }
                    return true
                }
            }
            if model.presented {
                SculptureCommandSearchField(
                    text: $model.query,
                    move: { _ in },
                    submit: {
                        model.submittedQuery = model.query
                        model.presented = false
                    },
                    cancel: {
                        model.cancelled = true
                        model.presented = false
                    },
                    inputReleased: {
                        model.releases += 1
                        restore()
                    }
                )
                .frame(height: 28)
            }
        }
    }
}

@MainActor
private func focusWindow(content: NSView) -> NSWindow {
    let size = content.frame.size
    let window = NSWindow(
        contentRect: CGRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.isExcludedFromWindowsMenu = true
    window.contentView = content
    window.setContentSize(size)
    return window
}

@MainActor
private func settleFocus(_ hosting: NSView) async throws {
    hosting.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(120))
    hosting.layoutSubtreeIfNeeded()
}

@MainActor
private func nativeViews(in view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { nativeViews(in: $0) }
}

@MainActor
private func nativeSearch(in view: NSView) -> SculptureCommandTextField? {
    nativeViews(in: view).compactMap { $0 as? SculptureCommandTextField }.first
}

@MainActor
private func typeQuery(_ text: String, into window: NSWindow) throws {
    let codes: [Character: UInt16] = [
        "s": 1, "h": 4, "o": 31, "w": 13, " ": 49, "l": 37, "i": 34, "c": 8, "e": 14, "x": 7,
    ]
    for character in text {
        let code = try #require(codes[character])
        try sendFocusKey(String(character), code: code, into: window)
    }
}

@MainActor
private func sendFocusKey(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], into window: NSWindow)
    throws
{
    let responder = try #require(window.firstResponder)
    let event = try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: text,
            charactersIgnoringModifiers: text,
            isARepeat: false,
            keyCode: code
        )
    )
    responder.keyDown(with: event)
}
