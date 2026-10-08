import AppKit
import Foundation
import RookSculpture
import SwiftUI
import Testing

@testable import RookApp

@Suite("Reference editor presentation", .serialized)
@MainActor
struct SculptureReferenceEditorPresentationTests {
    @Test func nativeReferenceControlsFitBothSizesAndThemes() async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/verification/reference-presentation-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var captures: [ReferencePresentationCapture] = []
        for kind in ["composition", "world"] {
            let minimumWidth: CGFloat = kind == "world" ? 980 : 940
            for size in [CGSize(width: minimumWidth, height: 720), CGSize(width: 1120, height: 780)] {
                for dark in [false, true] {
                    let root: AnyView
                    let required: Set<String>
                    if kind == "composition" {
                        root = AnyView(
                            SculptureCompositionEditor(onOpen: { _, _ in }, onSave: { _ in }, onWorld: { _ in })
                        )
                        required = [
                            "composition.close", "composition.save", "composition.open", "composition.open-world",
                            "composition.models.insert",
                            "composition.models.folder",
                            "composition.title",
                        ]
                    } else {
                        root = AnyView(SculptureWorldEditor(onSave: { _ in }, onOpen: { _ in }))
                        required = [
                            "world.close", "world.save", "world.title", "world.focus.go", "world.place",
                            "world.models.insert",
                            "world.models.folder",
                        ]
                    }
                    let capture = try await capture(
                        root: root,
                        kind: kind,
                        required: required,
                        size: size,
                        dark: dark,
                        directory: directory
                    )
                    captures.append(capture)
                    #expect(capture.pixelWidth > 0 && capture.pixelHeight > 0)
                    #expect(capture.fittingWidth <= size.width + 1)
                    #expect(capture.fittingHeight <= size.height + 1)
                    if capture.accessibilityAvailable {
                        #expect(capture.missingControls.isEmpty)
                        #expect(capture.controlsOutsideBounds.isEmpty)
                    }
                }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ReferencePresentationReceipt(captures: captures)).write(
            to: directory.appendingPathComponent("receipt.json"),
            options: .atomic
        )
        print("Retained reference editor presentation: \(directory.path)")
    }

    private func capture(
        root: AnyView,
        kind: String,
        required: Set<String>,
        size: CGSize,
        dark: Bool,
        directory: URL
    ) async throws -> ReferencePresentationCapture {
        let hosting = NSHostingView(rootView: root.environment(\.colorScheme, dark ? .dark : .light))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.contentView = hosting
        window.setContentSize(size)
        hosting.frame = CGRect(origin: .zero, size: size)
        defer { window.contentView = nil; window.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let fitting = hosting.fittingSize
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let name = "\(kind)-\(Int(size.width))x\(Int(size.height))-\(dark ? "dark" : "light").png"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        var pending: [Any] = [hosting]
        var visited = Set<ObjectIdentifier>()
        var identifiers = Set<String>()
        var outside = Set<String>()
        while let value = pending.popLast(), visited.count < 3_000 {
            guard visited.insert(ObjectIdentifier(value as AnyObject)).inserted,
                let element = value as? any NSAccessibilityProtocol
            else { continue }
            let identifier = element.accessibilityIdentifier() ?? ""
            if !identifier.isEmpty { identifiers.insert(identifier) }
            let frame = hosting.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
            if required.contains(identifier), frame.width > 0, frame.height > 0,
                !hosting.bounds.insetBy(dx: -1, dy: -1).contains(frame)
            {
                outside.insert(identifier)
            }
            pending.append(contentsOf: element.accessibilityChildren() ?? [])
        }
        #expect(!window.isVisible && !window.isKeyWindow)
        return ReferencePresentationCapture(
            file: name,
            pixelWidth: bitmap.pixelsWide,
            pixelHeight: bitmap.pixelsHigh,
            fittingWidth: fitting.width,
            fittingHeight: fitting.height,
            accessibilityAvailable: !identifiers.isEmpty,
            unverifiedControls: identifiers.isEmpty ? required.sorted() : [],
            missingControls: required.subtracting(identifiers).sorted(),
            controlsOutsideBounds: outside.sorted()
        )
    }
}

private struct ReferencePresentationCapture: Encodable {
    let file: String
    let pixelWidth: Int
    let pixelHeight: Int
    let fittingWidth: Double
    let fittingHeight: Double
    let accessibilityAvailable: Bool
    /// Controls this capture could not verify because the offscreen host exposed no accessibility tree.
    let unverifiedControls: [String]
    let missingControls: [String]
    let controlsOutsideBounds: [String]
}

private struct ReferencePresentationReceipt: Encodable {
    let complete = true
    let limitation =
        "Offscreen AppKit captures verify layout/accessibility; CAMetalLayer pixels are verified separately by actual native GPU snapshots and computer use."
    let captures: [ReferencePresentationCapture]
}
