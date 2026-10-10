import Foundation

public struct SculptureCamera: Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var zoom: Double
    public var panX: Double
    public var panY: Double
    public var fitsVolume: Bool
    public var axisRotation: SIMD4<Double>

    public init(
        yaw: Double = -0.6,
        pitch: Double = 0.35,
        zoom: Double = 1,
        panX: Double = 0,
        panY: Double = 0,
        fitsVolume: Bool = false,
        axisRotation: SIMD4<Double> = SIMD4(0, 0, 0, 1)
    ) {
        self.yaw = yaw
        self.pitch = pitch
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.fitsVolume = fitsVolume
        self.axisRotation = axisRotation
    }

    /// Session inputs are sanitized once for the scalar and live render paths.
    public var normalized: Self {
        Self(
            yaw: yaw.isFinite ? yaw.truncatingRemainder(dividingBy: 2 * .pi) : 0,
            pitch: pitch.isFinite ? pitch.truncatingRemainder(dividingBy: 2 * .pi) : 0,
            zoom: zoom.isFinite ? max(0.5, min(2, zoom)) : 1,
            panX: panX.isFinite ? max(-1_000_000, min(1_000_000, panX)) : 0,
            panY: panY.isFinite ? max(-1_000_000, min(1_000_000, panY)) : 0,
            fitsVolume: fitsVolume,
            axisRotation: normalizedRotation
        )
    }

    public var basis: (right: SIMD3<Double>, up: SIMD3<Double>, back: SIMD3<Double>) {
        let camera = normalized
        let cy = cos(camera.yaw), sy = sin(camera.yaw), cp = cos(camera.pitch), sp = sin(camera.pitch)
        return (
            rotated(SIMD3(cy, 0, sy)), rotated(SIMD3(sy * sp, cp, -cy * sp)),
            rotated(SIMD3(-sy * cp, sp, cy * cp))
        )
    }

    private var normalizedRotation: SIMD4<Double> {
        let largest = max(abs(axisRotation.x), abs(axisRotation.y), abs(axisRotation.z), abs(axisRotation.w))
        guard largest.isFinite, largest > 0,
            axisRotation.x.isFinite, axisRotation.y.isFinite, axisRotation.z.isFinite, axisRotation.w.isFinite
        else { return SIMD4(0, 0, 0, 1) }
        let scaled = axisRotation / largest
        return scaled / sqrt((scaled * scaled).sum())
    }

    private func rotated(_ point: SIMD3<Double>) -> SIMD3<Double> {
        let q = normalizedRotation
        let vector = SIMD3(q.x, q.y, q.z)
        let cross =
            SIMD3(
                vector.y * point.z - vector.z * point.y,
                vector.z * point.x - vector.x * point.z,
                vector.x * point.y - vector.y * point.x
            ) * 2
        return point + q.w * cross
            + SIMD3(
                vector.y * cross.z - vector.z * cross.y,
                vector.z * cross.x - vector.x * cross.z,
                vector.x * cross.y - vector.y * cross.x
            )
    }

    /// Positive rotation follows document X, row-down Y, and plane Z. Orientation remains session-only.
    public mutating func rotate(axis: Int, radians: Double) {
        guard (0...2).contains(axis), radians.isFinite else { return }
        let angle = radians.truncatingRemainder(dividingBy: 2 * .pi) / 2
        var rotation = SIMD4<Double>(0, 0, 0, cos(angle))
        rotation[axis] = sin(angle) * (axis == 1 ? -1 : 1)
        let q = normalizedRotation
        let a = SIMD3(rotation.x, rotation.y, rotation.z), b = SIMD3(q.x, q.y, q.z)
        let vector =
            rotation.w * b + q.w * a
            + SIMD3(
                a.y * b.z - a.z * b.y,
                a.z * b.x - a.x * b.z,
                a.x * b.y - a.y * b.x
            )
        axisRotation = SIMD4(vector.x, vector.y, vector.z, rotation.w * q.w - (a * b).sum())
        self = normalized
    }

    /// Interactive sessions opt into complete-cube framing. Default cameras preserve existing exported previews.
    public func projectionScale(dimensions: SIMD3<Int>, width: Double, height: Double) -> Double {
        let camera = normalized
        let extent = Double(max(1, dimensions.x, dimensions.y, dimensions.z))
        let distance = extent * 3
        let width = max(1, width), height = max(1, height)
        let scale = min(width, height) * 0.68 / extent * camera.zoom
        guard camera.fitsVolume else { return scale }
        var tangent = height / (2 * scale * distance)
        let basis = camera.basis
        var fit = 0.0
        for x in [-Double(dimensions.x) / 2, Double(dimensions.x) / 2] {
            for y in [-Double(dimensions.y) / 2, Double(dimensions.y) / 2] {
                for z in [-Double(dimensions.z) / 2, Double(dimensions.z) / 2] {
                    let point = SIMD3(x, y, z)
                    let depth = distance - (point * basis.back).sum()
                    fit = max(
                        fit,
                        abs((point * basis.up).sum()) / depth,
                        abs((point * basis.right).sum()) / depth / (width / height)
                    )
                }
            }
        }
        tangent = max(tangent, fit * 1.12 / camera.zoom)
        return height / (2 * distance * tangent)
    }

    public mutating func orbit(horizontal: Double, vertical: Double) {
        guard horizontal.isFinite, vertical.isFinite else { return }
        var camera = normalized
        camera.yaw += horizontal * 0.008
        camera.pitch += vertical * 0.008
        self = camera.normalized
    }

    public mutating func pan(
        horizontal: Double,
        vertical: Double,
        extent: Double,
        width: Double,
        height: Double,
        dimensions: SIMD3<Int>? = nil
    ) {
        guard horizontal.isFinite, vertical.isFinite, extent.isFinite, extent > 0,
            width.isFinite, height.isFinite, width > 0, height > 0
        else { return }
        var camera = normalized
        let scale =
            dimensions.map { camera.projectionScale(dimensions: $0, width: width, height: height) }
            ?? min(width, height) * 0.68 / extent * camera.zoom
        guard scale.isFinite, scale > 0 else { return }
        camera.panX -= horizontal / scale
        camera.panY += vertical / scale
        self = camera.normalized
    }

    public mutating func magnify(_ factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        var camera = normalized
        camera.zoom = max(0.5, min(2, camera.zoom * factor))
        self = camera
    }
}

