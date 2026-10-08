import AppKit
import RookSculpture
import SceneKit
import SwiftUI
import simd

/// A persistent GPU canvas. Orbit, zoom, opacity and slice selection reuse the installed mesh buffers.
@MainActor
public struct SculptureLiveVoxelView: NSViewRepresentable {
    public let scene: SculptureVoxelScene
    public let sceneID: UUID
    public let camera: SculptureCamera
    public let selectedLayer: Int
    public let opacity: Double
    public let emptyCells: [SculptureCell]
    public let controller: SculptureLiveVoxelController
    private let preparedMesh: SculptureVoxelMeshBuffers?
    private let preparedGhosts: SculptureVoxelGhostBuffers?

    /// `sceneID` must change whenever document geometry changes. Empty cells belong to that scene and selected slice.
    public init(
        scene: SculptureVoxelScene,
        sceneID: UUID,
        camera: SculptureCamera,
        selectedLayer: Int,
        opacity: Double,
        emptyCells: [SculptureCell],
        controller: SculptureLiveVoxelController
    ) {
        self.scene = scene
        self.sceneID = sceneID
        self.camera = camera
        self.selectedLayer = selectedLayer
        self.opacity = opacity
        self.emptyCells = emptyCells
        self.controller = controller
        preparedMesh = nil
        preparedGhosts = nil
    }

    /// Worker-prepared buffers preserve the synchronous initializer while keeping actual canvas packing off the UI actor.
    public init(
        preparedMesh: SculptureVoxelMeshBuffers,
        sceneID: UUID,
        camera: SculptureCamera,
        selectedLayer: Int,
        opacity: Double,
        preparedGhosts: SculptureVoxelGhostBuffers,
        controller: SculptureLiveVoxelController
    ) {
        scene = preparedMesh.scene
        self.sceneID = sceneID
        self.camera = camera
        self.selectedLayer = selectedLayer
        self.opacity = opacity
        emptyCells = preparedGhosts.cells
        self.controller = controller
        self.preparedMesh = preparedMesh
        self.preparedGhosts = preparedGhosts
    }

    public func makeNSView(context: Context) -> SCNView { controller.makeView() }

    public func updateNSView(_ nsView: SCNView, context: Context) {
        controller.configure(
            scene: scene,
            sceneID: sceneID,
            camera: camera,
            selectedLayer: selectedLayer,
            opacity: opacity,
            emptyCells: emptyCells,
            preparedMesh: preparedMesh,
            preparedGhosts: preparedGhosts
        )
    }

    public static func dismantleNSView(_ nsView: SCNView, coordinator: Void) { nsView.scene = nil }
}

/// Readiness and picking for the actual live canvas; this does not control another window or process.
@MainActor
public final class SculptureLiveVoxelController {
    public private(set) var installedSceneID: UUID?
    public private(set) var currentCamera: SculptureCamera?
    /// Counts document mesh installations. Camera and style changes do not increase it.
    public private(set) var meshInstallationCount = 0
    public var viewportSize: CGSize { view?.bounds.size ?? .zero }
    public var renderingAPI: SCNRenderingAPI? { view?.renderingAPI }

    private weak var view: LiveVoxelSCNView?
    private let sceneRoot = SCNScene()
    private let cameraNode = SCNNode()
    private let fillNode = SCNNode()
    private let edgeNode = SCNNode()
    private let selectedNode = SCNNode()
    private let ghostFillNode = SCNNode()
    private let ghostEdgeNode = SCNNode()
    private let fillMaterial = SCNMaterial()
    private let edgeMaterial = SCNMaterial()
    private let selectedMaterial = SCNMaterial()
    private let ghostMaterial = SCNMaterial()
    private let ghostEdgeMaterial = SCNMaterial()
    private var dimensions = SIMD3<Int>(repeating: 1)
    private var surfaces: [SculptureVoxelSurface] = []
    private var selectedOutlineLayer: Int?
    private var selectionLineBuffers: [Int: Data] = [:]
    private var ghostCells: [SculptureCell] = []
    private var ghostKey: GhostKey?

