import Foundation
import RookSculpture

/// Directions use document coordinates: Y increases downward and Z increases toward the front.
public enum SculptureVoxelFace: String, CaseIterable, Sendable {
    case left, right, top, bottom, back, front

    fileprivate var offset: (Int, Int, Int) {
        switch self {
        case .left: (-1, 0, 0)
        case .right: (1, 0, 0)
        case .top: (0, -1, 0)
        case .bottom: (0, 1, 0)
        case .back: (0, 0, -1)
        case .front: (0, 0, 1)
        }
    }
}

public struct SculptureVoxelVertex: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let depth: Double
}

/// One exterior cube face, or one editable empty-cell square in the selected Z slice.
public struct SculptureVoxelQuad: Equatable, Sendable {
    public let cell: SculptureCell
    public let face: SculptureVoxelFace?
    public let glyph: UInt8?
    public let vertices: [SculptureVoxelVertex]
    public let depth: Double
    public let brightness: Double
    public let adjacentCell: SculptureCell?
    public var isEmpty: Bool { glyph == nil }
    fileprivate let minimumX: Double
    fileprivate let maximumX: Double
    fileprivate let minimumY: Double
    fileprivate let maximumY: Double
}

public struct SculptureVoxelHit: Equatable, Sendable {
    public let cell: SculptureCell
    public let face: SculptureVoxelFace?
    public let isEmpty: Bool
    public let adjacentCell: SculptureCell?
    /// Add to a visible empty slice cell or to the empty neighbor beyond an occupied cube face.
    public var paintCell: SculptureCell? { isEmpty ? cell : adjacentCell }
}

public struct SculptureVoxelFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let quads: [SculptureVoxelQuad]
    /// No partial geometry is returned when the bounded preview exceeds its surface budget.
    public let isOverBudget: Bool
    fileprivate let cameraDistance: Double

    fileprivate init(
        width: Int,
        height: Int,
        quads: [SculptureVoxelQuad],
        cameraDistance: Double,
        isOverBudget: Bool = false
    ) {
        self.width = width
        self.height = height
        self.quads = quads
        self.cameraDistance = cameraDistance
        self.isOverBudget = isOverBudget
    }

    /// Coordinates are pixels measured from the upper-left corner of the rendered image.
    public func hitTest(x: Double, y: Double) -> SculptureVoxelHit? {
        guard x.isFinite, y.isFinite, x >= 0, y >= 0, x < Double(width), y < Double(height) else { return nil }
        var nearest: (SculptureVoxelQuad, Double)?
        for quad in quads {
            guard let depth = intersectionDepth(quad, x: x, y: y) else { continue }
            if let current = nearest, depth <= current.1 { continue }
            nearest = (quad, depth)
        }
        guard let quad = nearest?.0 else { return nil }
        return SculptureVoxelHit(
            cell: quad.cell,
            face: quad.face,
            isEmpty: quad.isEmpty,
            adjacentCell: quad.adjacentCell
        )
    }

    private func intersectionDepth(_ quad: SculptureVoxelQuad, x: Double, y: Double) -> Double? {
        guard quad.vertices.count == 4 else { return nil }
        let points = quad.vertices
        guard
            x >= quad.minimumX, x <= quad.maximumX,
            y >= quad.minimumY, y <= quad.maximumY
        else { return nil }
        return triangleDepth(points[0], points[1], points[2], x: x, y: y)
            ?? triangleDepth(points[0], points[2], points[3], x: x, y: y)
    }

    private func triangleDepth(
        _ a: SculptureVoxelVertex,
        _ b: SculptureVoxelVertex,
        _ c: SculptureVoxelVertex,
        x: Double,
        y: Double
    ) -> Double? {
        let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        guard abs(denominator) > 0.000_001 else { return nil }
        let wa = ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / denominator
        let wb = ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / denominator
        let wc = 1 - wa - wb
        guard wa >= -0.000_001, wb >= -0.000_001, wc >= -0.000_001 else { return nil }
        let reciprocalDistance =
            wa / (cameraDistance - a.depth)
            + wb / (cameraDistance - b.depth) + wc / (cameraDistance - c.depth)
        guard reciprocalDistance > 0 else { return nil }
        return cameraDistance - 1 / reciprocalDistance
    }
}