public struct ProjectedGlyph: Equatable, Sendable {
    public let glyph: UInt8
    public let cell: SculptureCell
    public let depth: Double
    public let brightness: Double
}

public struct SculptureFrame: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let pixels: [ProjectedGlyph?]

    public var text: String {
        (0..<rows).map { row in
            String(decoding: (0..<columns).map { pixels[row * columns + $0]?.glyph ?? 32 }, as: UTF8.self)
        }.joined(separator: "\n") + "\n"
    }

    public func cell(column: Int, row: Int) -> SculptureCell? {
        guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
        return pixels[row * columns + column]?.cell
    }
}

/// Deterministic projection and nearest-cell picking. The renderer consumes this immutable frame.
public enum SculptureProjection {
    public static func frame(
        _ sculpture: Sculpture,
        camera: SculptureCamera,
        columns: Int = 64,
        rows: Int = 36
    ) -> SculptureFrame {
        let columns = max(8, min(160, columns))
        let rows = max(8, min(100, rows))
        var pixels = [ProjectedGlyph?](repeating: nil, count: columns * rows)
        guard !Task.isCancelled, sculpture.occupiedCount > 0 else {
            return SculptureFrame(columns: columns, rows: rows, pixels: pixels)
        }
        let camera = camera.normalized
        let basis = camera.basis
        let extent = Double(max(sculpture.width, sculpture.height, sculpture.depth))
        let scale = camera.projectionScale(
            dimensions: SIMD3(sculpture.width, sculpture.height, sculpture.depth),
            width: Double(columns) / 2,
            height: Double(rows)
        )
        let centerX = Double(sculpture.width - 1) / 2
        let centerY = Double(sculpture.height - 1) / 2
        let centerZ = Double(sculpture.depth - 1) / 2

        for (z, layer) in sculpture.layers.enumerated() {
            guard sculpture.containsOccupiedCells(inLayer: z) else { continue }
            let vz = Double(z) - centerZ
            for y in 0..<sculpture.height {
                guard !Task.isCancelled else { return emptyFrame(columns: columns, rows: rows) }
                guard sculpture.containsOccupiedCells(inRow: y, ofLayer: z) else { continue }
                let rowOffset = y * sculpture.width
                let vy = centerY - Double(y)
                for x in 0..<sculpture.width {
                    let glyph = layer[rowOffset + x]
                    guard glyph != Sculpture.empty else { continue }
                    let cell = SculptureCell(x: x, y: y, z: z)
                    let vx = Double(x) - centerX
                    let point = SIMD3(vx, vy, vz)
                    let rx = (point * basis.right).sum()
                    let ry = (point * basis.up).sum()
                    let depth = (point * basis.back).sum()
                    let perspective = 1 / (1 - depth / (extent * 3))
                    let column = Int((Double(columns) / 2 + (rx - camera.panX) * scale * 2 * perspective).rounded())
                    let row = Int((Double(rows) / 2 - (ry - camera.panY) * scale * perspective).rounded())
                    guard (0..<columns).contains(column), (0..<rows).contains(row) else { continue }
                    let index = row * columns + column
                    if let previous = pixels[index], previous.depth >= depth { continue }
                    pixels[index] = ProjectedGlyph(
                        glyph: glyph,
                        cell: cell,
                        depth: depth,
                        brightness: max(0.3, min(1, 0.65 + depth / extent * 0.65))
                    )
                }
            }
        }
        guard !Task.isCancelled else { return emptyFrame(columns: columns, rows: rows) }
        return SculptureFrame(columns: columns, rows: rows, pixels: pixels)
    }

    private static func emptyFrame(columns: Int, rows: Int) -> SculptureFrame {
        SculptureFrame(columns: columns, rows: rows, pixels: [ProjectedGlyph?](repeating: nil, count: columns * rows))
    }
}