    public init() {
        cameraNode.camera = SCNCamera()
        sceneRoot.rootNode.addChildNode(cameraNode)
        for node in [fillNode, edgeNode, selectedNode, ghostFillNode, ghostEdgeNode] {
            sceneRoot.rootNode.addChildNode(node)
        }
        fillNode.categoryBitMask = 1
        ghostFillNode.categoryBitMask = 2
        fillNode.name = "voxel.surface"
        edgeNode.name = "voxel.edges"
        selectedNode.name = "voxel.selected-edges"
        ghostFillNode.name = "voxel.empty-fill"
        ghostEdgeNode.name = "voxel.empty-edges"
        edgeNode.categoryBitMask = 4
        selectedNode.categoryBitMask = 4
        ghostEdgeNode.categoryBitMask = 4
        edgeNode.renderingOrder = 1
        selectedNode.renderingOrder = 2
        ghostEdgeNode.renderingOrder = 1
        for material in [fillMaterial, edgeMaterial, selectedMaterial, ghostMaterial, ghostEdgeMaterial] {
            material.lightingModel = .constant
            material.diffuse.contents = NSColor.white
            material.readsFromDepthBuffer = true
            material.writesToDepthBuffer = false
            material.blendMode = .alpha
            material.transparencyMode = .aOne
        }
        fillMaterial.isDoubleSided = false
        ghostMaterial.isDoubleSided = true
        selectedMaterial.diffuse.contents = NSColor(calibratedRed: 1, green: 0.79, blue: 0.44, alpha: 1)
        ghostMaterial.diffuse.contents = NSColor(calibratedRed: 1, green: 0.79, blue: 0.44, alpha: 1)
        ghostEdgeMaterial.diffuse.contents = NSColor(calibratedRed: 1, green: 0.79, blue: 0.44, alpha: 1)
        selectedMaterial.transparency = 0.8
        ghostMaterial.transparency = 0.018
        ghostEdgeMaterial.transparency = 0.17
    }

    /// Camera updates are constant work: transform and projection changes only, with no document scan or mesh encoding.
    public func updateCamera(_ camera: SculptureCamera) {
        currentCamera = camera
        applyCamera()
    }

    /// Coordinates are measured from the upper-left of this view in AppKit points, independent of Retina scale.
    public func hitTest(x: Double, y: Double) -> SculptureVoxelHit? {
        guard let view, installedSceneID != nil, currentCamera != nil,
            x.isFinite, y.isFinite, x >= 0, y >= 0,
            x < Double(view.bounds.width), y < Double(view.bounds.height)
        else { return nil }
        let point = CGPoint(x: x, y: view.isFlipped ? y : Double(view.bounds.height) - y)
        let hits = view.hitTest(
            point,
            options: [
                .categoryBitMask: 3,
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .backFaceCulling: false,
                .ignoreHiddenNodes: true,
            ]
        )
        for hit in hits {
            let index = hit.faceIndex / 2
            if hit.node === fillNode, surfaces.indices.contains(index) {
                let surface = surfaces[index]
                return SculptureVoxelHit(
                    cell: surface.cell,
                    face: surface.face,
                    isEmpty: false,
                    adjacentCell: surface.adjacentCell
                )
            }
            if hit.node === ghostFillNode, ghostCells.indices.contains(index) {
                return SculptureVoxelHit(cell: ghostCells[index], face: nil, isEmpty: true, adjacentCell: nil)
            }
        }
        return nil
    }

    internal func makeView() -> SCNView {
        let canvas = LiveVoxelSCNView(
            frame: .zero,
            options: [
                SCNView.Option.preferredRenderingAPI.rawValue: NSNumber(value: SCNRenderingAPI.metal.rawValue)
            ]
        )
        canvas.backgroundColor = NSColor(calibratedRed: 0.065, green: 0.085, blue: 0.10, alpha: 1)
        canvas.scene = sceneRoot
        canvas.pointOfView = cameraNode
        canvas.autoenablesDefaultLighting = false
        canvas.allowsCameraControl = false
        canvas.antialiasingMode = .multisampling4X
        canvas.preferredFramesPerSecond = 60
        canvas.rendersContinuously = false
        canvas.resizeCamera = { [weak self] in self?.applyCamera() }
        view = canvas
        applyCamera()
        return canvas
    }

