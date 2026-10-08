import AppKit
import Observation
import RookSculpture
import SceneKit
import SwiftUI
import simd

/// Camera-independent, bounded snapshots for the models actually referenced by a sparse world.
public struct SculptureWorldScene: Sendable {
    public static let maximumPreparedFaces = 1_000_000
    public let world: SculptureWorld
    public var modelCount: Int { models.count }
    internal let models: [String: SculptureVoxelScene]
    internal let preparedMeshes: [String: SculptureVoxelMeshBuffers]
    internal let coarseMeshes: [String: SculptureWorldCoarseMeshResult]

    private init(
        world: SculptureWorld,
        models: [String: SculptureVoxelScene],
        preparedMeshes: [String: SculptureVoxelMeshBuffers],
        coarseMeshes: [String: SculptureWorldCoarseMeshResult]
    ) {
        self.world = world
        self.models = models
        self.preparedMeshes = preparedMeshes
        self.coarseMeshes = coarseMeshes
    }

    /// Call in a detached preparation task. Each referenced definition is resolved and extracted once.
    public static func prepare(_ world: SculptureWorld, cachedModels: Self? = nil) throws -> Self {
        try Task.checkCancellation()
        var models: [String: SculptureVoxelScene] = [:]
        var prepared: [String: SculptureVoxelMeshBuffers] = [:]
        var coarse: [String: SculptureWorldCoarseMeshResult] = [:]
        var faces = 0
        // The immutable library must match exactly. Placement edits can reuse bytes; changed definitions cannot.
        let reusable = cachedModels?.world.library == world.library ? cachedModels?.preparedMeshes : nil
        let reusableCoarse = cachedModels?.world.library == world.library ? cachedModels?.coarseMeshes : nil
        let referencedIDs = Set(world.instances.map(\.modelID)).sorted()
        for id in referencedIDs {
            try Task.checkCancellation()
            let cached = reusable?[id]
            let scene: SculptureVoxelScene
            if let cached {
                scene = cached.scene
            } else {
                let sculpture = try world.library.expanded(modelID: id)
                scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
            }
            guard scene.surfaces.count <= maximumPreparedFaces - faces else {
                throw SculptureWorldRenderingError.excessivePreparedFaces
            }
            faces += scene.surfaces.count
            models[id] = scene
            prepared[id] = try cached ?? SculptureVoxelMeshBuffers.prepare(scene)
        }
        // Detailed models retain their original acceptance budget. Coarse detail uses only what remains.
        for id in referencedIDs {
            try Task.checkCancellation()
            guard faces < maximumPreparedFaces else { break }
            let mesh: SculptureWorldCoarseMeshResult
            if let cached = reusableCoarse?[id] {
                mesh = cached
            } else {
                mesh = try SculptureWorldCoarseMesh.prepare(world.library.expanded(modelID: id))
            }
            guard mesh.faceCount <= maximumPreparedFaces - faces else { continue }
            faces += mesh.faceCount
            coarse[id] = mesh
        }
        try Task.checkCancellation()
        return Self(world: world, models: models, preparedMeshes: prepared, coarseMeshes: coarse)
    }
}

public enum SculptureWorldRenderingError: Error, LocalizedError, Sendable {
    case excessivePreparedFaces

    public var errorDescription: String? {
        "The referenced world models exceed the prepared cache budget of 1,000,000 exterior faces. Simplify the model library."
    }
}

/// Sparse Metal rendering. Model buffers are shared; changing focus changes only bounded instance nodes.
@MainActor
public struct SculptureLiveWorldView: NSViewRepresentable {
    public let scene: SculptureWorldScene
    public let sceneID: UUID
    public let focus: SculptureWorldPoint
    public let renderDistance: Int
    public let detailDistance: Int
    public let camera: SculptureCamera
    public let mode: SculptureWorldNavigationMode
    public let explorer: SculptureWorldExplorer?
    public let controller: SculptureLiveWorldController
    public let onCameraChange: @MainActor (SculptureCamera) -> Void
    public let onSelectInstance: @MainActor (String) -> Void
    public let onExplorerChange: @MainActor (SculptureWorldExplorer) -> Void

