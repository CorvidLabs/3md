import AppKit
import Foundation
import RookRendering
import RookSculpture
import SwiftUI
import Testing

@testable import RookApp

@Suite(.serialized)
struct SculptureEditorPresentationTests {
    @MainActor
    @Test func actualEditorViewsRenderAtMinimumAndDefaultSizes() async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/verification/editor-presentation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var receipt = PresentationReceipt()
        try writeReceipt(receipt, in: directory)
        let fixtures =
            SculptureEditorMode.allCases.map {
                PresentationFixture(
                    id: "default-\($0.rawValue.lowercased())",
                    filePrefix: "editor-\($0.rawValue.lowercased())",
                    mode: $0,
                    style: .cubes,
                    paintsIn3D: false,
                    documentID: "character-orb"
                )
            } + [
                PresentationFixture(
                    id: "cube-paint",
                    filePrefix: "editor-cube-paint",
                    mode: .sculpt,
                    style: .cubes,
                    paintsIn3D: true,
                    documentID: "character-orb"
                ),
                PresentationFixture(
                    id: "ascii",
                    filePrefix: "editor-ascii",
                    mode: .sculpt,
                    style: .ascii,
                    paintsIn3D: false,
                    documentID: "character-orb"
                ),
                PresentationFixture(
                    id: "citadel-slice",
                    filePrefix: "editor-citadel-slice",
                    mode: .slice,
                    style: .cubes,
                    paintsIn3D: false,
                    documentID: "citadel-of-arches"
                ),
                PresentationFixture(
                    id: "world-slice",
                    filePrefix: "editor-world-slice",
                    mode: .slice,
                    style: .cubes,
                    paintsIn3D: false,
                    documentID: "sky-island-village"
                ),
                PresentationFixture(
                    id: "solar-sculpt",
                    filePrefix: "editor-solar-sculpt",
                    mode: .sculpt,
                    style: .cubes,
                    paintsIn3D: false,
                    documentID: "grand-solar-system"
                ),
                PresentationFixture(
                    id: "solar-slice",
                    filePrefix: "editor-solar-slice",
                    mode: .slice,
                    style: .cubes,
                    paintsIn3D: false,
                    documentID: "grand-solar-system"
                ),
            ]
        for fixture in fixtures {
            for size in [CGSize(width: 940, height: 650), CGSize(width: 1120, height: 760)] {
                for theme in PresentationTheme.allCases {
                    let capture = try await capture(fixture: fixture, size: size, theme: theme, in: directory)
                    receipt.captures.append(capture)
                    try writeReceipt(receipt, in: directory)
                    #expect(capture.pixelWidth > 0 && capture.pixelHeight > 0)
                    #expect(capture.sampledVisiblePixels > 100)
                    #expect(capture.sampledDistinctColors > 16, "The view must draw more than a flat background.")
                    #expect(capture.fittingWidth <= size.width + 1, "The editor's minimum width must fit the window.")
                    #expect(
                        capture.fittingHeight <= size.height + 1,
                        "The editor's minimum height must fit the window."
                    )
                    if capture.accessibilityAvailable {
                        #expect(
                            capture.missingControlIdentifiers.isEmpty,
                            "Required editor actions must remain accessible."
                        )
                        #expect(
                            capture.controlsOutsideBounds.isEmpty,
                            "Visible editor actions must fit the content bounds."
                        )
                        #expect(
                            capture.unexpectedControlIdentifiers.isEmpty,
                            "Cube painting controls must appear only in the relevant rendering and editing mode."
                        )
                    }
                }
            }
        }
        #expect(receipt.captures.count == 32)
        #expect(Set(receipt.captures.map(\.file)).count == receipt.captures.count)
        receipt.complete = true
        try writeReceipt(receipt, in: directory)
        print("Retained editor presentation captures: \(directory.path)")
    }
}