    internal func configure(
        scene: SculptureVoxelScene,
        sceneID: UUID,
        camera: SculptureCamera,
        selectedLayer: Int,
        opacity: Double,
        emptyCells: [SculptureCell],
        preparedMesh: SculptureVoxelMeshBuffers? = nil,
        preparedGhosts: SculptureVoxelGhostBuffers? = nil
    ) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        if installedSceneID != sceneID {
            guard let mesh = preparedMesh ?? (try? SculptureVoxelMeshBuffers.prepare(scene)) else {
                SCNTransaction.commit()
                return
            }
            install(mesh, sceneID: sceneID)
        }
        fillMaterial.transparency = opacity.isFinite ? max(0, min(1, opacity)) : 0.35
        edgeMaterial.transparency = max(0.16, min(0.8, fillMaterial.transparency * 0.8))
        if let lines = selectionLineBuffers[selectedLayer] {
            // A primitiveRange on the full index stream can leave earlier slices visible in Metal.
            // Use the worker's exact slice indices and share the unchanged document vertices.
            if selectedOutlineLayer != selectedLayer, let geometry = fillNode.geometry {
                let selection = LiveVoxelMesh.element(lines, type: .line, indicesPerPrimitive: 2)
                selectedNode.geometry = LiveVoxelMesh.geometry(
                    geometry.sources(for: .vertex),
                    element: selection,
                    material: selectedMaterial
                )
                selectedOutlineLayer = selectedLayer
            }
            selectedNode.isHidden = false
        } else {
            selectedNode.isHidden = true
        }
        let key = GhostKey(sceneID: sceneID, layer: selectedLayer, count: emptyCells.count)
        if ghostKey != key {
            let supplied = preparedGhosts.flatMap {
                $0.dimensions == dimensions && $0.selectedLayer == selectedLayer ? $0 : nil
            }
            guard
                let ghosts = supplied
                    ?? (try? SculptureVoxelGhostBuffers.prepare(
                        cells: emptyCells,
                        scene: scene,
                        selectedLayer: selectedLayer
                    ))
            else {
                SCNTransaction.commit()
                return
            }
            installGhosts(ghosts)
            ghostKey = key
        }
        currentCamera = camera
        applyCamera()
        SCNTransaction.commit()
        view?.needsDisplay = true
    }

    private func install(_ buffers: SculptureVoxelMeshBuffers, sceneID: UUID) {
        let scene = buffers.scene
        dimensions = SIMD3(scene.width, scene.height, scene.depth)
        surfaces = scene.surfaces
        selectionLineBuffers = buffers.selectionLines
        selectedOutlineLayer = nil
        let vertexSource = LiveVoxelMesh.source(buffers.positions, semantic: .vertex, components: 3)
        let colorSource = LiveVoxelMesh.source(buffers.colors, semantic: .color, components: 4)
        let triangleElement = LiveVoxelMesh.element(buffers.triangles, type: .triangles, indicesPerPrimitive: 3)
        let edgeElement = LiveVoxelMesh.element(buffers.lines, type: .line, indicesPerPrimitive: 2)
        fillNode.geometry = LiveVoxelMesh.geometry(
            [vertexSource, colorSource],
            element: triangleElement,
            material: fillMaterial
        )
        edgeNode.geometry = LiveVoxelMesh.geometry(
            [vertexSource, colorSource],
            element: edgeElement,
            material: edgeMaterial
        )
        selectedNode.geometry = nil
        ghostKey = nil
        installedSceneID = sceneID
        meshInstallationCount += 1
    }

    private func installGhosts(_ buffers: SculptureVoxelGhostBuffers) {
        ghostCells = buffers.cells
        let source = LiveVoxelMesh.source(buffers.positions, semantic: .vertex, components: 3)
        ghostFillNode.geometry = LiveVoxelMesh.geometry(
            [source],
            element: LiveVoxelMesh.element(buffers.triangles, type: .triangles, indicesPerPrimitive: 3),
            material: ghostMaterial
        )
        ghostEdgeNode.geometry = LiveVoxelMesh.geometry(
            [source],
            element: LiveVoxelMesh.element(buffers.lines, type: .line, indicesPerPrimitive: 2),
            material: ghostEdgeMaterial
        )
    }

    private func applyCamera() {
        guard let currentCamera, let view, let camera = cameraNode.camera else { return }
        let transform = LiveVoxelCamera(dimensions: dimensions, camera: currentCamera, size: view.bounds.size)
        // Subpixel ghost lines accumulate into an opaque-looking sheet; retain faint fills and all pick targets.
        ghostEdgeNode.isHidden = ghostCells.isEmpty || transform.projectedGridSpacing < 2.5
        // Dense voxel grid lines are subpixel overdraw; the selected-slice outline and every fill/pick face remain.
        edgeNode.isHidden = transform.projectedGridSpacing < 2
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

    private struct GhostKey: Equatable {
        let sceneID: UUID
        let layer: Int
        let count: Int
    }
}