    /// Change `sceneID` only when the world or its model definitions change, not for focus or camera changes.
    public init(
        scene: SculptureWorldScene,
        sceneID: UUID,
        focus: SculptureWorldPoint,
        renderDistance: Int,
        detailDistance: Int,
        camera: SculptureCamera,
        controller: SculptureLiveWorldController,
        mode: SculptureWorldNavigationMode = .orbit,
        explorer: SculptureWorldExplorer? = nil,
        onCameraChange: @escaping @MainActor (SculptureCamera) -> Void = { _ in },
        onExplorerChange: @escaping @MainActor (SculptureWorldExplorer) -> Void = { _ in },
        onSelectInstance: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.scene = scene
        self.sceneID = sceneID
        self.focus = focus
        self.renderDistance = renderDistance
        self.detailDistance = detailDistance
        self.camera = camera
        self.controller = controller
        self.mode = mode
        self.explorer = explorer
        self.onCameraChange = onCameraChange
        self.onSelectInstance = onSelectInstance
        self.onExplorerChange = onExplorerChange
    }

    public func makeNSView(context: Context) -> SCNView { controller.makeView() }

    public func updateNSView(_ nsView: SCNView, context: Context) {
        controller.configure(
            scene: scene,
            sceneID: sceneID,
            focus: focus,
            renderDistance: renderDistance,
            detailDistance: detailDistance,
            camera: camera,
            mode: mode,
            explorer: explorer,
            onCameraChange: onCameraChange,
            onExplorerChange: onExplorerChange,
            onSelectInstance: onSelectInstance
        )
    }

    public static func dismantleNSView(_ nsView: SCNView, coordinator: Void) {
        (nsView as? LiveWorldSCNView)?.stopNavigation()
        nsView.scene = nil
    }
}

/// Counts distinguish distance culling, active instances, and capacity omissions; none implies a flattened world.
@MainActor
@Observable
public final class SculptureLiveWorldController {
    public static let maximumVisibleInstances = 512
    public static let maximumFullDetailFaces = 500_000
    public private(set) var installedSceneID: UUID?
    public private(set) var currentCamera: SculptureCamera?
    public private(set) var currentMode: SculptureWorldNavigationMode = .orbit
    public private(set) var currentExplorer: SculptureWorldExplorer?
    public private(set) var totalInstanceCount = 0
    public private(set) var visibleInstanceCount = 0
    public private(set) var fullDetailInstanceCount = 0
    public private(set) var proxyInstanceCount = 0
    public private(set) var coarseInstanceCount = 0
    public private(set) var boundsProxyInstanceCount = 0
    /// In-range placements omitted by the 512-instance cap; distance culling is reported separately.
    public private(set) var omittedInstanceCount = 0
    public private(set) var culledInstanceCount = 0
    public private(set) var detailBudgetProxyInstanceCount = 0
    public private(set) var renderedExteriorFaceCount = 0
    /// Counts new unique model meshes. Placement, rotation, focus and orbit retain matching prepared buffers.
    public private(set) var meshInstallationCount = 0
    public var viewportSize: CGSize { view?.bounds.size ?? .zero }
    public var renderingAPI: SCNRenderingAPI? { view?.renderingAPI }
    internal var navigationActive: Bool { view?.navigationActive ?? false }

