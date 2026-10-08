import Foundation
import RookSculpture

/// One exterior face in document coordinates, independent of camera or render style.
public struct SculptureVoxelSurface: Equatable, Sendable {
    public let cell: SculptureCell
    public let face: SculptureVoxelFace
    public let glyph: UInt8
    /// Empty in-bounds neighbor beyond this face. Nil means the face reaches a volume boundary.
    public let adjacentCell: SculptureCell?
}

/// Immutable geometry input that can be reused while the camera moves.
public struct SculptureVoxelScene: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let depth: Int
    public let occupiedCount: Int
    /// Stable z/y/x scan order, then `SculptureVoxelFace.allCases` order within a cell.
    public let surfaces: [SculptureVoxelSurface]
}

public enum SculptureVoxelSurfaceExtractor {
    /// Includes all exterior faces, including faces pointing away from the current camera.
    public static let maximumFaces = 500_000

    /// Throws on cancellation or budget overflow. A partially extracted scene is never returned.
    public static func extract(_ sculpture: Sculpture) throws -> SculptureVoxelScene {
        try Task.checkCancellation()
        var surfaces: [SculptureVoxelSurface] = []
        surfaces.reserveCapacity(min(sculpture.occupiedCount * 3, maximumFaces))
        let faces = SculptureVoxelFace.allCases
        for (z, layer) in sculpture.layers.enumerated() {
            try Task.checkCancellation()
            guard sculpture.containsOccupiedCells(inLayer: z) else { continue }
            let previousLayer = z > 0 ? sculpture.layers[z - 1] : nil
            let nextLayer = z + 1 < sculpture.depth ? sculpture.layers[z + 1] : nil
            for y in 0..<sculpture.height {
                try Task.checkCancellation()
                guard sculpture.containsOccupiedCells(inRow: y, ofLayer: z) else { continue }
                let rowOffset = y * sculpture.width
                for x in 0..<sculpture.width {
                    let index = rowOffset + x
                    let glyph = layer[index]
                    guard glyph != Sculpture.empty else { continue }
                    for face in faces {
                        // Sculpture validates every row and layer at construction. Read the
                        // six neighboring bytes directly; most occupied cells are interior
                        // and never need a cell or face value allocated for their neighbors.
                        let neighborGlyph: UInt8?
                        switch face {
                        case .left: neighborGlyph = x > 0 ? layer[index - 1] : nil
                        case .right: neighborGlyph = x + 1 < sculpture.width ? layer[index + 1] : nil
                        case .top: neighborGlyph = y > 0 ? layer[index - sculpture.width] : nil
                        case .bottom: neighborGlyph = y + 1 < sculpture.height ? layer[index + sculpture.width] : nil
                        case .back: neighborGlyph = previousLayer?[index]
                        case .front: neighborGlyph = nextLayer?[index]
                        }
                        guard neighborGlyph == nil || neighborGlyph == Sculpture.empty else { continue }
                        guard surfaces.count < maximumFaces else { throw SculptureVoxelSurfaceError.tooManyFaces }
                        let neighborOffset = offset(for: face)
                        surfaces.append(
                            SculptureVoxelSurface(
                                cell: SculptureCell(x: x, y: y, z: z),
                                face: face,
                                glyph: glyph,
                                adjacentCell: neighborGlyph == Sculpture.empty
                                    ? SculptureCell(
                                        x: x + neighborOffset.x,
                                        y: y + neighborOffset.y,
                                        z: z + neighborOffset.z
                                    ) : nil
                            )
                        )
                    }
                }
            }
        }
        try Task.checkCancellation()
        return SculptureVoxelScene(
            width: sculpture.width,
            height: sculpture.height,
            depth: sculpture.depth,
            occupiedCount: sculpture.occupiedCount,
            surfaces: surfaces
        )
    }

    private static func offset(for face: SculptureVoxelFace) -> (x: Int, y: Int, z: Int) {
        switch face {
        case .left: (-1, 0, 0)
        case .right: (1, 0, 0)
        case .top: (0, -1, 0)
        case .bottom: (0, 1, 0)
        case .back: (0, 0, -1)
        case .front: (0, 0, 1)
        }
    }
}

public enum SculptureVoxelSurfaceError: Error, LocalizedError, Equatable, Sendable {
    case tooManyFaces

    public var errorDescription: String? {
        "This volume exceeds the cube scene limit of 500,000 exterior faces. Use Slice or ASCII to edit it."
    }
}