public enum SculptureVoxelProjection {
    /// Includes occupied faces facing the camera and editable empty-slice squares.
    public static let maximumQuads = 250_000

    public static func frame(
        _ sculpture: Sculpture,
        camera: SculptureCamera,
        width: Int,
        height: Int,
        selectedLayer: Int? = nil,
        showsEmptyCells: Bool = true
    ) -> SculptureVoxelFrame {
        let width = max(64, min(2_048, width)), height = max(64, min(2_048, height))
        let view = VoxelCamera(sculpture: sculpture, camera: camera, width: width, height: height)
        let selected = selectedLayer.flatMap { sculpture.layers.indices.contains($0) ? $0 : nil }
        let faces = SculptureVoxelFace.allCases
        var quads: [SculptureVoxelQuad] = []
        quads.reserveCapacity(min(sculpture.width * sculpture.height * sculpture.depth, 16_384))
        for z in 0..<sculpture.depth {
            guard !Task.isCancelled else {
                return SculptureVoxelFrame(width: width, height: height, quads: [], cameraDistance: view.distance)
            }
            let slice = sculpture.layers[z]
            if !(showsEmptyCells && z == selected), !slice.contains(where: { $0 != Sculpture.empty }) { continue }
            for y in 0..<sculpture.height {
                for x in 0..<sculpture.width {
                    let cell = SculptureCell(x: x, y: y, z: z)
                    let glyph = slice[y * sculpture.width + x]
                    if glyph == Sculpture.empty {
                        if showsEmptyCells, z == selected {
                            guard quads.count < maximumQuads else {
                                return SculptureVoxelFrame(
                                    width: width,
                                    height: height,
                                    quads: [],
                                    cameraDistance: view.distance,
                                    isOverBudget: true
                                )
                            }
                            quads.append(view.ghost(cell))
                        }
                        continue
                    }
                    for face in faces {
                        let offset = face.offset
                        let neighbor = SculptureCell(x: x + offset.0, y: y + offset.1, z: z + offset.2)
                        let neighborGlyph = sculpture.glyph(at: neighbor)
                        guard neighborGlyph == nil || neighborGlyph == Sculpture.empty else { continue }
                        guard view.facesCamera(face, cell: cell) else { continue }
                        guard quads.count < maximumQuads else {
                            return SculptureVoxelFrame(
                                width: width,
                                height: height,
                                quads: [],
                                cameraDistance: view.distance,
                                isOverBudget: true
                            )
                        }
                        quads.append(
                            view.face(
                                face,
                                cell: cell,
                                glyph: glyph,
                                adjacent: neighborGlyph == Sculpture.empty ? neighbor : nil
                            )
                        )
                    }
                }
            }
        }
        return sortedFrame(&quads, view: view, width: width, height: height)
    }

