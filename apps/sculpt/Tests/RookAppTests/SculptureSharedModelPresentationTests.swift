import AppKit
import Foundation
import RookSculpture
import SwiftUI
import Testing

@testable import RookApp

@Suite("Shared model native presentation", .serialized)
@MainActor
struct SculptureSharedModelPresentationTests {
    @Test func nativeSessionRendersBothSizesAndThemesWithAccessibilityEvidenceWhenAvailable() async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/verification/shared-model-presentation-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var receipts: [SharedModelPresentationCapture] = []
        for size in [CGSize(width: 840, height: 640), CGSize(width: 1120, height: 780)] {
            for dark in [false, true] {
                let original = try fixture()
                let draft = SculptureCompositionDraft(composition: original)
                draft.beginSharedEdit(modelID: "leaf")
                let session = try #require(draft.sharedEdit)
                session.workspace.renderStyle = .ascii
                session.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
                let root = SculptureSharedModelEditor(
                    session: session,
                    cancel: { draft.cancelSharedEdit() },
                    apply: { await draft.applySharedEdit() }
                )
                let hosting = NSHostingView(rootView: root.environment(\.colorScheme, dark ? .dark : .light))
                hosting.sizingOptions = []
                hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let window = NSWindow(
                    contentRect: CGRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                window.setContentSize(size)
                hosting.frame = CGRect(origin: .zero, size: size)
                defer { window.contentView = nil; window.close() }
                try await Task.sleep(for: .milliseconds(180))
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let required: Set<String> = [
                    "shared.model.apply", "shared.model.cancel", "shared.model.title", "shared.model.slice",
                    "shared.model.undo", "shared.model.redo", "shared.model.glyph", "shared.model.tool",
                    "editor.canvas",
                ]
                let elements = accessibilityElements(in: hosting)
                let accessibilityAvailable = !elements.isEmpty
                if accessibilityAvailable {
                    #expect(required.isSubset(of: Set(elements.keys)))
                    for identifier in required {
                        let element = try #require(elements[identifier])
                        let frame = hosting.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
                        #expect(frame.width > 0 && frame.height > 0)
                        #expect(hosting.bounds.insetBy(dx: -1, dy: -1).contains(frame))
                    }
                    let canvas = try #require(elements["editor.canvas"])
                    #expect(canvas.accessibilityValue() as? String == "Shared leaf, 1 voxels, ASCII, slice 1 selected")
                }
                #expect(hosting.fittingSize.width <= size.width + 1)
                #expect(hosting.fittingSize.height <= size.height + 1)
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let image = try #require(bitmap.representation(using: .png, properties: [:]))
                #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0 && image.count > 1_000)
                let name = "shared-\(Int(size.width))x\(Int(size.height))-\(dark ? "dark" : "light").png"
                try image.write(to: directory.appendingPathComponent(name), options: .atomic)
                if accessibilityAvailable {
                    let apply = try #require(elements["shared.model.apply"])
                    #expect(apply.accessibilityPerformPress())
                    for _ in 0..<100 where draft.sharedEdit != nil { try await Task.sleep(for: .milliseconds(10)) }
                    #expect(draft.sharedEdit == nil)
                    #expect(try draft.composition().expanded().layers == [[64, 64]])
                    #expect(draft.hasChanges && draft.canUndo)
                    draft.undo()
                    #expect(try draft.composition() == original && !draft.hasChanges)
                }
                #expect(!window.isVisible && !window.isKeyWindow)
                receipts.append(
                    SharedModelPresentationCapture(
                        image: name,
                        width: bitmap.pixelsWide,
                        height: bitmap.pixelsHigh,
                        fittingWidth: hosting.fittingSize.width,
                        fittingHeight: hosting.fittingSize.height,
                        accessibilityIdentifiers: elements.keys.sorted(),
                        accessibilityAvailable: accessibilityAvailable,
                        appliedThroughAccessibility: accessibilityAvailable
                    )
                )
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipts).write(to: directory.appendingPathComponent("receipt.json"), options: .atomic)
        print("Retained native shared-model presentation: \(directory.path)")
    }

    @Test func paletteAcceptsEveryOfferedGlyphAndNativeCancelKeepsParentWhenAccessibilityAvailable() async throws {
        _ = NSApplication.shared
        let original = try fixture()
        let draft = SculptureCompositionDraft(composition: original)
        draft.beginSharedEdit(modelID: "leaf")
        let session = try #require(draft.sharedEdit)
        for glyph in Sculpture.palette {
            session.workspace.brush = glyph
            session.workspace.paint(.init(x: 0, y: 0, z: 0), start: true)
            session.workspace.endStroke()
            #expect(session.workspace.sculpture.glyph(at: .init(x: 0, y: 0, z: 0)) == glyph)
        }
        let hosting = NSHostingView(
            rootView: SculptureSharedModelEditor(
                session: session,
                cancel: { draft.cancelSharedEdit() },
                apply: { await draft.applySharedEdit() }
            )
        )
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 940, height: 720)
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 940, height: 720),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        let elements = accessibilityElements(in: hosting)
        if !elements.isEmpty {
            let cancel = try #require(elements["shared.model.cancel"])
            #expect(cancel.accessibilityPerformPress())
            #expect(draft.sharedEdit == nil)
            #expect(try draft.composition() == original && !draft.hasChanges && !draft.canUndo)
        }
    }

    private func accessibilityElements(in hosting: NSView) -> [String: any NSAccessibilityProtocol] {
        var result: [String: any NSAccessibilityProtocol] = [:]
        var pending: [Any] = [hosting]
        var visited = Set<ObjectIdentifier>()
        while let value = pending.popLast(), visited.count < 6_000 {
            guard visited.insert(ObjectIdentifier(value as AnyObject)).inserted,
                let element = value as? any NSAccessibilityProtocol
            else { continue }
            if let identifier = element.accessibilityIdentifier(), !identifier.isEmpty { result[identifier] = element }
            pending.append(contentsOf: element.accessibilityChildren() ?? [])
            if let view = value as? NSView { pending.append(contentsOf: view.subviews) }
        }
        return result
    }

    private func fixture() throws -> SculptureComposition {
        try SculptureComposition(
            title: "Shared composition",
            rootID: "root",
            models: [
                "leaf": .sculpture(Sculpture(title: "Shared leaf", width: 1, height: 1, layers: [[35]])),
                "root": .tiles(
                    SculptureTileMap(
                        width: 2,
                        height: 1,
                        layers: [[65, 65]],
                        tileSize: .init(width: 1, height: 1, depth: 1),
                        bindings: [SculptureModelBinding(glyph: 65, modelID: "leaf")]
                    )
                ),
            ]
        )
    }
}

private struct SharedModelPresentationCapture: Encodable {
    let image: String
    let width: Int
    let height: Int
    let fittingWidth: Double
    let fittingHeight: Double
    let accessibilityIdentifiers: [String]
    let accessibilityAvailable: Bool
    let appliedThroughAccessibility: Bool
    let limitation =
        "Offscreen native captures verify rendered layout. If SwiftUI accessibility is unavailable, action activation requires a separate packaged-app native check."
}
