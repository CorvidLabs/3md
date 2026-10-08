import AppKit
import CoreGraphics
import Foundation
import RookSculpture
import SceneKit
import Testing

@testable import RookRendering

@Suite(.serialized)
@MainActor
struct SculptureLiveWorldTests {
    @Test func largeIntegerAnchorsPreserveAdjacentPositionsPickingAndSharedGeometryAcrossCameraUpdates() throws {
        let model = try Sculpture(title: "One cube", width: 1, height: 1, layers: [[43]])
        let anchor: Int64 = 9_007_199_254_740_999
        let focus = SculptureWorldPoint(x: anchor, y: -anchor, z: anchor)
        let world = try SculptureWorld(
            title: "Large coordinate world",
            library: library(["cube": model]),
            instances: [
                SculptureWorldInstance(
                    id: "near",
                    modelID: "cube",
                    origin: .init(x: anchor + 3, y: -anchor - 2, z: anchor)
                ),
                SculptureWorldInstance(
                    id: "adjacent",
                    modelID: "cube",
                    origin: .init(x: anchor + 4, y: -anchor - 2, z: anchor)
                ),
                SculptureWorldInstance(id: "overflow-away", modelID: "cube", origin: .init(x: Int64.min, y: 0, z: 0)),
            ]
        )
        let scene = try SculptureWorldScene.prepare(world)
        #expect(scene.modelCount == 1)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 320)
        let id = UUID()
        controller.configure(
            scene: scene,
            sceneID: id,
            focus: focus,
            renderDistance: 16,
            detailDistance: 16,
            camera: .init(yaw: 0, pitch: 0)
        )
        SCNTransaction.flush()
        #expect(controller.totalInstanceCount == 3)
        #expect(controller.visibleInstanceCount == 2 && controller.fullDetailInstanceCount == 2)
        #expect(controller.culledInstanceCount == 1 && controller.omittedInstanceCount == 0)
        let near = try instance("near", in: view)
        let adjacent = try instance("adjacent", in: view)
        #expect(near.position.x == 3 && near.position.y == 2 && near.position.z == 0)
        #expect(adjacent.position.x - near.position.x == 1)
        let nearGeometry = try #require(near.childNodes.first?.geometry)
        let adjacentGeometry = try #require(adjacent.childNodes.first?.geometry)
        #expect(nearGeometry === adjacentGeometry)
        let source = try #require(nearGeometry.sources(for: .vertex).first)
        let element = try #require(nearGeometry.elements.first)
        for (name, point) in [("near", SCNVector3(3, 2, 0.5)), ("adjacent", SCNVector3(4, 2, 0.5))] {
            let projected = view.projectPoint(point)
            #expect(controller.hitTest(x: Double(projected.x), y: 320 - Double(projected.y)) == name)
        }
        for pose in 0..<32 {
            controller.configure(
                scene: scene,
                sceneID: id,
                focus: focus,
                renderDistance: 16,
                detailDistance: 16,
                camera: .init(yaw: Double(pose) / 10, pitch: 0.4, zoom: 0.8 + Double(pose % 3) / 10)
            )
            #expect(try instance("near", in: view) === near)
            #expect(near.childNodes.first?.geometry === nearGeometry)
            #expect(nearGeometry.sources(for: .vertex).first === source)
            #expect(nearGeometry.elements.first === element)
        }
        #expect(controller.meshInstallationCount == 1)
        controller.configure(
            scene: scene,
            sceneID: id,
            focus: .init(x: anchor + 1, y: -anchor, z: anchor),
            renderDistance: 16,
            detailDistance: 16,
            camera: .init()
        )
        #expect(try instance("near", in: view).position.x == 2)
        #expect(try instance("near", in: view).childNodes.first?.geometry === nearGeometry)
        #expect(controller.meshInstallationCount == 1)
        #expect(controller.hitTest(x: .nan, y: 0) == nil)
        #expect(controller.hitTest(x: 400, y: 160) == nil)
    }

