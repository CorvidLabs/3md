import Foundation
import RookSculpture
import SceneKit
import Testing

@testable import RookRendering

struct SculptureSolarPerformanceTests {
    @Test func actualSolarSystemFitsTheReusableExteriorMeshBudget() throws {
        let sculpture = try #require(SculptureExamples.all.first { $0.id == "grand-solar-system" }).sculpture
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        #expect(scene.width == 256 && scene.height == 256 && scene.depth == 256)
        #expect(scene.occupiedCount == sculpture.occupiedCount)
        #expect(scene.surfaces.count == 75_552)
        #expect(scene.surfaces.count < SculptureVoxelSurfaceExtractor.maximumFaces)
        #expect(Set(scene.surfaces.map(\.glyph)) == Set(Sculpture.palette))
        #expect(Set(scene.surfaces.map(\.face)) == Set(SculptureVoxelFace.allCases))
        #expect(
            scene.surfaces.allSatisfy { surface in
                sculpture.glyph(at: surface.cell) == surface.glyph
                    && (surface.adjacentCell.map { sculpture.glyph(at: $0) == Sculpture.empty } ?? true)
            }
        )
    }

    @Test @MainActor func solarCameraAndLayerChangesRetainActualNativeGeometryBuffers() throws {
        let sculpture = try #require(SculptureExamples.all.first { $0.id == "grand-solar-system" }).sculpture
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        let sceneID = UUID()
        let controller = SculptureLiveVoxelController()
        let view = controller.makeView()
        view.setFrameSize(CGSize(width: 1_120, height: 760))
        controller.configure(
            scene: scene,
            sceneID: sceneID,
            camera: .init(),
            selectedLayer: 128,
            opacity: 0.35,
            emptyCells: []
        )
        let root = try #require(view.scene?.rootNode)
        let cameraNode = try #require(view.pointOfView)
        let firstCameraPosition = cameraNode.simdWorldPosition
        let firstProjection = try #require(cameraNode.camera).projectionTransform
        let fillNode = try #require(root.childNode(withName: "voxel.surface", recursively: false))
        let edgeNode = try #require(root.childNode(withName: "voxel.edges", recursively: false))
        let selectedNode = try #require(root.childNode(withName: "voxel.selected-edges", recursively: false))
        let geometry = try [fillNode, edgeNode].map { try #require($0.geometry) }
        let sources = geometry.map(\.sources)
        let elements = try geometry.map { try #require($0.elements.first) }
        let vertexSource = try #require(geometry[0].sources(for: .vertex).first)
        #expect(vertexSource.vectorCount == scene.surfaces.count * 4)
        #expect(geometry[1].sources(for: .vertex).first === vertexSource)
        #expect(elements[0].primitiveType == .triangles)
        #expect(elements[0].primitiveCount == scene.surfaces.count * 2)
        #expect(elements[1].primitiveType == .line)
        #expect(elements[1].primitiveCount == scene.surfaces.count * 4)
        var previousSelection = try #require(selectedNode.geometry)
        var previousSelectionElement = try #require(previousSelection.elements.first)
        var previousLayer = 128
        let expectedEdges = Dictionary(
            uniqueKeysWithValues: [128, 208].map { layer in
                let edges = scene.surfaces.enumerated().filter { $0.element.cell.z == layer }.flatMap { surface in
                    let first = UInt32(surface.offset * 4)
                    return (0..<4).map { corner in
                        let start = first + UInt32(corner)
                        let end = first + UInt32((corner + 1) % 4)
                        return SIMD2(min(start, end), max(start, end))
                    }
                }
                return (layer, Set(edges))
            }
        )
        try #require(expectedEdges.values.allSatisfy { !$0.isEmpty })
        #expect(expectedEdges[128] != expectedEdges[208])
        #expect(controller.meshInstallationCount == 1)

        for index in 0..<24 {
            let camera = SculptureCamera(
                yaw: Double(index) * .pi / 12,
                pitch: -1.2 + Double(index % 9) * 0.3,
                zoom: 0.6 + Double(index % 8) * 0.18
            )
            let selectedLayer = index.isMultiple(of: 2) ? 128 : 208
            controller.configure(
                scene: scene,
                sceneID: sceneID,
                camera: camera,
                selectedLayer: selectedLayer,
                opacity: index.isMultiple(of: 3) ? 0.75 : 0.35,
                emptyCells: []
            )
            #expect(controller.meshInstallationCount == 1)
            #expect(controller.installedSceneID == sceneID)
            #expect(controller.currentCamera == camera)
            for (offset, node) in [fillNode, edgeNode].enumerated() {
                let current = try #require(node.geometry)
                #expect(current === geometry[offset])
                #expect(current.sources.count == sources[offset].count)
                #expect(zip(current.sources, sources[offset]).allSatisfy { $0 === $1 })
                #expect(current.elements.first === elements[offset])
            }
            let selected = try #require(selectedNode.geometry)
            let selectedElement = try #require(selected.elements.first)
            #expect(selected.sources(for: .vertex).first === vertexSource)
            #expect(selectedElement.primitiveType == .line)
            #expect(!selectedNode.isHidden)
            if selectedLayer == previousLayer {
                #expect(selected === previousSelection)
                #expect(selectedElement === previousSelectionElement)
            } else {
                #expect(selected !== previousSelection)
                #expect(selectedElement !== previousSelectionElement)
                #expect(selectedElement.data != previousSelectionElement.data)
            }
            let indices = try lineIndices(selectedElement)
            var actualEdges: Set<SIMD2<UInt32>> = []
            for offset in stride(from: 0, to: indices.count, by: 2) {
                let start = indices[offset]
                let end = indices[offset + 1]
                actualEdges.insert(SIMD2(min(start, end), max(start, end)))
            }
            let selectedEdges = try #require(expectedEdges[selectedLayer])
            #expect(actualEdges == selectedEdges)
            #expect(selectedElement.primitiveCount == actualEdges.count)

            // Orbit uses this same selected index element until the selected layer changes.
            controller.updateCamera(.init(yaw: camera.yaw + 0.01, pitch: camera.pitch, zoom: camera.zoom))
            #expect(selectedNode.geometry === selected)
            #expect(selectedNode.geometry?.elements.first === selectedElement)
            #expect(controller.meshInstallationCount == 1)
            previousSelection = selected
            previousSelectionElement = selectedElement
            previousLayer = selectedLayer
        }
        #expect(cameraNode.simdWorldPosition != firstCameraPosition)
        #expect(try #require(cameraNode.camera).projectionTransform.m11 != firstProjection.m11)
        #expect(controller.viewportSize == CGSize(width: 1_120, height: 760))
    }

    private func lineIndices(_ element: SCNGeometryElement) throws -> [UInt32] {
        try #require(element.bytesPerIndex == MemoryLayout<UInt32>.size)
        try #require(element.data.count == element.primitiveCount * 2 * element.bytesPerIndex)
        return element.data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: MemoryLayout<UInt32>.size).map {
                bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self)
            }
        }
    }
}