@MainActor
private func capture(
    fixture: PresentationFixture,
    size: CGSize,
    theme: PresentationTheme,
    in directory: URL
) async throws -> PresentationCapture {
    let workspace = SculptureWorkspace()
    if fixture.documentID != "character-orb" {
        let example = try #require(SculptureExamples.all.first { $0.id == fixture.documentID })
        workspace.replace(with: example.sculpture)
        workspace.column = example.sculpture.width / 2
        workspace.row = example.sculpture.height / 2
        let dimension = fixture.documentID == "grand-solar-system" ? 256 : 64
        #expect(
            workspace.sculpture.width == dimension && workspace.sculpture.height == dimension
                && workspace.sculpture.depth == dimension
        )
        if example.category == "Space" { workspace.camera.pitch = 0.7 }
    }
    workspace.renderStyle = fixture.style
    workspace.paintsIn3D = fixture.paintsIn3D
    let root = SculptureEditor(workspace: workspace, mode: fixture.mode)
        .environment(\.colorScheme, theme == .light ? .light : .dark)
    let hosting = NSHostingView(rootView: root)
    hosting.sizingOptions = []
    hosting.autoresizingMask = [.width, .height]
    hosting.appearance = NSAppearance(named: theme == .light ? .aqua : .darkAqua)
    let window = NSWindow(
        contentRect: CGRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.isExcludedFromWindowsMenu = true
    window.appearance = hosting.appearance
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
    hosting.displayIfNeeded()
    #expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow)
    let fitting = hosting.fittingSize
    let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let name = "\(fixture.filePrefix)-\(Int(size.width))x\(Int(size.height))-\(theme.rawValue).png"
    try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    let pixels = sampledPixels(bitmap)
    let accessibility = accessibilityNodes(hosting: hosting, window: window)
    let identifiers = Set(accessibility.map(\.identifier).filter { !$0.isEmpty })
    let available = !identifiers.isEmpty
    let required = requiredControlIdentifiers(for: fixture)
    let forbidden = forbiddenControlIdentifiers(for: fixture)
    let visibleRequiredNodes = accessibility.filter {
        required.contains($0.identifier) && $0.frame.width > 0 && $0.frame.height > 0
    }
    let outside = visibleRequiredNodes.filter {
        !hosting.bounds.insetBy(dx: -1, dy: -1).contains($0.frame.cgRect)
    }.map(\.identifier)
    #expect(!window.isVisible && !window.isKeyWindow && !window.isMainWindow)
    return PresentationCapture(
        file: name,
        fixture: fixture.id,
        mode: fixture.mode.rawValue,
        style: fixture.style.rawValue,
        paintsIn3D: fixture.paintsIn3D,
        documentID: fixture.documentID,
        documentTitle: workspace.sculpture.title,
        documentWidth: workspace.sculpture.width,
        documentHeight: workspace.sculpture.height,
        documentDepth: workspace.sculpture.depth,
        theme: theme.rawValue,
        logicalWidth: size.width,
        logicalHeight: size.height,
        pixelWidth: bitmap.pixelsWide,
        pixelHeight: bitmap.pixelsHigh,
        pngBytes: data.count,
        fittingWidth: fitting.width,
        fittingHeight: fitting.height,
        sampledVisiblePixels: pixels.visible,
        sampledDistinctColors: pixels.colors,
        metalAvailable: MetalSculptureView.isAvailable,
        accessibilityAvailable: available,
        unverifiedControls: available ? [] : required.sorted(),
        accessibilityGeometryAvailable: required.isSubset(of: Set(visibleRequiredNodes.map(\.identifier))),
        requiredControlIdentifiers: required.sorted(),
        missingControlIdentifiers: available ? required.subtracting(identifiers).sorted() : [],
        unexpectedControlIdentifiers: available ? forbidden.intersection(identifiers).sorted() : [],
        controlsOutsideBounds: outside.sorted(),
        accessibility: accessibility,
        cameraYaw: workspace.camera.yaw,
        cameraPitch: workspace.camera.pitch,
        cameraZoom: workspace.camera.zoom
    )
}

private func requiredControlIdentifiers(for fixture: PresentationFixture) -> Set<String> {
    let common: Set<String> = [
        "editor.document.title", "editor.document.save", "editor.examples", "editor.export",
        "editor.commands.open", "editor.mode.sculpt", "editor.mode.slice", "editor.render-style",
    ]
    switch fixture.mode {
    case .sculpt:
        var required = common.union(["editor.canvas", "editor.camera.fit", "editor.edit-slice"])
        if fixture.style == .cubes { required.insert("editor.voxel.paint-mode") }
        if fixture.style == .cubes, fixture.paintsIn3D {
            required.formUnion(["editor.voxel.tool", "editor.voxel.material"])
        }
        return required
    case .slice:
        return common.union([
            "editor.slice.grid", "editor.tool", "editor.brush.35", "editor.slice.actions",
            "editor.slice.zoom.fit", "editor.slice.zoom.2x", "editor.slice.zoom.4x",
            "editor.slice.zoom.8x", "editor.slice.zoom.16x",
        ])
    }
}