    @ObservationIgnored private weak var view: LiveWorldSCNView?
    @ObservationIgnored private let sceneRoot = SCNScene()
    @ObservationIgnored private let cameraNode = SCNNode()
    @ObservationIgnored private let instanceRoot = SCNNode()
    @ObservationIgnored private var installedScene: SculptureWorldScene?
    @ObservationIgnored private var meshes: [String: WorldMesh] = [:]
    @ObservationIgnored private var edgeNodes: [SCNNode] = []
    @ObservationIgnored private var gridVisible: Bool?
    @ObservationIgnored private var visibilityKey: VisibilityKey?
    @ObservationIgnored private var visibleIDs: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var cameraExtent = 1
    @ObservationIgnored private var cameraChanged: @MainActor (SculptureCamera) -> Void = { _ in }
    @ObservationIgnored private var instanceSelected: @MainActor (String) -> Void = { _ in }
    @ObservationIgnored private var explorerChanged: @MainActor (SculptureWorldExplorer) -> Void = { _ in }

    public init() {
        cameraNode.camera = SCNCamera()
        sceneRoot.rootNode.addChildNode(cameraNode)
        instanceRoot.name = "world.instances"
        sceneRoot.rootNode.addChildNode(instanceRoot)
    }

    /// Constant camera work: no model resolution, surface extraction, visibility scan, or buffer encoding.
    public func updateCamera(_ camera: SculptureCamera) {
        currentCamera = camera
        applyCamera()
    }

    /// Rebase visibility only when the exact anchor changes. Local eye and look updates reuse every node and mesh.
    public func updateExplorer(_ explorer: SculptureWorldExplorer) {
        currentExplorer = explorer
        if currentMode == .explore, let key = visibilityKey, key.focus != explorer.anchor {
            installInstances(
                focus: explorer.anchor,
                renderDistance: key.renderDistance,
                detailDistance: key.detailDistance
            )
            visibilityKey = VisibilityKey(
                sceneID: key.sceneID,
                focus: explorer.anchor,
                renderDistance: key.renderDistance,
                detailDistance: key.detailDistance
            )
        }
        applyCamera()
    }

    @discardableResult
    public func focusCanvas() -> Bool {
        guard let view, let window = view.window else { return false }
        return window.makeFirstResponder(view)
    }

    public func stopNavigation() { view?.stopNavigation() }

    internal func stepNavigation(duration: Double) { view?.stepNavigation(duration: duration) }

    /// Native view-local points measured from the upper-left. Both detailed models and outline proxies are selectable.
    public func hitTest(x: Double, y: Double) -> String? {
        guard let view, installedSceneID != nil, currentCamera != nil,
            x.isFinite, y.isFinite, x >= 0, y >= 0,
            x < Double(view.bounds.width), y < Double(view.bounds.height)
        else { return nil }
        let point = CGPoint(x: x, y: view.isFlipped ? y : Double(view.bounds.height) - y)
        let hits = view.hitTest(
            point,
            options: [
                .categoryBitMask: 1, .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .backFaceCulling: false, .ignoreHiddenNodes: true,
            ]
        )
        for hit in hits {
            if let id = visibleIDs[ObjectIdentifier(hit.node)] { return id }
        }
        return nil
    }

    internal func makeView() -> SCNView {
        let canvas = LiveWorldSCNView(
            frame: .zero,
            options: [SCNView.Option.preferredRenderingAPI.rawValue: NSNumber(value: SCNRenderingAPI.metal.rawValue)]
        )
        canvas.scene = sceneRoot
        canvas.pointOfView = cameraNode
        canvas.backgroundColor = NSColor(calibratedRed: 0.065, green: 0.085, blue: 0.10, alpha: 1)
        canvas.allowsCameraControl = false
        canvas.autoenablesDefaultLighting = false
        canvas.antialiasingMode = .multisampling4X
        canvas.preferredFramesPerSecond = 60
        canvas.rendersContinuously = false
        canvas.resizeCamera = { [weak self] in self?.applyCamera() }
        canvas.cameraValue = { [weak self] in self?.currentCamera }
        canvas.changeCamera = { [weak self] camera in
            self?.updateCamera(camera)
            self?.cameraChanged(camera)
        }
        canvas.navigationMode = { [weak self] in self?.currentMode ?? .orbit }
        canvas.explorerValue = { [weak self] in self?.currentExplorer }
        canvas.changeExplorer = { [weak self] explorer in
            self?.updateExplorer(explorer)
            self?.explorerChanged(explorer)
        }
        canvas.selectPoint = { [weak self] point in
            guard let self, let id = self.hitTest(x: Double(point.x), y: Double(point.y)) else { return }
            self.instanceSelected(id)
        }
        view = canvas
        applyCamera()
        return canvas
    }

