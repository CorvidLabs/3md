import Foundation

public struct SculptureCamera: Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var zoom: Double

    public init(yaw: Double = -0.6, pitch: Double = 0.35, zoom: Double = 1) {
        self.yaw = yaw
        self.pitch = pitch
        self.zoom = zoom
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
        let yaw = camera.yaw.isFinite ? camera.yaw.truncatingRemainder(dividingBy: 2 * .pi) : 0
        let pitch = camera.pitch.isFinite ? max(-1.4, min(1.4, camera.pitch)) : 0
        let zoom = camera.zoom.isFinite ? max(0.5, min(2, camera.zoom)) : 1
        let extent = Double(max(sculpture.width, sculpture.height, sculpture.depth))
        let scale = min(Double(columns) / 2, Double(rows)) * 0.68 / extent * zoom
        let cy = cos(yaw)
        let sy = sin(yaw)
        let cp = cos(pitch)
        let sp = sin(pitch)
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
                    let rx = vx * cy + vz * sy
                    let rz = -vx * sy + vz * cy
                    let ry = vy * cp - rz * sp
                    let depth = vy * sp + rz * cp
                    let perspective = 1 / (1 - depth / (extent * 3))
                    let column = Int((Double(columns) / 2 + rx * scale * 2 * perspective).rounded())
                    let row = Int((Double(rows) / 2 - ry * scale * perspective).rounded())
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
