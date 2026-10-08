import Foundation
import RookSculpture

/// Immutable, camera-independent native mesh bytes. Prepare these on a worker before installing the SceneKit view.
public struct SculptureVoxelMeshBuffers: Sendable {
    public let scene: SculptureVoxelScene
    public var byteCount: Int {
        positions.count + colors.count + triangles.count + lines.count
            + selectionLines.values.reduce(0) { $0 + $1.count }
    }

    internal let identity: UUID
    internal let positions: Data
    internal let colors: Data
    internal let triangles: Data
    internal let lines: Data
    internal let layerRanges: [Int: NSRange]
    internal let selectionLines: [Int: Data]

    /// Preserves surface order, four vertices, two triangles and four grid edges for every exterior face.
    /// Cancellation throws without publishing partial bytes or picking metadata.
    public static func prepare(_ scene: SculptureVoxelScene) throws -> Self {
        try Task.checkCancellation()
        let count = scene.surfaces.count
        guard count <= SculptureVoxelSurfaceExtractor.maximumFaces else {
            throw SculptureVoxelSurfaceError.tooManyFaces
        }
        var positions = Data(count: count * 12 * MemoryLayout<Float>.size)
        var colors = Data(count: count * 16 * MemoryLayout<Float>.size)
        var triangles = Data(count: count * 6 * MemoryLayout<UInt32>.size)
        var lines = Data(count: count * 8 * MemoryLayout<UInt32>.size)
        var ranges: [Int: NSRange] = [:]
        let center = SIMD3<Float>(
            Float(scene.width - 1) / 2,
            Float(scene.height - 1) / 2,
            Float(scene.depth - 1) / 2
        )
        try positions.withUnsafeMutableBytes { positionBytes in
            try colors.withUnsafeMutableBytes { colorBytes in
                try triangles.withUnsafeMutableBytes { triangleBytes in
                    try lines.withUnsafeMutableBytes { lineBytes in
                        let positionValues = positionBytes.bindMemory(to: Float.self)
                        let colorValues = colorBytes.bindMemory(to: Float.self)
                        let triangleValues = triangleBytes.bindMemory(to: UInt32.self)
                        let lineValues = lineBytes.bindMemory(to: UInt32.self)
                        for (index, surface) in scene.surfaces.enumerated() {
                            if index.isMultiple(of: 256) { try Task.checkCancellation() }
                            let face = MeshBufferPacking.index(surface.face)
                            let color = MeshBufferPacking.colors[Int(surface.glyph) * 6 + face]
                            let origin = SIMD3<Float>(
                                Float(surface.cell.x),
                                Float(surface.cell.y),
                                Float(surface.cell.z)
                            )
                            for corner in 0..<4 {
                                let point = origin + MeshBufferPacking.corners[face][corner]
                                let vertex = index * 12 + corner * 3
                                positionValues[vertex] = point.x - center.x
                                positionValues[vertex + 1] = center.y - point.y
                                positionValues[vertex + 2] = point.z - center.z
                                let tint = index * 16 + corner * 4
                                colorValues[tint] = color.x
                                colorValues[tint + 1] = color.y
                                colorValues[tint + 2] = color.z
                                colorValues[tint + 3] = 1
                            }
                            MeshBufferPacking.indices(index, triangles: triangleValues, lines: lineValues)
                            if let range = ranges[surface.cell.z] {
                                ranges[surface.cell.z] = NSRange(location: range.location, length: range.length + 4)
                            } else {
                                ranges[surface.cell.z] = NSRange(location: index * 4, length: 4)
                            }
                        }
                    }
                }
            }
        }
        var selectionLines: [Int: Data] = [:]
        for (layer, range) in ranges {
            try Task.checkCancellation()
            let firstByte = range.location * 2 * MemoryLayout<UInt32>.size
            let byteCount = range.length * 2 * MemoryLayout<UInt32>.size
            selectionLines[layer] = lines.subdata(in: firstByte..<(firstByte + byteCount))
        }
        try Task.checkCancellation()
        return Self(
            scene: scene,
            identity: UUID(),
            positions: positions,
            colors: colors,
            triangles: triangles,
            lines: lines,
            layerRanges: ranges,
            selectionLines: selectionLines
        )
    }
}

/// Packed, faint empty-slice squares retain their original cell order and therefore their native hit identities.
public struct SculptureVoxelGhostBuffers: Sendable {
    public let cells: [SculptureCell]
    public var byteCount: Int { positions.count + triangles.count + lines.count }

    internal let positions: Data
    internal let triangles: Data
    internal let lines: Data
    internal let dimensions: SIMD3<Int>
    internal let selectedLayer: Int