    internal func configure(
        scene: SculptureWorldScene,
        sceneID: UUID,
        focus: SculptureWorldPoint,
        renderDistance: Int,
        detailDistance: Int,
        camera: SculptureCamera,
        mode: SculptureWorldNavigationMode = .orbit,
        explorer: SculptureWorldExplorer? = nil,
        onCameraChange: @escaping @MainActor (SculptureCamera) -> Void = { _ in },
        onExplorerChange: @escaping @MainActor (SculptureWorldExplorer) -> Void = { _ in },
        onSelectInstance: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        cameraChanged = onCameraChange
        instanceSelected = onSelectInstance
        explorerChanged = onExplorerChange
        if currentMode != mode { stopNavigation() }
        currentMode = mode
        currentExplorer = explorer ?? (mode == .explore ? SculptureWorldExplorer(anchor: focus) : nil)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        if installedSceneID != sceneID {
            installedScene = scene
            installedSceneID = sceneID
            totalInstanceCount = scene.world.instances.count
            var next: [String: WorldMesh] = [:]
            for (id, buffers) in scene.preparedMeshes {
                let coarse = scene.coarseMeshes[id]
                if let prior = meshes[id], prior.bufferIdentity == buffers.identity,
                    prior.coarseIdentity == coarse?.buffers.identity
                {
                    next[id] = prior
                } else {
                    next[id] = WorldMesh(buffers, coarse: coarse)
                    meshInstallationCount += 1
                }
            }
            meshes = next
            visibilityKey = nil
        }
        let distance = max(1, min(1_048_576, renderDistance))
        let detail = max(0, min(distance, detailDistance))
        let renderingFocus = mode == .explore ? currentExplorer?.anchor ?? focus : focus
        let key = VisibilityKey(
            sceneID: sceneID,
            focus: renderingFocus,
            renderDistance: distance,
            detailDistance: detail
        )
        if visibilityKey != key {
            installInstances(focus: renderingFocus, renderDistance: distance, detailDistance: detail)
            visibilityKey = key
        }
        currentCamera = camera
        applyCamera()
        SCNTransaction.commit()
    }