    /// Projects a reusable exterior scene without rescanning its volume. This export
    /// path has the same camera, face ordering, picking, and 250,000-quad frame limit
    /// as the document overload; it does not add editable empty-slice squares.
    public static func frame(
        _ scene: SculptureVoxelScene,
        camera: SculptureCamera,
        width: Int,
        height: Int
    ) -> SculptureVoxelFrame {
        let width = max(64, min(2_048, width)), height = max(64, min(2_048, height))
        let view = VoxelCamera(
            volumeWidth: scene.width,
            volumeHeight: scene.height,
            volumeDepth: scene.depth,
            camera: camera,
            width: width,
            height: height
        )
        var quads: [SculptureVoxelQuad] = []
        quads.reserveCapacity(min(scene.surfaces.count, maximumQuads))
        for (index, surface) in scene.surfaces.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled {
                return SculptureVoxelFrame(width: width, height: height, quads: [], cameraDistance: view.distance)
            }
            guard view.facesCamera(surface.face, cell: surface.cell) else { continue }
            guard quads.count < maximumQuads else {
                return SculptureVoxelFrame(
                    width: width,
                    height: height,
                    quads: [],
                    cameraDistance: view.distance,
                    isOverBudget: true
                )
            }
            quads.append(
                view.face(surface.face, cell: surface.cell, glyph: surface.glyph, adjacent: surface.adjacentCell)
            )
        }
        return sortedFrame(&quads, view: view, width: width, height: height)
    }

    private static func sortedFrame(
        _ quads: inout [SculptureVoxelQuad],
        view: VoxelCamera,
        width: Int,
        height: Int
    ) -> SculptureVoxelFrame {
        guard !Task.isCancelled else {
            return SculptureVoxelFrame(width: width, height: height, quads: [], cameraDistance: view.distance)
        }
        quads.sort { left, right in
            if left.depth != right.depth { return left.depth < right.depth }
            if left.isEmpty != right.isEmpty { return left.isEmpty }
            if left.cell.z != right.cell.z { return left.cell.z < right.cell.z }
            if left.cell.y != right.cell.y { return left.cell.y < right.cell.y }
            if left.cell.x != right.cell.x { return left.cell.x < right.cell.x }
            return (left.face?.rawValue ?? "") < (right.face?.rawValue ?? "")
        }
        return SculptureVoxelFrame(
            width: width,
            height: height,
            quads: Task.isCancelled ? [] : quads,
            cameraDistance: view.distance
        )
    }
}

private struct VoxelCamera {
    let centerX: Double
    let centerY: Double
    let centerZ: Double
    let width: Double
    let height: Double
    let scale: Double
    let cy: Double
    let sy: Double
    let cp: Double
    let sp: Double
    let distance: Double

    init(sculpture: Sculpture, camera: SculptureCamera, width: Int, height: Int) {
        self.init(
            volumeWidth: sculpture.width,
            volumeHeight: sculpture.height,
            volumeDepth: sculpture.depth,
            camera: camera,
            width: width,
            height: height
        )
    }

    init(volumeWidth: Int, volumeHeight: Int, volumeDepth: Int, camera: SculptureCamera, width: Int, height: Int) {
        centerX = Double(volumeWidth - 1) / 2
        centerY = Double(volumeHeight - 1) / 2
        centerZ = Double(volumeDepth - 1) / 2
        self.width = Double(width)
        self.height = Double(height)
        let extent = Double(max(volumeWidth, volumeHeight, volumeDepth))
        let yaw = camera.yaw.isFinite ? camera.yaw.truncatingRemainder(dividingBy: 2 * .pi) : 0
        let pitch = camera.pitch.isFinite ? max(-1.4, min(1.4, camera.pitch)) : 0
        let zoom = camera.zoom.isFinite ? max(0.5, min(2, camera.zoom)) : 1
        scale = Double(min(width, height)) * 0.68 / extent * zoom
        cy = cos(yaw); sy = sin(yaw); cp = cos(pitch); sp = sin(pitch)
        distance = extent * 3
    }

    func facesCamera(_ face: SculptureVoxelFace, cell: SculptureCell) -> Bool {
        let offset = face.offset
        let nx = Double(offset.0), ny = -Double(offset.1), nz = Double(offset.2)
        let x = Double(cell.x) - centerX + nx * 0.5
        let y = centerY - Double(cell.y) + ny * 0.5
        let z = Double(cell.z) - centerZ + nz * 0.5
        return nx * (-sy * cp * distance - x) + ny * (sp * distance - y) + nz * (cy * cp * distance - z) > 0.000_001
    }