    @Test func boundingIntersectionRotationAndDetailDistanceControlDetailedAndColoredCoarseNodes() throws {
        let wide = try Sculpture(title: "Long model", width: 6, height: 1, layers: [Array(repeating: 35, count: 6)])
        let corners = try Sculpture(title: "Asymmetric model", width: 2, height: 3, layers: [Array("#....+".utf8)])
        let world = try SculptureWorld(
            title: "World bounds",
            library: library(["wide": wide, "corners": corners]),
            instances: [
                SculptureWorldInstance(id: "intersects", modelID: "wide", origin: .init(x: -5, y: 0, z: 0)),
                SculptureWorldInstance(
                    id: "outside",
                    modelID: "wide",
                    origin: .init(x: 4, y: 0, z: 0),
                    quarterTurns: 1
                ),
                SculptureWorldInstance(
                    id: "rotated",
                    modelID: "corners",
                    origin: .init(x: 8, y: 0, z: 0),
                    quarterTurns: 1
                ),
            ]
        )
        let scene = try SculptureWorldScene.prepare(world)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 320)
        let id = UUID()
        let focus = SculptureWorldPoint(x: 0, y: 0, z: 0)
        controller.configure(
            scene: scene,
            sceneID: id,
            focus: focus,
            renderDistance: 2,
            detailDistance: 2,
            camera: .init(yaw: 0, pitch: 0)
        )
        #expect(controller.visibleInstanceCount == 1)
        #expect(controller.culledInstanceCount == 2)
        #expect(try instance("intersects", in: view).childNodes.first?.name == "world.detail")
        controller.configure(
            scene: scene,
            sceneID: id,
            focus: focus,
            renderDistance: 16,
            detailDistance: 2,
            camera: .init(yaw: 0, pitch: 0)
        )
        SCNTransaction.flush()
        #expect(controller.visibleInstanceCount == 3)
        #expect(controller.fullDetailInstanceCount == 1 && controller.proxyInstanceCount == 2)
        #expect(controller.coarseInstanceCount == 2 && controller.boundsProxyInstanceCount == 0)
        let coarse = try #require(try instance("rotated", in: view).childNodes.first)
        #expect(coarse.name == "world.coarse")
        let geometry = try #require(coarse.geometry)
        #expect(!(geometry is SCNBox))
        #expect(geometry.firstMaterial?.fillMode == .fill)
        #expect(geometry.sources(for: .color).count == 1)
        #expect(geometry.elements.first?.primitiveType == .triangles)
        let point = view.projectPoint(SCNVector3(10, 0, 0.5))
        #expect(controller.hitTest(x: Double(point.x), y: 320 - Double(point.y)) == "rotated")
        controller.configure(
            scene: scene,
            sceneID: id,
            focus: focus,
            renderDistance: 16,
            detailDistance: 16,
            camera: .init(yaw: 0, pitch: 0)
        )
        SCNTransaction.flush()
        #expect(controller.fullDetailInstanceCount == 3 && controller.proxyInstanceCount == 0)
        #expect(controller.coarseInstanceCount == 0 && controller.boundsProxyInstanceCount == 0)
        let rotated = try instance("rotated", in: view)
        #expect(abs(rotated.eulerAngles.z + .pi / 2) < 0.0001)
        #expect(rotated.position.x == 9 && rotated.position.y == -0.5)
        let actualCorner = view.projectPoint(SCNVector3(10, 0, 0.5))
        #expect(controller.hitTest(x: Double(actualCorner.x), y: 320 - Double(actualCorner.y)) == "rotated")
        let emptyCorner = view.projectPoint(SCNVector3(8, 0, 0.5))
        #expect(controller.hitTest(x: Double(emptyCorner.x), y: 320 - Double(emptyCorner.y)) == nil)
        #expect(controller.meshInstallationCount == 2)
    }

    @Test func visibleCapacityAndFullFaceBudgetDegradeToBoundedSharedProxiesDeterministically() throws {
        let checker = try checkerboard(size: 16)
        let instances = try (0..<620).map { index in
            try SculptureWorldInstance(
                id: String(format: "instance-%04d", index),
                modelID: "checker",
                origin: .init(x: 0, y: 0, z: 0)
            )
        }
        let world = try SculptureWorld(
            title: "Dense placement capacity",
            library: library(["checker": checker]),
            instances: Array(instances.reversed())
        )
        let scene = try SculptureWorldScene.prepare(world)
        let faces = try #require(scene.models["checker"]?.surfaces.count)
        #expect(faces > 10_000 && faces < SculptureLiveWorldController.maximumFullDetailFaces)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 320)
        controller.configure(
            scene: scene,
            sceneID: UUID(),
            focus: .init(x: 0, y: 0, z: 0),
            renderDistance: 32,
            detailDistance: 32,
            camera: .init()
        )
        #expect(controller.totalInstanceCount == 620)
        #expect(controller.visibleInstanceCount == 512 && controller.omittedInstanceCount == 108)
        #expect(controller.culledInstanceCount == 0)
        #expect(controller.fullDetailInstanceCount > 0 && controller.fullDetailInstanceCount < 512)
        #expect(controller.proxyInstanceCount == 512 - controller.fullDetailInstanceCount)
        #expect(controller.proxyInstanceCount == controller.coarseInstanceCount + controller.boundsProxyInstanceCount)
        #expect(controller.detailBudgetProxyInstanceCount == controller.proxyInstanceCount)
        #expect(controller.renderedExteriorFaceCount <= SculptureLiveWorldController.maximumFullDetailFaces)
        let coarseFaces = try #require(scene.coarseMeshes["checker"]?.faceCount)
        #expect(
            controller.renderedExteriorFaceCount == controller.fullDetailInstanceCount * faces
                + controller.coarseInstanceCount * coarseFaces + controller.boundsProxyInstanceCount * 6
        )
        let root = try #require(view.scene?.rootNode.childNode(withName: "world.instances", recursively: false))
        #expect(root.childNodes.count == 512)
        #expect(root.childNodes.first?.name == "world.instance.instance-0000")
        #expect(root.childNodes.last?.name == "world.instance.instance-0511")
        let proxies = root.childNodes.compactMap { $0.childNodes.first }.filter { $0.name == "world.proxy" }
        #expect(proxies.count == controller.boundsProxyInstanceCount && !proxies.isEmpty)
        #expect(proxies.allSatisfy { $0.geometry is SCNBox && $0.geometry?.firstMaterial?.fillMode == .lines })
        #expect(proxies.first?.geometry === proxies.last?.geometry)
        #expect(controller.meshInstallationCount == 1)
    }

    @Test func preparationSkipsUnusedDefinitionsAndRejectsAnOversizedAggregateCache() throws {
        let cube = try Sculpture(title: "Referenced cube", width: 1, height: 1, layers: [[35]])
        let unused = try checkerboard(size: 56)
        let sparse = try SculptureWorld(
            title: "Used model only",
            library: library(["cube": cube, "unused": unused]),
            instances: [SculptureWorldInstance(id: "only", modelID: "cube", origin: .init(x: 0, y: 0, z: 0))]
        )
        let scene = try SculptureWorldScene.prepare(sparse)
        #expect(scene.modelCount == 1 && scene.models["unused"] == nil)
        let checker = try checkerboard(size: 32)
        let models = Dictionary(uniqueKeysWithValues: (0..<11).map { ("model-\($0)", checker) })
        let world = try SculptureWorld(
            title: "Prepared cache limit",
            library: library(models),
            instances: (0..<11).map {
                try SculptureWorldInstance(
                    id: "placement-\($0)",
                    modelID: "model-\($0)",
                    origin: .init(x: Int64($0 * 40), y: 0, z: 0)
                )
            }
        )
        #expect(throws: SculptureWorldRenderingError.self) { try SculptureWorldScene.prepare(world) }
    }

    @Test func actualMetalWorldSnapshotsContainColoredDetailsSelectableCoarseModelsAndRetainedEvidence() throws {
        _ = NSApplication.shared
        let model = try Sculpture(
            title: "Colored block",
            width: 3,
            height: 3,
            layers: [
                Array(repeating: UInt8(43), count: 9), Array(repeating: UInt8(111), count: 9),
                Array(repeating: UInt8(64), count: 9),
            ]
        )
        let world = try SculptureWorld(
            title: "Live sparse snapshot",
            library: library(["block": model]),
            instances: [
                SculptureWorldInstance(id: "detail", modelID: "block", origin: .init(x: -4, y: 0, z: 0)),
                SculptureWorldInstance(id: "outline", modelID: "block", origin: .init(x: 12, y: 0, z: 0)),
                SculptureWorldInstance(id: "far-away", modelID: "block", origin: .init(x: 1_000_000_000, y: 0, z: 0)),
            ]
        )
        let scene = try SculptureWorldScene.prepare(world)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 480, height: 360)
        #expect(controller.renderingAPI == .metal)
        let id = UUID()
        let folder = try evidenceFolder()
        var receipts: [WorldReceipt] = []
        var frames = Set<Data>()
        for (pose, camera) in [
            ("front", SculptureCamera(yaw: 0, pitch: 0)), ("orbit", SculptureCamera(yaw: -0.6, pitch: 0.5)),
        ] {
            controller.configure(
                scene: scene,
                sceneID: id,
                focus: .init(x: 0, y: 0, z: 0),
                renderDistance: 16,
                detailDistance: 4,
                camera: camera
            )
            SCNTransaction.flush()
            #expect(controller.visibleInstanceCount == 2)
            #expect(controller.fullDetailInstanceCount == 1 && controller.proxyInstanceCount == 1)
            #expect(controller.coarseInstanceCount == 1 && controller.boundsProxyInstanceCount == 0)
            #expect(controller.culledInstanceCount == 1)
            let image = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
            let pixels = try rgbaPixels(image)
            let background = Array(pixels.prefix(3))
            var changedPixels = 0
            var bluePixels = 0
            for index in stride(from: 0, to: pixels.count, by: 4) {
                let difference = (0..<3).reduce(0) { $0 + abs(Int(pixels[index + $1]) - Int(background[$1])) }
                if difference > 16 { changedPixels += 1 }
                if Int(pixels[index + 2]) > Int(pixels[index]) + 18 { bluePixels += 1 }
            }
            #expect(changedPixels > 200)
            #expect(bluePixels > 25)
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: folder.appendingPathComponent("\(pose).png"), options: .atomic)
            frames.insert(png)
            receipts.append(
                WorldReceipt(
                    pose: pose,
                    width: image.width,
                    height: image.height,
                    renderer: "SceneKit Metal",
                    total: controller.totalInstanceCount,
                    visible: controller.visibleInstanceCount,
                    detailed: controller.fullDetailInstanceCount,
                    proxies: controller.proxyInstanceCount,
                    coarse: controller.coarseInstanceCount,
                    boundsFallback: controller.boundsProxyInstanceCount,
                    culled: controller.culledInstanceCount,
                    changedPixels: changedPixels,
                    bluePixels: bluePixels
                )
            )
            let outline = try instance("outline", in: view)
            let point = view.projectPoint(outline.position)
            #expect(
                controller.hitTest(x: Double(point.x), y: Double(view.bounds.height) - Double(point.y)) == "outline"
            )
        }
        #expect(frames.count == 2 && controller.meshInstallationCount == 1)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipts).write(to: folder.appendingPathComponent("receipt.json"), options: .atomic)
    }

    @Test func nestedGardenAndCourtyardKeepGlyphColorsAcrossDenseNativeEdges() throws {
        _ = NSApplication.shared
        let composition = try SculptureCompositionExamples.courtyard()
        let folder = try evidenceFolder()
        var receipts: [CourtyardColorReceipt] = []
        for (modelID, name) in [("garden", "nested-garden"), ("root", "nested-courtyard")] {
            let expanded = try composition.expanded(modelID: modelID)
            #expect(expanded.occupiedCount > 1_000)
            let world = try SculptureWorld(
                title: "Native nested color regression",
                library: composition,
                instances: [
                    SculptureWorldInstance(
                        id: name,
                        modelID: modelID,
                        origin: .init(
                            x: -Int64(expanded.width / 2),
                            y: -Int64(expanded.height / 2),
                            z: -Int64(expanded.depth / 2)
                        )
                    )
                ]
            )
            let scene = try SculptureWorldScene.prepare(world)
            let controller = SculptureLiveWorldController()
            let view = controller.makeView()
            view.frame = CGRect(x: 0, y: 0, width: 640, height: 420)
            let radius = max(expanded.width, expanded.height, expanded.depth) * 2 / 3
            let camera = SculptureCamera(yaw: -0.6, pitch: 0.55, zoom: 0.9)
            controller.configure(
                scene: scene,
                sceneID: UUID(),
                focus: .init(x: 0, y: 0, z: 0),
                renderDistance: radius,
                detailDistance: radius,
                camera: camera
            )
            SCNTransaction.flush()
            #expect(controller.renderingAPI == .metal)
            #expect(controller.fullDetailInstanceCount == 1 && controller.proxyInstanceCount == 0)
            let node = try instance(name, in: view)
            let fill = try #require(node.childNodes.first(where: { $0.name == "world.detail" })?.geometry)
            let edges = try #require(
                node.childNodes.first(where: { $0.geometry?.elements.first?.primitiveType == .line })?.geometry
            )
            let fillColors = try #require(fill.sources(for: .color).first)
            let edgeColors = try #require(edges.sources(for: .color).first)
            #expect(edgeColors === fillColors)
            let image = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
            let pixels = try rgbaPixels(image)
            let background = Array(pixels.prefix(3))
            var changedPixels = 0
            var coloredPixels = 0
            var neutralBrightPixels = 0
            for index in stride(from: 0, to: pixels.count, by: 4) {
                let channels = (0..<3).map { Int(pixels[index + $0]) }
                let difference = (0..<3).reduce(0) { $0 + abs(channels[$1] - Int(background[$1])) }
                guard difference > 16 else { continue }
                changedPixels += 1
                let maximum = channels.max() ?? 0, minimum = channels.min() ?? 0
                if maximum - minimum > 18 { coloredPixels += 1 }
                if minimum > 50 && maximum - minimum < 12 { neutralBrightPixels += 1 }
            }
            #expect(changedPixels > 1_000)
            #expect(coloredPixels * 2 > changedPixels)
            #expect(neutralBrightPixels * 5 < changedPixels)
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
            receipts.append(
                CourtyardColorReceipt(
                    model: name,
                    width: image.width,
                    height: image.height,
                    occupiedCount: expanded.occupiedCount,
                    exteriorFaces: controller.renderedExteriorFaceCount,
                    changedPixels: changedPixels,
                    coloredPixels: coloredPixels,
                    neutralBrightPixels: neutralBrightPixels
                )
            )
            controller.updateCamera(.init(yaw: 0.4, pitch: 0.35))
            #expect(edges.sources(for: .color).first === edgeColors)
            #expect(controller.meshInstallationCount == 1)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipts).write(
            to: folder.appendingPathComponent("nested-colors-receipt.json"),
            options: .atomic
        )
    }

    private func library(_ models: [String: Sculpture]) throws -> SculptureComposition {
        let id = try #require(models.keys.sorted().first)
        let model = try #require(models[id])
        let map = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[67]],
            tileSize: SculptureTileSize(width: model.width, height: model.height, depth: model.depth),
            bindings: [SculptureModelBinding(glyph: 67, modelID: id)]
        )
        var entries = models.mapValues { SculptureCompositionModel.sculpture($0) }
        entries["root"] = .tiles(map)
        return try SculptureComposition(title: "World model library", rootID: "root", models: entries)
    }

    private func checkerboard(size: Int) throws -> Sculpture {
        let layers = (0..<size).map { z in
            (0..<size * size).map { index in
                (index % size + index / size + z).isMultiple(of: 2) ? UInt8(35) : Sculpture.empty
            }
        }
        return try Sculpture(title: "Checkerboard budget fixture", width: size, height: size, layers: layers)
    }

    private func instance(_ id: String, in view: SCNView) throws -> SCNNode {
        try #require(view.scene?.rootNode.childNode(withName: "world.instance.\(id)", recursively: true))
    }

    private func evidenceFolder() throws -> URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let folder = repository.appendingPathComponent(".build/verification/live-world-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
            return true
        }
        try #require(rendered)
        return bytes
    }

    private struct WorldReceipt: Codable {
        let pose: String
        let width: Int
        let height: Int
        let renderer: String
        let total: Int
        let visible: Int
        let detailed: Int
        let proxies: Int
        let coarse: Int
        let boundsFallback: Int
        let culled: Int
        let changedPixels: Int
        let bluePixels: Int
    }

    private struct CourtyardColorReceipt: Codable {
        let model: String
        let width: Int
        let height: Int
        let occupiedCount: Int
        let exteriorFaces: Int
        let changedPixels: Int
        let coloredPixels: Int
        let neutralBrightPixels: Int
    }
}
