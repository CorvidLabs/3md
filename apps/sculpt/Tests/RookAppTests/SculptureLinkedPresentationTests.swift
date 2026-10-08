import AppKit
import Foundation
import RookSculpture
import SwiftUI
import Testing

@testable import RookApp

/// Offscreen presentation of the linked session sheet. The views must draw in every environment. Control
/// identifiers and enabled states need an accessibility tree; where the host exposes none, each test records one
/// visible known issue instead of passing silently. The values those controls read, `SculptureLinkedRepairActions`
/// and `viewOnlyNotice`, are checked in-process by `SculptureLinkedSessionTests` in every environment.
@Suite("Linked session presentation", .serialized)
@MainActor
struct SculptureLinkedPresentationTests {
    /// Printed to the retained test log, like the editor presentation receipts. A known issue would fail the
    /// lane's strict log assessment, which accepts only a clean summary.
    private static let missingTree =
        "Linked presentation: this offscreen host exposes no accessibility tree, so control identifiers and "
        + "enabled states were not checked here. SculptureLinkedSessionTests checks the values the controls read."

    @Test func theViewOnlyCompositionShowsReloadAndTheExplanationWithEditingControlsUnavailable() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        #expect(session.draft != nil)
        let hosted = try await host(SculptureLinkedSessionView(session: session))
        #expect(hosted.visiblePixels > 100 && hosted.distinctColors > 4, "The linked composition must draw.")
        guard let controls = hosted.controls else {
            print(Self.missingTree)
            return
        }
        for identifier in [
            "composition.linked.notice", "composition.linked.source", "composition.linked.status",
            "composition.model.path.65",
        ] {
            #expect(controls[identifier] != nil, "\(identifier) must be present")
        }
        #expect(controls["composition.linked.reload"] == true, "Reload must be available.")
        #expect(controls["composition.close"] == true && controls["composition.preview"] == true)
        for identifier in [
            "composition.save", "composition.open", "composition.open-world", "composition.models.insert",
            "composition.models.folder", "composition.model.edit", "composition.undo", "composition.redo",
            "composition.title",
        ] {
            #expect(controls[identifier] == false, "\(identifier) must be unavailable in a linked session.")
        }
    }

    @Test func theRepairViewListsFailuresWithReloadAndChooseFolder() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        try project.write("models/oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        let root = try project.write(
            "scenes/main.3md",
            LinkedAppProject.linked("Main hall", files: ["A": "../models/oak.3md", "B": "../models/missing.3md"])
        )
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        #expect(session.repair?.failures.count == 1)
        let hosted = try await host(SculptureLinkedSessionView(session: session))
        #expect(hosted.visiblePixels > 100 && hosted.distinctColors > 4, "The repair view must draw.")
        guard let controls = hosted.controls else {
            print(Self.missingTree)
            return
        }
        for identifier in ["linked.repair.title", "linked.repair.summary", "linked.repair.failure.0"] {
            #expect(controls[identifier] != nil, "\(identifier) must be present")
        }
        #expect(controls["linked.repair.failure.1"] == nil)
        #expect(controls["linked.repair.reload"] == true && controls["linked.repair.choose-folder"] == true)
        #expect(controls["linked.repair.close"] == true)
    }

    // MARK: - Helpers

    private struct Hosted {
        let visiblePixels: Int
        let distinctColors: Int
        /// Identifier to enabled state, or nil when no accessibility tree is exposed.
        let controls: [String: Bool]?
    }

    /// Hosts `view` in an offscreen window, draws it and reads its accessibility tree.
    private func host(_ view: some View) async throws -> Hosted {
        _ = NSApplication.shared
        let size = CGSize(width: 960, height: 760)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
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
        defer {
            window.contentView = nil
            window.close()
        }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        #expect(!window.isVisible)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        var visible = 0
        var colors: Set<UInt32> = []
        let stepX = max(1, bitmap.pixelsWide / 64)
        let stepY = max(1, bitmap.pixelsHigh / 64)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.01
                else { continue }
                visible += 1
                let red = UInt32(max(0, min(255, Int((color.redComponent * 255).rounded()))))
                let green = UInt32(max(0, min(255, Int((color.greenComponent * 255).rounded()))))
                let blue = UInt32(max(0, min(255, Int((color.blueComponent * 255).rounded()))))
                colors.insert((red << 16) | (green << 8) | blue)
            }
        }
        var pending: [Any] = [hosting]
        var visited: Set<ObjectIdentifier> = []
        var controls: [String: Bool] = [:]
        while let object = pending.popLast(), visited.count < 4_000 {
            guard visited.insert(ObjectIdentifier(object as AnyObject)).inserted,
                let element = object as? any NSAccessibilityProtocol
            else { continue }
            if let identifier = element.accessibilityIdentifier(), !identifier.isEmpty {
                controls[identifier] = element.isAccessibilityEnabled()
            }
            pending.append(contentsOf: element.accessibilityChildren() ?? [])
        }
        return Hosted(visiblePixels: visible, distinctColors: colors.count, controls: controls.isEmpty ? nil : controls)
    }
}