    /// Matches the native canvas's 65,536-target cap and its existing in-bounds, selected-slice filtering.
    public static func prepare(
        cells: [SculptureCell],
        scene: SculptureVoxelScene,
        selectedLayer: Int
    ) throws -> Self {
        try Task.checkCancellation()
        var accepted: [SculptureCell] = []
        accepted.reserveCapacity(min(cells.count, 65_536))
        for (index, cell) in cells.prefix(65_536).enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard cell.z == selectedLayer, (0..<scene.width).contains(cell.x),
                (0..<scene.height).contains(cell.y), (0..<scene.depth).contains(cell.z)
            else { continue }
            accepted.append(cell)
        }
        let count = accepted.count
        var positions = Data(count: count * 12 * MemoryLayout<Float>.size)
        var triangles = Data(count: count * 6 * MemoryLayout<UInt32>.size)
        var lines = Data(count: count * 8 * MemoryLayout<UInt32>.size)
        let center = SIMD3<Float>(
            Float(scene.width - 1) / 2,
            Float(scene.height - 1) / 2,
            Float(scene.depth - 1) / 2
        )
        try positions.withUnsafeMutableBytes { positionBytes in
            try triangles.withUnsafeMutableBytes { triangleBytes in
                try lines.withUnsafeMutableBytes { lineBytes in
                    let values = positionBytes.bindMemory(to: Float.self)
                    let triangleValues = triangleBytes.bindMemory(to: UInt32.self)
                    let lineValues = lineBytes.bindMemory(to: UInt32.self)
                    for (index, cell) in accepted.enumerated() {
                        if index.isMultiple(of: 256) { try Task.checkCancellation() }
                        let origin = SIMD3<Float>(Float(cell.x), Float(cell.y), Float(cell.z))
                        for corner in 0..<4 {
                            let point = origin + MeshBufferPacking.ghostCorners[corner]
                            let start = index * 12 + corner * 3
                            values[start] = point.x - center.x
                            values[start + 1] = center.y - point.y
                            values[start + 2] = point.z - center.z
                        }
                        MeshBufferPacking.indices(index, triangles: triangleValues, lines: lineValues)
                    }
                }
            }
        }
        try Task.checkCancellation()
        return Self(
            cells: accepted,
            positions: positions,
            triangles: triangles,
            lines: lines,
            dimensions: SIMD3(scene.width, scene.height, scene.depth),
            selectedLayer: selectedLayer
        )
    }
}

private enum MeshBufferPacking {
    static let corners: [[SIMD3<Float>]] = [
        [SIMD3(-0.5, -0.5, -0.5), SIMD3(-0.5, 0.5, -0.5), SIMD3(-0.5, 0.5, 0.5), SIMD3(-0.5, -0.5, 0.5)],
        [SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, -0.5, 0.5), SIMD3(0.5, 0.5, 0.5), SIMD3(0.5, 0.5, -0.5)],
        [SIMD3(-0.5, -0.5, -0.5), SIMD3(-0.5, -0.5, 0.5), SIMD3(0.5, -0.5, 0.5), SIMD3(0.5, -0.5, -0.5)],
        [SIMD3(-0.5, 0.5, -0.5), SIMD3(0.5, 0.5, -0.5), SIMD3(0.5, 0.5, 0.5), SIMD3(-0.5, 0.5, 0.5)],
        [SIMD3(-0.5, -0.5, -0.5), SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, 0.5, -0.5), SIMD3(-0.5, 0.5, -0.5)],
        [SIMD3(-0.5, -0.5, 0.5), SIMD3(-0.5, 0.5, 0.5), SIMD3(0.5, 0.5, 0.5), SIMD3(0.5, -0.5, 0.5)],
    ]
    static let ghostCorners: [SIMD3<Float>] = [
        SIMD3(-0.5, -0.5, 0), SIMD3(-0.5, 0.5, 0), SIMD3(0.5, 0.5, 0), SIMD3(0.5, -0.5, 0),
    ]
    static let colors: [SIMD3<Float>] = {
        let brightness = [0.85, 0.61, 0.96, 0.5, 0.63, 0.83]
        var values = [SIMD3<Float>](repeating: .zero, count: 256 * 6)
        for glyph in Sculpture.palette {
            let tint = SculptureVoxelRasterizer.color(for: glyph)
            for face in 0..<6 {
                let level = brightness[face]
                values[Int(glyph) * 6 + face] = SIMD3(
                    Float(tint.red * level),
                    Float(tint.green * level),
                    Float(tint.blue * level)
                )
            }
        }
        return values
    }()

    static func index(_ face: SculptureVoxelFace) -> Int {
        switch face {
        case .left: 0
        case .right: 1
        case .top: 2
        case .bottom: 3
        case .back: 4
        case .front: 5
        }
    }

    static func indices(
        _ index: Int,
        triangles: UnsafeMutableBufferPointer<UInt32>,
        lines: UnsafeMutableBufferPointer<UInt32>
    ) {
        let base = UInt32(index * 4)
        let triangle = index * 6
        triangles[triangle] = base
        triangles[triangle + 1] = base + 1
        triangles[triangle + 2] = base + 2
        triangles[triangle + 3] = base
        triangles[triangle + 4] = base + 2
        triangles[triangle + 5] = base + 3
        let line = index * 8
        lines[line] = base
        lines[line + 1] = base + 1
        lines[line + 2] = base + 1
        lines[line + 3] = base + 2
        lines[line + 4] = base + 2
        lines[line + 5] = base + 3
        lines[line + 6] = base + 3
        lines[line + 7] = base
    }
}