    private func installInstances(focus: SculptureWorldPoint, renderDistance: Int, detailDistance: Int) {
        guard let installedScene else { return }
        instanceRoot.childNodes.forEach { $0.removeFromParentNode() }
        edgeNodes.removeAll(keepingCapacity: true)
        gridVisible = nil
        visibleIDs.removeAll(keepingCapacity: true)
        fullDetailInstanceCount = 0
        proxyInstanceCount = 0
        coarseInstanceCount = 0
        boundsProxyInstanceCount = 0
        detailBudgetProxyInstanceCount = 0
        renderedExteriorFaceCount = 0
        let candidates = installedScene.world.instances.compactMap { instance -> WorldCandidate? in
            guard let model = installedScene.models[instance.modelID] else { return nil }
            return WorldCandidate(instance: instance, model: model, focus: focus, renderDistance: renderDistance)
        }.sorted { lhs, rhs in
            lhs.distanceSquared == rhs.distanceSquared
                ? lhs.instance.id < rhs.instance.id : lhs.distanceSquared < rhs.distanceSquared
        }
        culledInstanceCount = totalInstanceCount - candidates.count
        visibleInstanceCount = min(Self.maximumVisibleInstances, candidates.count)
        omittedInstanceCount = candidates.count - visibleInstanceCount
        var renderedFaces = 0
        var largestModel = 1
        let visibleCandidates = Array(candidates.prefix(Self.maximumVisibleInstances))
        let coarseCosts = visibleCandidates.map { candidate in
            let coarse = meshes[candidate.instance.modelID]?.coarseFaceCount ?? 0
            return coarse > 0 ? coarse : 6
        }
        let coarseTotal = coarseCosts.reduce(0, +)
        let reserveCoarse = coarseTotal <= Self.maximumFullDetailFaces
        var remainingFaces = reserveCoarse ? coarseTotal : 6 * visibleInstanceCount
        for (index, candidate) in visibleCandidates.enumerated() {
            guard let mesh = meshes[candidate.instance.modelID] else { continue }
            remainingFaces -= reserveCoarse ? coarseCosts[index] : 6
            let near = candidate.distanceSquared <= Double(detailDistance) * Double(detailDistance)
            let faces = mesh.faceCount
            let availableFaces = Self.maximumFullDetailFaces - renderedFaces - remainingFaces
            let full =
                near && faces > 0
                && faces <= availableFaces
            let coarse = !full && mesh.coarseFaceCount > 0 && mesh.coarseFaceCount <= availableFaces
            let node = SCNNode()
            node.name = "world.instance.\(candidate.instance.id)"
            node.simdPosition = candidate.center
            node.simdEulerAngles.z = -Float(candidate.instance.quarterTurns) * .pi / 2
            let fill = SCNNode(geometry: full ? mesh.fill : coarse ? mesh.coarse : mesh.proxy)
            fill.name = full ? "world.detail" : coarse ? "world.coarse" : "world.proxy"
            if coarse { fill.simdScale = mesh.coarseScale }
            fill.categoryBitMask = 1
            node.addChildNode(fill)
            visibleIDs[ObjectIdentifier(fill)] = candidate.instance.id
            if full {
                let edges = SCNNode(geometry: mesh.edges)
                edges.categoryBitMask = 2
                edges.renderingOrder = 1
                node.addChildNode(edges)
                edgeNodes.append(edges)
                fullDetailInstanceCount += 1
                renderedFaces += faces
            } else {
                proxyInstanceCount += 1
                if coarse {
                    coarseInstanceCount += 1
                    renderedFaces += mesh.coarseFaceCount
                } else {
                    boundsProxyInstanceCount += 1
                    renderedFaces += 6
                }
                if near && faces > 0 { detailBudgetProxyInstanceCount += 1 }
            }
            largestModel = max(
                largestModel,
                max(candidate.dimensions.x, candidate.dimensions.y, candidate.dimensions.z)
            )
            instanceRoot.addChildNode(node)
        }
        renderedExteriorFaceCount = renderedFaces
        cameraExtent = max(renderDistance * 2, largestModel)
    }

    private func applyCamera() {
        guard let view, let currentCamera, let camera = cameraNode.camera else { return }
        if currentMode == .explore, let explorer = currentExplorer {
            for node in edgeNodes { node.isHidden = true }
            gridVisible = false
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            SCNTransaction.disableActions = true
            camera.usesOrthographicProjection = false
            camera.fieldOfView = 65
            camera.zNear = 0.2
            camera.zFar = Double(max(256, cameraExtent * 2))
            let near = camera.zNear
            let far = camera.zFar
            let aspect = max(1, Double(view.bounds.width)) / max(1, Double(view.bounds.height))
            let scale = 1 / tan(65 * Double.pi / 360)
            camera.projectionTransform = SCNMatrix4(
                simd_float4x4(
                    columns: (
                        SIMD4(Float(scale / aspect), 0, 0, 0),
                        SIMD4(0, Float(scale), 0, 0),
                        SIMD4(0, 0, Float(-(far + near) / (far - near)), -1),
                        SIMD4(0, 0, Float(-2 * far * near / (far - near)), 0)
                    )
                )
            )
            cameraNode.simdPosition = SIMD3(
                Float(explorer.offset.x),
                -Float(explorer.offset.y),
                Float(explorer.offset.z)
            )
            cameraNode.simdOrientation =
                simd_quatf(angle: Float(explorer.yaw), axis: SIMD3(0, 1, 0))
                * simd_quatf(angle: Float(explorer.pitch), axis: SIMD3(1, 0, 0))
            SCNTransaction.commit()
            view.needsDisplay = true
            return
        }
        let transform = LiveVoxelCamera(
            dimensions: SIMD3(repeating: cameraExtent),
            camera: currentCamera,
            size: view.bounds.size
        )
        let visible = transform.projectedGridSpacing >= 2
        if gridVisible != visible {
            for node in edgeNodes { node.isHidden = !visible }
            gridVisible = visible
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        cameraNode.simdTransform = transform.cameraToWorld
        camera.zNear = transform.near
        camera.zFar = transform.far
        camera.projectionTransform = SCNMatrix4(transform.projection)
        SCNTransaction.commit()
        view.needsDisplay = true
    }

    private struct VisibilityKey: Equatable {
        let sceneID: UUID
        let focus: SculptureWorldPoint
        let renderDistance: Int
        let detailDistance: Int
    }
}

/// Subtraction happens in integer space before converting the bounded, local result to GPU coordinates.
private struct WorldCandidate {
    let instance: SculptureWorldInstance
    let dimensions: SIMD3<Int>
    let center: SIMD3<Float>
    let distanceSquared: Double