private func forbiddenControlIdentifiers(for fixture: PresentationFixture) -> Set<String> {
    var forbidden: Set<String> = []
    if fixture.mode != .sculpt || fixture.style != .cubes { forbidden.insert("editor.voxel.paint-mode") }
    if fixture.mode != .sculpt || fixture.style != .cubes || !fixture.paintsIn3D {
        forbidden.formUnion(["editor.voxel.tool", "editor.voxel.material"])
    }
    return forbidden
}

@MainActor
private func sampledPixels(_ bitmap: NSBitmapImageRep) -> (visible: Int, colors: Int) {
    var visible = 0
    var colors: Set<UInt32> = []
    let stepX = max(1, bitmap.pixelsWide / 64)
    let stepY = max(1, bitmap.pixelsHigh / 64)
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.01 else {
                continue
            }
            visible += 1
            let red = UInt32(max(0, min(255, Int((color.redComponent * 255).rounded()))))
            let green = UInt32(max(0, min(255, Int((color.greenComponent * 255).rounded()))))
            let blue = UInt32(max(0, min(255, Int((color.blueComponent * 255).rounded()))))
            colors.insert((red << 16) | (green << 8) | blue)
        }
    }
    return (visible, colors.count)
}

@MainActor
private func accessibilityNodes(hosting: NSView, window: NSWindow) -> [AccessibilityCapture] {
    var pending: [Any] = [hosting]
    var visited: Set<ObjectIdentifier> = []
    var captures: [AccessibilityCapture] = []
    while let object = pending.popLast(), visited.count < 2_000 {
        let identity = ObjectIdentifier(object as AnyObject)
        guard visited.insert(identity).inserted, let element = object as? any NSAccessibilityProtocol else { continue }
        let frame = hosting.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
        captures.append(
            AccessibilityCapture(
                identifier: element.accessibilityIdentifier() ?? "",
                label: element.accessibilityLabel() ?? "",
                role: element.accessibilityRole()?.rawValue ?? "",
                frame: PresentationBounds(frame)
            )
        )
        pending.append(contentsOf: element.accessibilityChildren() ?? [])
    }
    return captures
}

private func writeReceipt(_ receipt: PresentationReceipt, in directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(receipt).write(to: directory.appendingPathComponent("receipt.json"), options: .atomic)
}

private enum PresentationTheme: String, CaseIterable { case light, dark }

private struct PresentationFixture: Sendable {
    let id: String
    let filePrefix: String
    let mode: SculptureEditorMode
    let style: SculptureRenderStyle
    let paintsIn3D: Bool
    let documentID: String
}

private struct PresentationReceipt: Encodable {
    let schema = "rook-editor-presentation-1"
    let createdAt = Date()
    let method = "NSHostingView.cacheDisplay in an unshown offscreen AppKit window"
    let limitation =
        "AppKit bitmap caching may omit CAMetalLayer drawable contents. These captures record native presentation and accessibility; they do not replace separate Metal rendering verification. No desktop automation or baseline comparison is performed."
    var complete = false
    var captures: [PresentationCapture] = []
}

private struct PresentationCapture: Encodable {
    let file: String
    let fixture: String
    let mode: String
    let style: String
    let paintsIn3D: Bool
    let documentID: String
    let documentTitle: String
    let documentWidth: Int
    let documentHeight: Int
    let documentDepth: Int
    let theme: String
    let logicalWidth: CGFloat
    let logicalHeight: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    let pngBytes: Int
    let fittingWidth: CGFloat
    let fittingHeight: CGFloat
    let sampledVisiblePixels: Int
    let sampledDistinctColors: Int
    let metalAvailable: Bool
    let accessibilityAvailable: Bool
    /// Controls this capture could not verify because the offscreen host exposed no accessibility tree.
    let unverifiedControls: [String]
    let accessibilityGeometryAvailable: Bool
    let requiredControlIdentifiers: [String]
    let missingControlIdentifiers: [String]
    let unexpectedControlIdentifiers: [String]
    let controlsOutsideBounds: [String]
    let accessibility: [AccessibilityCapture]
    let cameraYaw: Double
    let cameraPitch: Double
    let cameraZoom: Double
}

private struct AccessibilityCapture: Encodable {
    let identifier: String
    let label: String
    let role: String
    let frame: PresentationBounds
}

private struct PresentationBounds: Encodable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init(_ rect: CGRect) {
        x = rect.minX
        y = rect.minY
        width = rect.width
        height = rect.height
    }
}
