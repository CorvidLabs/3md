import AppKit
import RookSculpture
import SwiftUI
import Testing

@testable import RookApp

@Suite(.serialized)
struct LayerGridScrollPresentationTests {
    @MainActor
    @Test func nativeClipMeasurementIsWindowScopedAndDisconnectsWhenDismantled() async throws {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let view = SliceClipBoundsView(frame: CGRect(x: 0, y: 0, width: 6_144, height: 6_144))
        var measurements: [CGRect] = []
        view.changed = { measurements.append($0) }
        scroll.documentView = view
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 400, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(scroll)
        scroll.contentView.scroll(to: CGPoint(x: 3_000, y: 4_000))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(scroll)
        let actual = try #require(measurements.last)
        #expect(actual.origin == CGPoint(x: -3_000, y: -4_000))
        #expect(actual.size == CGSize(width: 6_144, height: 6_144))
        let count = measurements.count
        SliceClipBounds.dismantleNSView(view, coordinator: ())
        scroll.contentView.scroll(to: CGPoint(x: 1_000, y: 1_000))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(scroll)
        #expect(measurements.count == count, "A removed canvas must not receive native scroll updates.")
        #expect(!window.isVisible && !window.isKeyWindow)
    }

    @MainActor
    @Test func nativeZoomedSliceKeepsDrawingAfterItsOriginScrollsOutOfView() async throws {
        _ = NSApplication.shared
        let glyphs = (0..<(256 * 256)).map { index in
            UInt8((index / 256 + index % 256).isMultiple(of: 2) ? 35 : Sculpture.empty)
        }
        let sculpture = try Sculpture(title: "Native scroll", width: 256, height: 256, layers: [glyphs])
        let content = LayerGrid(
            sculpture: sculpture,
            layer: 0,
            column: 0,
            row: 0,
            showPreviousLayer: false,
            zoom: .sixteenTimes,
            stroke: { _, _ in },
            finishStroke: {}
        )
        .padding(8)
        .background(Brand.paper)
        .environment(\.colorScheme, .light)
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.appearance = NSAppearance(named: .aqua)
        let size = CGSize(width: 400, height: 440)
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.contentView = hosting
        window.setContentSize(size)
        hosting.frame = CGRect(origin: .zero, size: size)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(hosting)
        let scroll = try #require(findScrollView(in: hosting))
        let document = try #require(scroll.documentView)
        #expect(document.frame.height > 4_000)
        let before = try darkGridPixels(hosting)
        #expect(before > 100, "The actual initial Canvas must contain visible glyphs.")
        for fraction in [0.35, 0.75, 1.0] {
            let x = (document.frame.width - scroll.contentView.bounds.width) * fraction
            let y = (document.frame.height - scroll.contentView.bounds.height) * fraction
            scroll.contentView.scroll(to: CGPoint(x: x, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await settle(hosting)
            #expect(scroll.contentView.bounds.origin.y > 1_000)
            let visible = try darkGridPixels(hosting)
            #expect(visible > 100, "Scrolling must retain actual Canvas glyphs beyond the original layout origin.")
            #expect(visible > before / 3)
        }
        #expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow)
    }
}

@MainActor
private func findScrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    for child in view.subviews {
        if let scroll = findScrollView(in: child) { return scroll }
    }
    return nil
}

@MainActor
private func settle(_ hosting: NSView) async throws {
    hosting.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(120))
    hosting.layoutSubtreeIfNeeded()
    hosting.displayIfNeeded()
}

@MainActor
private func darkGridPixels(_ hosting: NSView) throws -> Int {
    let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    var count = 0
    // Skip the toolbar and scroll bars; sample only the actual grid interior.
    for y in (bitmap.pixelsHigh / 4)..<(bitmap.pixelsHigh * 3 / 4) {
        for x in (bitmap.pixelsWide / 4)..<(bitmap.pixelsWide * 3 / 4) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            if color.redComponent < 0.5 && color.greenComponent < 0.5 && color.blueComponent < 0.5 {
                count += 1
            }
        }
    }
    return count
}