    init?(instance: SculptureWorldInstance, model: SculptureVoxelScene, focus: SculptureWorldPoint, renderDistance: Int)
    {
        let x = instance.origin.x.subtractingReportingOverflow(focus.x)
        let y = instance.origin.y.subtractingReportingOverflow(focus.y)
        let z = instance.origin.z.subtractingReportingOverflow(focus.z)
        guard !x.overflow, !y.overflow, !z.overflow else { return nil }
        let odd = !instance.quarterTurns.isMultiple(of: 2)
        let dimensions = SIMD3(odd ? model.height : model.width, odd ? model.width : model.height, model.depth)
        let relative = [x.partialValue, y.partialValue, z.partialValue]
        let lengths = [dimensions.x, dimensions.y, dimensions.z]
        let radius = Int64(renderDistance)
        var distanceSquared = 0.0
        for axis in 0..<3 {
            let coordinate = relative[axis]
            let length = Int64(lengths[axis])
            guard coordinate >= -radius - length, coordinate <= radius + 1 else { return nil }
            let minimum = Double(coordinate) - 0.5
            let maximum = Double(coordinate) + Double(length) - 0.5
            let distance = minimum > 0 ? minimum : maximum < 0 ? -maximum : 0
            distanceSquared += distance * distance
        }
        guard distanceSquared <= Double(renderDistance) * Double(renderDistance) else { return nil }
        self.instance = instance
        self.dimensions = dimensions
        self.distanceSquared = distanceSquared
        center = SIMD3(
            Float(relative[0]) + Float(dimensions.x - 1) / 2,
            -Float(relative[1]) - Float(dimensions.y - 1) / 2,
            Float(relative[2]) + Float(dimensions.z - 1) / 2
        )
    }
}

@MainActor
private final class LiveWorldSCNView: SCNView {
    var resizeCamera: (() -> Void)?
    var cameraValue: (() -> SculptureCamera?)?
    var changeCamera: ((SculptureCamera) -> Void)?
    var selectPoint: ((CGPoint) -> Void)?
    var navigationMode: (() -> SculptureWorldNavigationMode)?
    var explorerValue: (() -> SculptureWorldExplorer?)?
    var changeExplorer: ((SculptureWorldExplorer) -> Void)?
    private var dragStart: CGPoint?
    private var dragCamera: SculptureCamera?
    private var dragged = false
    private var dragExplorer: SculptureWorldExplorer?
    private var heldKeys: Set<UInt16> = []
    private var fastMovement = false
    private var movementTask: Task<Void, Never>?
    private var movementGeneration = UUID()
    private var windowObservers: [NSObjectProtocol] = []
    var navigationActive: Bool { movementTask != nil }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        stopNavigation()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        stopNavigation()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            windowObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: newWindow, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.stopNavigation() }
                }
            )
        }
    }

    func stopNavigation() {
        movementTask?.cancel()
        movementTask = nil
        movementGeneration = UUID()
        heldKeys.removeAll(keepingCapacity: true)
        fastMovement = false
    }

    override func keyDown(with event: NSEvent) {
        guard navigationMode?() == .explore else { super.keyDown(with: event); return }
        if event.keyCode == 53 {
            stopNavigation()
            window?.makeFirstResponder(nil)
            return
        }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
            Self.movementKeys.contains(event.keyCode), window?.firstResponder === self
        else { super.keyDown(with: event); return }
        let inserted = heldKeys.insert(event.keyCode).inserted
        fastMovement = event.modifierFlags.contains(.shift)
        if inserted && !event.isARepeat { stepNavigation(duration: 1.0 / 30) }
        startNavigation()
    }

    override func keyUp(with event: NSEvent) {
        guard heldKeys.remove(event.keyCode) != nil else { super.keyUp(with: event); return }
        if heldKeys.isEmpty { stopNavigation() }
    }

    override func flagsChanged(with event: NSEvent) {
        fastMovement = event.modifierFlags.contains(.shift)
        super.flagsChanged(with: event)
    }

    private static let movementKeys: Set<UInt16> = [0, 1, 2, 12, 13, 14, 123, 124, 125, 126]

    private func startNavigation() {
        guard movementTask == nil, !heldKeys.isEmpty else { return }
        let generation = UUID()
        movementGeneration = generation
        movementTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { break }
                guard let self, self.navigationMode?() == .explore,
                    self.window?.firstResponder === self, !self.heldKeys.isEmpty
                else { break }
                let now = clock.now
                let components = previous.duration(to: now).components
                let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
                previous = now
                self.stepNavigation(duration: min(0.1, max(0, seconds)))
            }
            if let self, self.movementGeneration == generation { self.stopNavigation() }
        }
    }

    func stepNavigation(duration: Double) {
        guard navigationMode?() == .explore, !heldKeys.isEmpty, var explorer = explorerValue?() else { return }
        let forward = axis(positive: [13, 126], negative: [1, 125])
        let right = axis(positive: [2, 124], negative: [0, 123])
        let vertical = axis(positive: [14], negative: [12])
        do {
            try explorer.move(
                forward: forward,
                right: right,
                vertical: vertical,
                speed: SculptureWorldExplorer.defaultSpeed * (fastMovement ? 4 : 1),
                duration: duration
            )
            changeExplorer?(explorer)
        } catch { stopNavigation() }
    }

    private func axis(positive: Set<UInt16>, negative: Set<UInt16>) -> Double {
        Double(heldKeys.isDisjoint(with: positive) ? 0 : 1)
            - Double(heldKeys.isDisjoint(with: negative) ? 0 : 1)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeCamera?()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = convert(event.locationInWindow, from: nil)
        dragCamera = cameraValue?()
        dragExplorer = explorerValue?()
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        let x = Double(point.x - start.x), y = Double(point.y - start.y)
        guard abs(x) + abs(y) > 3 else { return }
        dragged = true
        if navigationMode?() == .explore, var explorer = explorerValue?(), let initial = dragExplorer {
            explorer.look(
                horizontal: initial.yaw - explorer.yaw - x * 0.006,
                vertical: initial.pitch - explorer.pitch + y * 0.006
            )
            changeExplorer?(explorer)
            return
        }
        guard let camera = dragCamera else { return }
        changeCamera?(
            SculptureCamera(
                yaw: camera.yaw + x * 0.008,
                pitch: max(-1.4, min(1.4, camera.pitch + y * 0.008)),
                zoom: camera.zoom
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged, dragStart != nil {
            let point = convert(event.locationInWindow, from: nil)
            selectPoint?(CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y))
        }
        dragStart = nil
        dragCamera = nil
        dragExplorer = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard navigationMode?() != .explore else { return }
        guard let camera = cameraValue?() else { return }
        let scale = event.hasPreciseScrollingDeltas ? 0.02 : 0.12
        let zoom = max(0.5, min(2, camera.zoom * exp(Double(event.scrollingDeltaY) * scale)))
        changeCamera?(SculptureCamera(yaw: camera.yaw, pitch: camera.pitch, zoom: zoom))
    }
}

