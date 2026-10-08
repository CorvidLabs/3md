import RookSculpture

/// An immutable, worker-prepared silhouette. Apply `scale` to the mesh child before world placement or rotation.
/// Original dimensions define placement and culling; native picking follows the scaled occupied coarse triangles.
public struct SculptureWorldCoarseMeshResult: Sendable {
    public let buffers: SculptureVoxelMeshBuffers
    public let scale: SIMD3<Float>
    public let originalDimensions: SIMD3<Int>
    public let stride: Int
    public var scene: SculptureVoxelScene { buffers.scene }
    public var faceCount: Int { scene.surfaces.count }
}

/// Keeps any occupied coarse bin, including a single source cell, and selects its dominant nonempty material.
/// At most 16³ bins and 24,576 faces are prepared for one immutable model, independent of camera movement.
public enum SculptureWorldCoarseMesh {
    public static let maximumDimension = 16
    public static let maximumFaces = 6 * maximumDimension * maximumDimension * maximumDimension

    public static func prepare(_ sculpture: Sculpture) throws -> SculptureWorldCoarseMeshResult {
        try Task.checkCancellation()
        let dimensions = SIMD3(sculpture.width, sculpture.height, sculpture.depth)
        guard (1...Sculpture.maximumDimension).contains(dimensions.x),
            (1...Sculpture.maximumDimension).contains(dimensions.y),
            (1...Sculpture.maximumDimension).contains(dimensions.z)
        else { throw SculptureError.invalidDimensions }
        let stride = (max(dimensions.x, dimensions.y, dimensions.z) + maximumDimension - 1) / maximumDimension
        let width = (dimensions.x + stride - 1) / stride
        let height = (dimensions.y + stride - 1) / stride
        let depth = (dimensions.z + stride - 1) / stride
        guard (1...maximumDimension).contains(width), (1...maximumDimension).contains(height),
            (1...maximumDimension).contains(depth)
        else { throw SculptureError.invalidDimensions }

        let palette = Sculpture.palette
        let materialCount = palette.count
        var materialIndex = [Int](repeating: -1, count: 256)
        for (index, glyph) in palette.enumerated() { materialIndex[Int(glyph)] = index }
        // Source dimensions are at most 256, so stride <=16 and each counter <=16³=4096.
        // Nine materials across at most 4096 bins require at most 73,728 histogram bytes.
        var counts = [UInt16](repeating: 0, count: width * height * depth * materialCount)
        for (z, layer) in sculpture.layers.enumerated() {
            try Task.checkCancellation()
            guard sculpture.containsOccupiedCells(inLayer: z) else { continue }
            let coarseLayer = (z / stride) * width * height
            for y in 0..<sculpture.height {
                try Task.checkCancellation()
                guard sculpture.containsOccupiedCells(inRow: y, ofLayer: z) else { continue }
                let sourceRow = y * sculpture.width
                let coarseRow = coarseLayer + (y / stride) * width
                for x in 0..<sculpture.width {
                    let glyph = layer[sourceRow + x]
                    guard glyph != Sculpture.empty else { continue }
                    let material = materialIndex[Int(glyph)]
                    guard material >= 0 else { throw SculptureError.invalidGlyph }
                    counts[(coarseRow + x / stride) * materialCount + material] += 1
                }
            }
        }

        var layers = [[UInt8]]()
        layers.reserveCapacity(depth)
        for z in 0..<depth {
            try Task.checkCancellation()
            var layer = [UInt8](repeating: Sculpture.empty, count: width * height)
            for y in 0..<height {
                try Task.checkCancellation()
                for x in 0..<width {
                    let bin = (z * width * height + y * width + x) * materialCount
                    var dominantCount: UInt16 = 0
                    for material in palette.indices {
                        let count = counts[bin + material]
                        // Equal counts retain the first material in the public palette's stable order.
                        if count > dominantCount {
                            dominantCount = count
                            layer[y * width + x] = palette[material]
                        }
                    }
                }
            }
            layers.append(layer)
        }
        try Task.checkCancellation()
        let coarse = try Sculpture(title: sculpture.title, width: width, height: height, layers: layers)
        let scene = try SculptureVoxelSurfaceExtractor.extract(coarse)
        guard scene.surfaces.count <= maximumFaces else { throw SculptureVoxelSurfaceError.tooManyFaces }
        let buffers = try SculptureVoxelMeshBuffers.prepare(scene)
        try Task.checkCancellation()
        // Existing packed positions are centered. Per-axis scaling restores the exact original volume bounds,
        // including odd dimensions and a partially filled final bin, without translating the model center.
        return SculptureWorldCoarseMeshResult(
            buffers: buffers,
            scale: SIMD3(
                Float(dimensions.x) / Float(width),
                Float(dimensions.y) / Float(height),
                Float(dimensions.z) / Float(depth)
            ),
            originalDimensions: dimensions,
            stride: stride
        )
    }
}
