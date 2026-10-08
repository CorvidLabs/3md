import AppKit
import Foundation
import Metal
import RookRendering
import RookSculpture
import SceneKit
import SwiftUI

struct Result: Codable {
    let dimensions: [Int]
    let occupiedCells: Int
    let exteriorFaces: Int
    let extractionMilliseconds: Double
    let installationMilliseconds: Double
    let meshInstallationCount: Int
    let cameraUpdates: Int
    let cameraUpdateMedianMilliseconds: Double
    let cameraUpdateMaximumMilliseconds: Double
    let offscreenGPUFrameMedianMilliseconds: Double
    let offscreenGPUFrameMaximumMilliseconds: Double
    let backend: String
    let note: String
}

func milliseconds(_ start: ContinuousClock.Instant) -> Double {
    let components = start.duration(to: .now).components
    return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
}

@MainActor func findCanvas(_ parent: NSView) -> SCNView? {
    if let canvas = parent as? SCNView { return canvas }
    return parent.subviews.lazy.compactMap(findCanvas).first
}

@main struct Benchmark {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/Users/leif/Development/_CorvidLabs/rook")
        let sculpture = try SculptureDocumentCodec.decode(
            Data(contentsOf: root.appendingPathComponent("Examples/grand-solar-system.3mdb"))
        )
        let extractionStart = ContinuousClock.now
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        let extractionMilliseconds = milliseconds(extractionStart)
        let controller = SculptureLiveVoxelController()
        let sceneID = UUID()
        let installationStart = ContinuousClock.now
        let host = NSHostingView(
            rootView: SculptureLiveVoxelView(
                scene: scene,
                sceneID: sceneID,
                camera: .init(),
                selectedLayer: 128,
                opacity: 0.35,
                emptyCells: [],
                controller: controller
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 1_100, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(5)
        while controller.installedSceneID != sceneID, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
        }
        guard controller.installedSceneID == sceneID, let canvas = findCanvas(host),
            canvas.renderingAPI == .metal, let device = MTLCreateSystemDefaultDevice()
        else {
            fatalError(
                "Live Metal scene was not installed: id=\(controller.installedSceneID == sceneID), canvas=\(findCanvas(host) != nil), API=\(String(describing: findCanvas(host)?.renderingAPI))"
            )
        }
        let installationMilliseconds = milliseconds(installationStart)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = canvas.scene
        renderer.pointOfView = canvas.pointOfView
        renderer.scene?.background.contents = NSColor(calibratedRed: 0.065, green: 0.085, blue: 0.10, alpha: 1)
        var updates: [Double] = []
        var frames: [Double] = []
        for index in 0..<128 {
            let start = ContinuousClock.now
            controller.updateCamera(.init(yaw: 0.65 + Double(index) * 0.025, pitch: 0.7, zoom: 0.9))
            let submitted = milliseconds(start)
            let gpuStart = ContinuousClock.now
            let image = renderer.snapshot(
                atTime: Double(index) / 60,
                with: CGSize(width: 1_100, height: 700),
                antialiasingMode: .multisampling4X
            )
            guard image.size.width > 0 else { fatalError("GPU snapshot failed") }
            let rendered = milliseconds(gpuStart)
            if index == 127, let tiff = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiff),
                let png = bitmap.representation(using: .png, properties: [:])
            {
                try png.write(
                    to: root.appendingPathComponent("docs/evidence/camera-performance/solar-metal.png"),
                    options: .atomic
                )
            }
            if index >= 8 { updates.append(submitted); frames.append(rendered) }
        }
        guard controller.meshInstallationCount == 1 else { fatalError("Camera update rebuilt the mesh") }
        updates.sort(); frames.sort()
        let result = Result(
            dimensions: [scene.width, scene.height, scene.depth],
            occupiedCells: scene.occupiedCount,
            exteriorFaces: scene.surfaces.count,
            extractionMilliseconds: extractionMilliseconds,
            installationMilliseconds: installationMilliseconds,
            meshInstallationCount: controller.meshInstallationCount,
            cameraUpdates: updates.count,
            cameraUpdateMedianMilliseconds: updates[updates.count / 2],
            cameraUpdateMaximumMilliseconds: updates.last!,
            offscreenGPUFrameMedianMilliseconds: frames[frames.count / 2],
            offscreenGPUFrameMaximumMilliseconds: frames.last!,
            backend: "SceneKit Metal",
            note:
                "Optimized release objects, 1100x700, 4x MSAA, 8 warmup frames then 120 measured camera updates and synchronous offscreen GPU snapshots. Excludes decode/file IO. Not an on-screen FPS measurement."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        try data.write(
            to: root.appendingPathComponent("docs/evidence/camera-performance/live-release.json"),
            options: .atomic
        )
        FileHandle.standardOutput.write(data)
    }
}