@MainActor
private struct WorldMesh {
    let fill: SCNGeometry
    let edges: SCNGeometry
    let proxy: SCNGeometry
    let coarse: SCNGeometry
    let coarseScale: SIMD3<Float>
    let coarseFaceCount: Int
    let coarseIdentity: UUID?
    let faceCount: Int
    let bufferIdentity: UUID

    init(_ buffers: SculptureVoxelMeshBuffers, coarse: SculptureWorldCoarseMeshResult?) {
        let scene = buffers.scene
        faceCount = scene.surfaces.count
        bufferIdentity = buffers.identity
        coarseIdentity = coarse?.buffers.identity
        coarseScale = coarse?.scale ?? SIMD3(repeating: 1)
        coarseFaceCount = coarse?.faceCount ?? 0
        let source = WorldMeshData.source(buffers.positions, semantic: .vertex, components: 3)
        let colorSource = WorldMeshData.source(buffers.colors, semantic: .color, components: 4)
        fill = SCNGeometry(
            sources: [source, colorSource],
            elements: [WorldMeshData.element(buffers.triangles, type: .triangles, divisor: 3)]
        )
        edges = SCNGeometry(
            sources: [source, colorSource],
            elements: [WorldMeshData.element(buffers.lines, type: .line, divisor: 2)]
        )
        fill.materials = [WorldMeshData.material(color: .white, transparency: 1)]
        if let coarse {
            self.coarse = SCNGeometry(
                sources: [
                    WorldMeshData.source(coarse.buffers.positions, semantic: .vertex, components: 3),
                    WorldMeshData.source(coarse.buffers.colors, semantic: .color, components: 4),
                ],
                elements: [WorldMeshData.element(coarse.buffers.triangles, type: .triangles, divisor: 3)]
            )
        } else {
            self.coarse = SCNGeometry(sources: [], elements: [])
        }
        self.coarse.materials = [WorldMeshData.material(color: .white, transparency: 1)]
        edges.materials = [WorldMeshData.material(color: .white, transparency: 0.38)]
        proxy = SCNBox(
            width: CGFloat(scene.width),
            height: CGFloat(scene.height),
            length: CGFloat(scene.depth),
            chamferRadius: 0
        )
        let outline = WorldMeshData.material(
            color: NSColor(calibratedRed: 0.62, green: 0.86, blue: 0.78, alpha: 1),
            transparency: 0.55
        )
        outline.fillMode = .lines
        proxy.materials = [outline]
    }
}

@MainActor
private enum WorldMeshData {
    static func source(_ values: Data, semantic: SCNGeometrySource.Semantic, components: Int) -> SCNGeometrySource {
        SCNGeometrySource(
            data: values,
            semantic: semantic,
            vectorCount: values.count / MemoryLayout<Float>.size / components,
            usesFloatComponents: true,
            componentsPerVector: components,
            bytesPerComponent: 4,
            dataOffset: 0,
            dataStride: components * 4
        )
    }

    static func element(_ values: Data, type: SCNGeometryPrimitiveType, divisor: Int) -> SCNGeometryElement {
        SCNGeometryElement(
            data: values,
            primitiveType: type,
            primitiveCount: values.count / MemoryLayout<UInt32>.size / divisor,
            bytesPerIndex: 4
        )
    }

    static func material(color: NSColor, transparency: Double) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.transparency = transparency
        material.transparencyMode = .aOne
        material.blendMode = transparency == 1 ? .replace : .alpha
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = transparency == 1
        return material
    }

}