@MainActor
private final class LiveVoxelSCNView: SCNView {
    var resizeCamera: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeCamera?()
    }
}

/// The inverse camera rotation and custom perspective reproduce `VoxelCamera.project` in view-local points.
internal struct LiveVoxelCamera {
    let cameraToWorld: simd_float4x4
    let projection: simd_float4x4
    let near: Double
    let far: Double
    let projectedGridSpacing: Double

    init(dimensions: SIMD3<Int>, camera: SculptureCamera, size: CGSize) {
        let extent = Double(max(dimensions.x, dimensions.y, dimensions.z))
        let distance = extent * 3
        let yaw = camera.yaw.isFinite ? camera.yaw.truncatingRemainder(dividingBy: 2 * .pi) : 0
        let pitch = camera.pitch.isFinite ? max(-1.4, min(1.4, camera.pitch)) : 0
        let zoom = camera.zoom.isFinite ? max(0.5, min(2, camera.zoom)) : 1
        let width = max(1, Double(size.width)), height = max(1, Double(size.height))
        let scale = min(width, height) * 0.68 / extent * zoom
        let cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch)
        projectedGridSpacing = scale * min(sqrt(cy * cy + sy * sy * sp * sp), abs(cp))
        cameraToWorld = simd_float4x4(
            columns: (
                SIMD4(Float(cy), 0, Float(sy), 0),
                SIMD4(Float(sy * sp), Float(cp), Float(-cy * sp), 0),
                SIMD4(Float(-sy * cp), Float(sp), Float(cy * cp), 0),
                SIMD4(Float(-sy * cp * distance), Float(sp * distance), Float(cy * cp * distance), 1)
            )
        )
        near = max(0.01, extent * 0.01)
        far = distance + extent * 2
        projection = simd_float4x4(
            columns: (
                SIMD4(Float(2 * scale * distance / width), 0, 0, 0),
                SIMD4(0, Float(2 * scale * distance / height), 0, 0),
                SIMD4(0, 0, Float(-(far + near) / (far - near)), -1),
                SIMD4(0, 0, Float(-2 * far * near / (far - near)), 0)
            )
        )
    }
}

@MainActor
private enum LiveVoxelMesh {
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

    static func element(_ indices: Data, type: SCNGeometryPrimitiveType, indicesPerPrimitive: Int)
        -> SCNGeometryElement
    {
        SCNGeometryElement(
            data: indices,
            primitiveType: type,
            primitiveCount: indices.count / MemoryLayout<UInt32>.size / indicesPerPrimitive,
            bytesPerIndex: 4
        )
    }

    static func geometry(_ sources: [SCNGeometrySource], element: SCNGeometryElement, material: SCNMaterial)
        -> SCNGeometry
    {
        let geometry = SCNGeometry(sources: sources, elements: [element])
        geometry.materials = [material]
        return geometry
    }

}