    func face(_ face: SculptureVoxelFace, cell: SculptureCell, glyph: UInt8, adjacent: SculptureCell?)
        -> SculptureVoxelQuad
    {
        let x = Double(cell.x), y = Double(cell.y), z = Double(cell.z)
        let corners: [(Double, Double, Double)]
        switch face {
        case .left:
            corners = [
                (x - 0.5, y - 0.5, z - 0.5), (x - 0.5, y + 0.5, z - 0.5),
                (x - 0.5, y + 0.5, z + 0.5), (x - 0.5, y - 0.5, z + 0.5),
            ]
        case .right:
            corners = [
                (x + 0.5, y - 0.5, z - 0.5), (x + 0.5, y - 0.5, z + 0.5),
                (x + 0.5, y + 0.5, z + 0.5), (x + 0.5, y + 0.5, z - 0.5),
            ]
        case .top:
            corners = [
                (x - 0.5, y - 0.5, z - 0.5), (x - 0.5, y - 0.5, z + 0.5),
                (x + 0.5, y - 0.5, z + 0.5), (x + 0.5, y - 0.5, z - 0.5),
            ]
        case .bottom:
            corners = [
                (x - 0.5, y + 0.5, z - 0.5), (x + 0.5, y + 0.5, z - 0.5),
                (x + 0.5, y + 0.5, z + 0.5), (x - 0.5, y + 0.5, z + 0.5),
            ]
        case .back:
            corners = [
                (x - 0.5, y - 0.5, z - 0.5), (x + 0.5, y - 0.5, z - 0.5),
                (x + 0.5, y + 0.5, z - 0.5), (x - 0.5, y + 0.5, z - 0.5),
            ]
        case .front:
            corners = [
                (x - 0.5, y - 0.5, z + 0.5), (x - 0.5, y + 0.5, z + 0.5),
                (x + 0.5, y + 0.5, z + 0.5), (x + 0.5, y - 0.5, z + 0.5),
            ]
        }
        let offset = face.offset
        let brightness = max(
            0.45,
            min(1, 0.73 - Double(offset.0) * 0.12 - Double(offset.1) * 0.23 + Double(offset.2) * 0.10)
        )
        return quad(cell: cell, face: face, glyph: glyph, corners: corners, brightness: brightness, adjacent: adjacent)
    }

    func ghost(_ cell: SculptureCell) -> SculptureVoxelQuad {
        let x = Double(cell.x), y = Double(cell.y), z = Double(cell.z)
        return quad(
            cell: cell,
            face: nil,
            glyph: nil,
            corners: [
                (x - 0.5, y - 0.5, z), (x - 0.5, y + 0.5, z),
                (x + 0.5, y + 0.5, z), (x + 0.5, y - 0.5, z),
            ],
            brightness: 1,
            adjacent: nil
        )
    }

    private func quad(
        cell: SculptureCell,
        face: SculptureVoxelFace?,
        glyph: UInt8?,
        corners: [(Double, Double, Double)],
        brightness: Double,
        adjacent: SculptureCell?
    ) -> SculptureVoxelQuad {
        let vertices = corners.map(project)
        return SculptureVoxelQuad(
            cell: cell,
            face: face,
            glyph: glyph,
            vertices: vertices,
            depth: vertices.reduce(0) { $0 + $1.depth } / 4,
            brightness: brightness,
            adjacentCell: adjacent,
            minimumX: vertices.reduce(.infinity) { min($0, $1.x) },
            maximumX: vertices.reduce(-.infinity) { max($0, $1.x) },
            minimumY: vertices.reduce(.infinity) { min($0, $1.y) },
            maximumY: vertices.reduce(-.infinity) { max($0, $1.y) }
        )
    }

    private func project(_ point: (Double, Double, Double)) -> SculptureVoxelVertex {
        let vx = point.0 - centerX, vy = centerY - point.1, vz = point.2 - centerZ
        let rx = vx * cy + vz * sy
        let rz = -vx * sy + vz * cy
        let ry = vy * cp - rz * sp
        let depth = vy * sp + rz * cp
        let perspective = 1 / (1 - depth / distance)
        return SculptureVoxelVertex(
            x: width / 2 + rx * scale * perspective,
            y: height / 2 - ry * scale * perspective,
            depth: depth
        )
    }
}
