import AppKit
import CoreGraphics
import Darwin
import Foundation
import Metal
import RookSculpture
import SceneKit
import Testing
import simd

@testable import RookRendering

@Suite(.serialized)
@MainActor
struct SculptureWorldExplorationRenderingTests {
    /// Explicit evidence capture only. Ordinary CI returns before preparing a world or creating files.
    @Test func optionalActualMetalOverviewAndLandmarkExplorationEvidence() throws {
        guard let path = ProcessInfo.processInfo.environment["ROOK_WORLD_EXPLORATION_EVIDENCE"] else { return }
        try #require(path.hasPrefix("/") && !path.isEmpty, "Evidence destination must be an absolute new directory.")
        _ = NSApplication.shared
        let output = try evidenceDirectory(URL(fileURLWithPath: path).standardizedFileURL)
        defer { close(output.directory); close(output.parent) }
        let world = try SculptureVolumeStudyExamples.landscapeWorld()
        let original = try SculptureWorldCodec.encode(world)
        let scene = try SculptureWorldScene.prepare(world)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        try #require(controller.renderingAPI == .metal)
        let emptyController = SculptureLiveWorldController()
        let emptyView = emptyController.makeView()
        emptyView.frame = view.frame
        let emptyWorld = try SculptureWorld(title: "Empty camera reference", library: world.library, instances: [])
        let emptyScene = try SculptureWorldScene.prepare(emptyWorld, cachedModels: scene)
        let emptyID = UUID()
        let castle = try #require(world.instances.first { $0.modelID == "castle" })
        let citadel = try #require(world.instances.first { $0.modelID == "citadel" })
        let id = UUID()
        var frames: [EvidenceFrame] = []
        for (name, landmark) in [
            ("overview", Optional<SculptureWorldInstance>.none), ("valley-castle", castle), ("sky-citadel", citadel),
        ] {
            try Task.checkCancellation()
            let explorer = try landmark.map {
                try SculptureWorldExplorer(anchor: $0.origin, offset: SIMD3(32, 20, 96), yaw: 0, pitch: -0.08)
            }
            let focus = explorer?.anchor ?? SculptureWorldPoint(x: 511, y: 511, z: 511)
            configure(
                controller,
                scene: scene,
                id: id,
                focus: focus,
                camera: .init(yaw: -0.6, pitch: 0.45),
                mode: explorer == nil ? .orbit : .explore,
                explorer: explorer,
                renderDistance: explorer == nil ? 960 : 384,
                detailDistance: explorer == nil ? 128 : 192
            )
            configure(
                emptyController,
                scene: emptyScene,
                id: emptyID,
                focus: focus,
                camera: .init(yaw: -0.6, pitch: 0.45),
                mode: explorer == nil ? .orbit : .explore,
                explorer: explorer,
                renderDistance: explorer == nil ? 960 : 384,
                detailDistance: explorer == nil ? 128 : 192
            )
            SCNTransaction.flush()
            let clearImage = try #require(emptyView.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
            let background = Array(try imagePixels(clearImage).prefix(3))
            let image = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
            let pixels = try imagePixels(image)
            var changed = 0
            var colored = 0
            for offset in stride(from: 0, to: pixels.count, by: 4) {
                let rgb = (0..<3).map { Int(pixels[offset + $0]) }
                let difference = (0..<3).reduce(0) { $0 + abs(rgb[$1] - Int(background[$1])) }
                if difference > 16 {
                    changed += 1
                    if (rgb.max() ?? 0) - (rgb.min() ?? 0) > 18 { colored += 1 }
                }
            }
            try #require(image.width >= 800 && image.height >= 600 && changed > 100 && colored > 50)
            try #require(colored <= changed)
            if explorer == nil {
                try #require(changed < image.width * image.height * 3 / 4, "Overview must retain visible background.")
            }
            try #require(controller.totalInstanceCount == 280 && controller.visibleInstanceCount > 0)
            try #require(
                controller.totalInstanceCount == controller.visibleInstanceCount + controller.omittedInstanceCount
                    + controller.culledInstanceCount
            )
            try #require(
                controller.visibleInstanceCount == controller.fullDetailInstanceCount + controller.coarseInstanceCount
                    + controller.boundsProxyInstanceCount
            )
            try #require(controller.visibleInstanceCount <= SculptureLiveWorldController.maximumVisibleInstances)
            try #require(
                controller.boundsProxyInstanceCount == 0,
                "Skyreach's visible coarse models fit the face budget."
            )
            try #require(controller.renderedExteriorFaceCount <= SculptureLiveWorldController.maximumFullDetailFaces)
            let installed = try #require(
                view.scene?.rootNode.childNode(withName: "world.instances", recursively: false)
            )
            try #require(installed.childNodes.count == controller.visibleInstanceCount)
            let actualFaces = installed.childNodes.reduce(0) { total, node in
                guard let fill = node.childNodes.first else { return total }
                if fill.name == "world.proxy" { return total + 6 }
                return total
                    + (fill.geometry?.elements.filter { $0.primitiveType == .triangles }.reduce(0) {
                        $0 + $1.primitiveCount
                    } ?? 0) / 2
            }
            try #require(actualFaces == controller.renderedExteriorFaceCount)
            try #require(controller.meshInstallationCount == scene.modelCount)
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try writeEvidence(png, name: "\(name).png", output: output)
            frames.append(
                EvidenceFrame(
                    name: name,
                    mode: controller.currentMode.rawValue,
                    focus: focus,
                    explorer: explorer.map(EvidenceExplorer.init),
                    renderDistance: explorer == nil ? 960 : 384,
                    detailDistance: explorer == nil ? 128 : 192,
                    width: image.width,
                    height: image.height,
                    total: controller.totalInstanceCount,
                    visible: controller.visibleInstanceCount,
                    detailed: controller.fullDetailInstanceCount,
                    coarse: controller.coarseInstanceCount,
                    boundsFallback: controller.boundsProxyInstanceCount,
                    omitted: controller.omittedInstanceCount,
                    culled: controller.culledInstanceCount,
                    renderedExteriorFaces: controller.renderedExteriorFaceCount,
                    meshInstallations: controller.meshInstallationCount,
                    changedPixels: changed,
                    coloredPixels: colored,
                    clearBackgroundRGB: background,
                    filename: "\(name).png"
                )
            )
        }
        try #require(SculptureWorldCodec.encode(scene.world) == original)
        let receipt = EvidenceReceipt(
            schema: "sculpt-world-exploration-metal-1",
            suppliedSourceRevision: ProcessInfo.processInfo.environment["ROOK_WORLD_EXPLORATION_SOURCE_REVISION"],
            platform: ProcessInfo.processInfo.operatingSystemVersionString,
            renderer: "SceneKit Metal",
            device: view.device?.name,
            title: world.title,
            frames: frames,
            notes: [
                "Actual synchronized offscreen SCNView snapshots. No on-screen FPS or dense billion-voxel rendering claim.",
                "Overview and exploration retain the same immutable sparse world, source bytes and prepared model cache.",
                "Coarse models preserve colored silhouettes; bounds fallback covers budget limits, unavailable coarse meshes and empty geometry.",
                "Exterior faces count each installed detailed/coarse surface plus six per bounds fallback; shared chunk boundaries are not merged.",
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try writeEvidence(encoder.encode(receipt), name: "receipt.json", output: output)
        try requireEvidenceDirectory(output)
        guard
            renameatx_np(output.parent, output.stagingName, output.parent, output.destinationName, UInt32(RENAME_EXCL))
                == 0
        else {
            throw evidenceError("publish directory")
        }
        var published = stat()
        guard fstatat(output.parent, output.destinationName, &published, AT_SYMLINK_NOFOLLOW) == 0,
            published.st_dev == output.device, published.st_ino == output.inode,
            published.st_mode & S_IFMT == S_IFDIR
        else { throw evidenceError("verify published directory") }
    }

    @Test func perspectiveAndOrbitSwitchesRestoreCameraWithoutChangingWorldOrMeshes() throws {
        let focus = SculptureWorldPoint(x: 0, y: 0, z: 0)
        let world = try fixture(focus: focus)
        let original = try SculptureWorldCodec.encode(world)
        let scene = try SculptureWorldScene.prepare(world)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let id = UUID()
        let orbit = SculptureCamera(yaw: -0.4, pitch: 0.3, zoom: 1.2)
        configure(controller, scene: scene, id: id, focus: focus, camera: orbit)
        let cameraNode = try #require(view.pointOfView)
        let camera = try #require(cameraNode.camera)
        let orbitProjection = camera.projectionTransform
        let orbitTransform = cameraNode.simdTransform
        let near = try instance("near", in: view)
        let far = try instance("coarse", in: view)
        let detailedGeometry = try #require(near.childNodes.first?.geometry)
        let coarseGeometry = try #require(far.childNodes.first?.geometry)
        let initialCounts = counts(controller)
        for _ in 0..<3 {
            configure(
                controller,
                scene: scene,
                id: id,
                focus: focus,
                camera: orbit,
                mode: .explore,
                explorer: SculptureWorldExplorer(anchor: focus)
            )
            #expect(controller.currentMode == .explore)
            #expect(!camera.usesOrthographicProjection && camera.fieldOfView == 65 && camera.zNear == 0.2)
            #expect(controller.currentCamera == orbit)
            #expect(try instance("near", in: view) === near)
            #expect(try instance("coarse", in: view) === far)
            #expect(counts(controller) == initialCounts)
            configure(controller, scene: scene, id: id, focus: focus, camera: orbit)
            #expect(controller.currentMode == .orbit && controller.currentExplorer == nil)
            #expect(SCNMatrix4EqualToMatrix4(camera.projectionTransform, orbitProjection))
            #expect(cameraNode.simdTransform == orbitTransform)
        }
        #expect(near.childNodes.first?.geometry === detailedGeometry)
        #expect(far.childNodes.first?.geometry === coarseGeometry)
        #expect(controller.meshInstallationCount == 1 && controller.installedSceneID == id)
        #expect(scene.world == world)
        #expect(try SculptureWorldCodec.encode(scene.world) == original)
    }

    @Test func localTravelLookAndExactIntegerRebaseRetainDetailedAndCoarseBuffers() throws {
        let high: Int64 = 9_007_199_254_740_999
        let focus = SculptureWorldPoint(x: high, y: -high, z: high)
        let world = try fixture(focus: focus)
        let original = try SculptureWorldCodec.encode(world)
        let scene = try SculptureWorldScene.prepare(world)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let id = UUID()
        var explorer = SculptureWorldExplorer(anchor: focus)
        configure(controller, scene: scene, id: id, focus: focus, mode: .explore, explorer: explorer)
        let near = try instance("near", in: view)
        let adjacent = try instance("adjacent", in: view)
        let far = try instance("coarse", in: view)
        let detailedGeometry = try #require(near.childNodes.first?.geometry)
        let coarseGeometry = try #require(far.childNodes.first?.geometry)
        let detailVertex = try #require(detailedGeometry.sources(for: .vertex).first)
        let coarseColor = try #require(coarseGeometry.sources(for: .color).first)
        let detailElement = try #require(detailedGeometry.elements.first)
        let coarseElement = try #require(coarseGeometry.elements.first)
        #expect(adjacent.position.x - near.position.x == 1)
        for _ in 0..<8 {
            try explorer.move(forward: 1, right: 1, vertical: 1, speed: 0.25, duration: 1)
            explorer.look(horizontal: 0.03, vertical: -0.01)
            controller.updateExplorer(explorer)
            #expect(explorer.anchor == focus)
            #expect(try instance("near", in: view) === near)
            #expect(try instance("coarse", in: view) === far)
            #expect(detailedGeometry.sources(for: .vertex).first === detailVertex)
            #expect(coarseGeometry.sources(for: .color).first === coarseColor)
            #expect(detailedGeometry.elements.first === detailElement)
            #expect(coarseGeometry.elements.first === coarseElement)
        }
        let eye = try #require(view.pointOfView)
        #expect(
            eye.simdPosition == SIMD3(Float(explorer.offset.x), -Float(explorer.offset.y), Float(explorer.offset.z))
        )
        let rebased = try SculptureWorldExplorer(
            anchor: focus,
            offset: SIMD3(65.25, 0.25, -0.5),
            yaw: explorer.yaw,
            pitch: explorer.pitch
        )
        #expect(rebased.anchor == SculptureWorldPoint(x: high + 65, y: -high, z: high))
        #expect(rebased.offset == SIMD3(0.25, 0.25, -0.5))
        controller.updateExplorer(rebased)
        let movedNear = try instance("near", in: view)
        #expect(movedNear !== near && movedNear.position.x == -62)
        #expect(try instance("adjacent", in: view).position.x - movedNear.position.x == 1)
        #expect(movedNear.childNodes.first?.geometry === detailedGeometry)
        #expect(try instance("coarse", in: view).childNodes.first?.geometry === coarseGeometry)
        #expect(controller.fullDetailInstanceCount == 2 && controller.coarseInstanceCount == 1)
        #expect(controller.culledInstanceCount == 1 && controller.meshInstallationCount == 1)
        #expect(scene.world == world)
        #expect(try SculptureWorldCodec.encode(scene.world) == original)
        let preparedAgain = try SculptureWorldScene.prepare(world, cachedModels: scene)
        #expect(preparedAgain.preparedMeshes["cube"]?.identity == scene.preparedMeshes["cube"]?.identity)
        #expect(preparedAgain.coarseMeshes["cube"]?.buffers.identity == scene.coarseMeshes["cube"]?.buffers.identity)
    }

    @Test func nativePerspectiveAndOrbitPickBothColoredCoarseAndDetailedInstances() throws {
        let focus = SculptureWorldPoint(x: 0, y: 0, z: 0)
        let world = try fixture(focus: focus, nearX: -4, coarseX: 10, coarseZ: -24)
        let scene = try SculptureWorldScene.prepare(world)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let id = UUID()
        for mode in SculptureWorldNavigationMode.allCases {
            configure(
                controller,
                scene: scene,
                id: id,
                focus: focus,
                camera: .init(yaw: 0, pitch: 0),
                mode: mode,
                explorer: mode == .explore ? SculptureWorldExplorer(anchor: focus) : nil,
                renderDistance: 64,
                detailDistance: 16
            )
            SCNTransaction.flush()
            #expect(controller.fullDetailInstanceCount == 2 && controller.coarseInstanceCount == 1)
            #expect(controller.boundsProxyInstanceCount == 0)
            for (name, child) in [("near", "world.detail"), ("coarse", "world.coarse")] {
                let node = try instance(name, in: view)
                let fill = try #require(node.childNodes.first)
                let geometry = try #require(fill.geometry)
                #expect(fill.name == child && geometry.firstMaterial?.fillMode == .fill)
                #expect(geometry.sources(for: .color).count == 1)
                let projected = view.projectPoint(node.position)
                #expect(projected.x.isFinite && projected.y.isFinite)
                #expect(projected.x >= 0 && projected.x < 640 && projected.y >= 0 && projected.y < 480)
                #expect(controller.hitTest(x: Double(projected.x), y: 480 - Double(projected.y)) == name)
            }
        }
        #expect(controller.meshInstallationCount == 1)
    }

    @Test func realNativeKeyEventsMapHorizontalAndVerticalMovementAndReleaseWithoutClockRaces() throws {
        let mounted = try mountedFixture()
        defer { mounted.window.contentView = nil; mounted.window.close() }
        let controller = mounted.controller
        let view = mounted.view
        #expect(controller.focusCanvas())
        for (code, character, expected) in [
            (UInt16(13), "w", SIMD3<Double>(0, 0, -1)),
            (1, "s", SIMD3<Double>(0, 0, 1)), (0, "a", SIMD3<Double>(-1, 0, 0)),
            (2, "d", SIMD3<Double>(1, 0, 0)), (12, "q", SIMD3<Double>(0, 1, 0)),
            (14, "e", SIMD3<Double>(0, -1, 0)),
        ] {
            controller.updateExplorer(SculptureWorldExplorer(anchor: .init(x: 0, y: 0, z: 0)))
            try key(.keyDown, character: character, code: code, view: view, window: mounted.window)
            #expect(controller.navigationActive)
            controller.stepNavigation(duration: 1 / SculptureWorldExplorer.defaultSpeed)
            #expect(
                try #require(controller.currentExplorer).offset == expected
                    * (1 + SculptureWorldExplorer.defaultSpeed / 30)
            )
            try key(.keyUp, character: character, code: code, view: view, window: mounted.window)
            #expect(!controller.navigationActive)
        }
        controller.updateExplorer(SculptureWorldExplorer(anchor: .init(x: 0, y: 0, z: 0)))
        try key(.keyDown, character: "w", code: 13, modifiers: .shift, view: view, window: mounted.window)
        controller.stepNavigation(duration: 1 / SculptureWorldExplorer.defaultSpeed)
        #expect(
            try #require(controller.currentExplorer).offset
                == SIMD3<Double>(0, 0, -4 * (1 + SculptureWorldExplorer.defaultSpeed / 30))
        )
        try key(.keyUp, character: "w", code: 13, view: view, window: mounted.window)
        try key(.keyDown, character: "w", code: 13, modifiers: .command, view: view, window: mounted.window)
        #expect(!controller.navigationActive)
        try key(.keyDown, character: "w", code: 13, view: view, window: mounted.window)
        try key(.keyDown, character: "\u{1B}", code: 53, view: view, window: mounted.window)
        #expect(!controller.navigationActive && mounted.window.firstResponder !== view)
        #expect(mounted.scene.world == mounted.world)
        #expect(!mounted.window.isVisible && !mounted.window.isKeyWindow)
    }

    @Test func nativeHeldKeysStopOnResponderLossWindowKeyLossCloseModeChangeAndDismantling() throws {
        let mounted = try mountedFixture()
        defer { mounted.window.contentView = nil; mounted.window.close() }
        let controller = mounted.controller
        let view = mounted.view
        func begin() throws {
            #expect(controller.focusCanvas())
            try key(.keyDown, character: "w", code: 13, view: view, window: mounted.window)
            #expect(controller.navigationActive)
        }
        try begin()
        #expect(mounted.window.makeFirstResponder(nil))
        #expect(!controller.navigationActive)
        try begin()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: mounted.window)
        #expect(!controller.navigationActive)
        try begin()
        configure(
            controller,
            scene: mounted.scene,
            id: mounted.id,
            focus: .init(x: 0, y: 0, z: 0),
            mode: .orbit
        )
        #expect(!controller.navigationActive)
        configure(
            controller,
            scene: mounted.scene,
            id: mounted.id,
            focus: .init(x: 0, y: 0, z: 0),
            mode: .explore,
            explorer: SculptureWorldExplorer(anchor: .init(x: 0, y: 0, z: 0))
        )
        try begin()
        view.removeFromSuperview()
        #expect(!controller.navigationActive)
        mounted.window.contentView = view
        try begin()
        mounted.window.close()
        #expect(!controller.navigationActive)
        mounted.window.contentView = view
        try begin()
        SculptureLiveWorldView.dismantleNSView(view, coordinator: ())
        #expect(!controller.navigationActive && view.scene == nil)
    }

    @Test func nativeExploreDragChangesLookAndClickStillSelectsWithoutMutatingSource() throws {
        let mounted = try mountedFixture()
        defer { mounted.window.contentView = nil; mounted.window.close() }
        var selected = ""
        var changed: SculptureWorldExplorer?
        mounted.controller.configure(
            scene: mounted.scene,
            sceneID: mounted.id,
            focus: .init(x: 0, y: 0, z: 0),
            renderDistance: 64,
            detailDistance: 16,
            camera: .init(yaw: 0, pitch: 0),
            mode: .explore,
            explorer: SculptureWorldExplorer(anchor: .init(x: 0, y: 0, z: 0)),
            onExplorerChange: { changed = $0 },
            onSelectInstance: { selected = $0 }
        )
        let original = try SculptureWorldCodec.encode(mounted.world)
        try mouse(.leftMouseDown, at: CGPoint(x: 200, y: 180), mounted: mounted)
        try mouse(.leftMouseDragged, at: CGPoint(x: 240, y: 200), mounted: mounted)
        try mouse(.leftMouseUp, at: CGPoint(x: 240, y: 200), mounted: mounted)
        #expect(selected.isEmpty)
        #expect(abs(try #require(changed).yaw + 0.24) < 0.000001)
        #expect(abs(try #require(changed).pitch - 0.12) < 0.000001)
        mounted.controller.updateExplorer(SculptureWorldExplorer(anchor: .init(x: 0, y: 0, z: 0)))
        SCNTransaction.flush()
        let near = try instance("near", in: mounted.view)
        let projected = mounted.view.projectPoint(near.position)
        let local = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        try mouse(.leftMouseDown, at: local, mounted: mounted)
        try mouse(.leftMouseUp, at: local, mounted: mounted)
        #expect(selected == "near")
        #expect((try SculptureWorldCodec.encode(mounted.scene.world)) == original)
        #expect(mounted.controller.meshInstallationCount == 1)
    }

    private func fixture(
        focus: SculptureWorldPoint,
        nearX: Int64 = 3,
        coarseX: Int64 = 200,
        coarseZ: Int64 = -12
    ) throws -> SculptureWorld {
        let cube = try Sculpture(title: "Shared colored cube", width: 1, height: 1, layers: [[43]])
        let unused = try Sculpture(title: "Unused definition", width: 1, height: 1, layers: [[64]])
        let root = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[67]],
            tileSize: SculptureTileSize(width: 1, height: 1, depth: 1),
            bindings: [SculptureModelBinding(glyph: 67, modelID: "cube")]
        )
        let library = try SculptureComposition(
            title: "Exploration library",
            rootID: "root",
            models: ["root": .tiles(root), "cube": .sculpture(cube), "unused": .sculpture(unused)]
        )
        return try SculptureWorld(
            title: "Immutable exploration fixture",
            library: library,
            instances: [
                SculptureWorldInstance(
                    id: "near",
                    modelID: "cube",
                    origin: .init(x: focus.x + nearX, y: focus.y - 2, z: focus.z - 12)
                ),
                SculptureWorldInstance(
                    id: "adjacent",
                    modelID: "cube",
                    origin: .init(x: focus.x + nearX + 1, y: focus.y - 2, z: focus.z - 12)
                ),
                SculptureWorldInstance(
                    id: "coarse",
                    modelID: "cube",
                    origin: .init(x: focus.x + coarseX, y: focus.y - 2, z: focus.z + coarseZ)
                ),
                SculptureWorldInstance(id: "culled", modelID: "cube", origin: .init(x: Int64.min, y: 0, z: 0)),
            ]
        )
    }

    private func configure(
        _ controller: SculptureLiveWorldController,
        scene: SculptureWorldScene,
        id: UUID,
        focus: SculptureWorldPoint,
        camera: SculptureCamera = .init(),
        mode: SculptureWorldNavigationMode = .orbit,
        explorer: SculptureWorldExplorer? = nil,
        renderDistance: Int = 512,
        detailDistance: Int = 128
    ) {
        controller.configure(
            scene: scene,
            sceneID: id,
            focus: focus,
            renderDistance: renderDistance,
            detailDistance: detailDistance,
            camera: camera,
            mode: mode,
            explorer: explorer
        )
    }

    private func instance(_ id: String, in view: SCNView) throws -> SCNNode {
        try #require(view.scene?.rootNode.childNode(withName: "world.instance.\(id)", recursively: true))
    }

    private func counts(_ controller: SculptureLiveWorldController) -> [Int] {
        [
            controller.totalInstanceCount, controller.visibleInstanceCount, controller.fullDetailInstanceCount,
            controller.coarseInstanceCount, controller.boundsProxyInstanceCount, controller.omittedInstanceCount,
            controller.culledInstanceCount, controller.renderedExteriorFaceCount,
        ]
    }

    private struct Mounted {
        let window: NSWindow; let view: SCNView; let controller: SculptureLiveWorldController
        let world: SculptureWorld; let scene: SculptureWorldScene; let id: UUID
    }

    private func mountedFixture() throws -> Mounted {
        _ = NSApplication.shared
        let focus = SculptureWorldPoint(x: 0, y: 0, z: 0)
        let world = try fixture(focus: focus, nearX: -4, coarseX: 10, coarseZ: -24)
        let scene = try SculptureWorldScene.prepare(world)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.contentView = view
        let id = UUID()
        configure(
            controller,
            scene: scene,
            id: id,
            focus: focus,
            mode: .explore,
            explorer: SculptureWorldExplorer(anchor: focus),
            renderDistance: 64,
            detailDistance: 16
        )
        return Mounted(window: window, view: view, controller: controller, world: world, scene: scene, id: id)
    }

    private func key(
        _ type: NSEvent.EventType,
        character: String,
        code: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        view: SCNView,
        window: NSWindow
    ) throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: code
            )
        )
        if type == .keyDown { view.keyDown(with: event) } else { view.keyUp(with: event) }
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, mounted: Mounted) throws {
        let event = try #require(
            NSEvent.mouseEvent(
                with: type,
                location: mounted.view.convert(point, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: mounted.window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        switch type {
        case .leftMouseDown: mounted.view.mouseDown(with: event)
        case .leftMouseDragged: mounted.view.mouseDragged(with: event)
        case .leftMouseUp: mounted.view.mouseUp(with: event)
        default: Issue.record("Unsupported native mouse event")
        }
    }

    private struct EvidenceDirectory {
        let parent: Int32; let directory: Int32; let stagingName: String; let destinationName: String
        let device: dev_t; let inode: ino_t
    }

    private func evidenceDirectory(_ destination: URL) throws -> EvidenceDirectory {
        let parentURL = destination.deletingLastPathComponent()
        try #require(destination.lastPathComponent != "." && destination.lastPathComponent != "/")
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let parent = open(parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw evidenceError("open parent") }
        var existing = stat()
        guard fstatat(parent, destination.lastPathComponent, &existing, AT_SYMLINK_NOFOLLOW) != 0,
            errno == ENOENT
        else {
            close(parent)
            throw NSError(
                domain: "WorldExplorationEvidence",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Evidence destination already exists or cannot be checked."]
            )
        }
        let stagingName = ".world-exploration-\(UUID()).staging"
        guard mkdirat(parent, stagingName, 0o700) == 0 else {
            let error = evidenceError("create staging"); close(parent); throw error
        }
        let directory = openat(parent, stagingName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else {
            let error = evidenceError("open staging"); close(parent); throw error
        }
        var identity = stat()
        guard fstat(directory, &identity) == 0 else {
            let error = evidenceError("identify staging"); close(directory); close(parent); throw error
        }
        return EvidenceDirectory(
            parent: parent,
            directory: directory,
            stagingName: stagingName,
            destinationName: destination.lastPathComponent,
            device: identity.st_dev,
            inode: identity.st_ino
        )
    }

    private func requireEvidenceDirectory(_ output: EvidenceDirectory) throws {
        var current = stat()
        guard fstatat(output.parent, output.stagingName, &current, AT_SYMLINK_NOFOLLOW) == 0,
            current.st_dev == output.device, current.st_ino == output.inode,
            current.st_mode & S_IFMT == S_IFDIR
        else {
            throw NSError(
                domain: "WorldExplorationEvidence",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Evidence staging directory was replaced."]
            )
        }
    }

    private func writeEvidence(_ data: Data, name: String, output: EvidenceDirectory) throws {
        try requireEvidenceDirectory(output)
        let descriptor = openat(output.directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw evidenceError("create \(name)") }
        defer { close(descriptor) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw evidenceError("write \(name)") }
                offset += count
            }
        }
        try requireEvidenceDirectory(output)
    }

    private func evidenceError(_ operation: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: "Could not \(operation)."]
        )
    }

    private func imagePixels(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes in
            guard
                let context = CGContext(
                    data: bytes.baseAddress,
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
        return pixels
    }

    private struct EvidenceReceipt: Encodable {
        let schema: String; let suppliedSourceRevision: String?; let platform: String; let renderer: String
        let device: String?; let title: String; let frames: [EvidenceFrame]; let notes: [String]
    }

    private struct EvidenceFrame: Encodable {
        let name: String; let mode: String; let focus: SculptureWorldPoint; let explorer: EvidenceExplorer?
        let renderDistance: Int; let detailDistance: Int; let width: Int; let height: Int
        let total: Int; let visible: Int; let detailed: Int; let coarse: Int; let boundsFallback: Int
        let omitted: Int; let culled: Int; let renderedExteriorFaces: Int; let meshInstallations: Int
        let changedPixels: Int; let coloredPixels: Int; let clearBackgroundRGB: [UInt8]; let filename: String
    }

    private struct EvidenceExplorer: Encodable {
        let anchor: SculptureWorldPoint; let offset: [Double]; let yaw: Double; let pitch: Double
        init(_ value: SculptureWorldExplorer) {
            anchor = value.anchor; offset = [value.offset.x, value.offset.y, value.offset.z]
            yaw = value.yaw; pitch = value.pitch
        }
    }
}
