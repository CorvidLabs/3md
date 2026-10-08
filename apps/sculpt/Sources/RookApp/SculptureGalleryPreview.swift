import CoreGraphics
import Foundation
import RookRendering
import RookSculpture

/// CGImage is immutable; a worker publishes a finished thumbnail through this wrapper.
internal struct SculptureGalleryPreviewImage: @unchecked Sendable {
    internal let image: CGImage?
}

/// Bounded gallery thumbnails. A voxel scene is reduced to at most 64 cells per axis before it is rendered, and a
/// world is drawn as a top-down plan of its placements, so no preview renders a full large volume or allocates a
/// dense buffer larger than one 256-cell model.
internal enum SculptureGalleryPreview {
    /// The largest axis a thumbnail volume keeps. Larger volumes are reduced by whole blocks.
    internal static let maximumAxis = 64
    /// Thumbnail width in pixels.
    internal static let width = 420
    /// Thumbnail height in pixels.
    internal static let height = 320
    /// Samples per axis of one model's top surface in a world plan.
    private static let planSamples = 32


    // MARK: - Internal Methods

    /// The thumbnail camera: map-like scenes are seen from higher up, and Space a little farther away. Math ladder
    /// models fill their whole volume, so they keep the full frame instead of the closer authored framing.
    internal static func camera(for entry: SculptureGalleryEntry) -> SculptureCamera {
        let looksDown = ["Maps", "Worlds", "Space"].contains(entry.category) || entry.kind != .model
        let zoom: Double
        if entry.category == "Space" {
            zoom = 0.9
        } else if entry.kind == .model && entry.formula == nil {
            zoom = 1.3
        } else {
            zoom = 1
        }
        return SculptureCamera(yaw: -0.6, pitch: looksDown ? 0.7 : 0.35, zoom: zoom)
    }

    /// Renders a bounded thumbnail of a created scene. Call on a worker; cancellation throws.
    /// - Parameters:
    ///   - scene: The scene the entry's factory created.
    ///   - entry: The entry, which chooses the camera.
    /// - Returns: The thumbnail, or nil when there is nothing to draw.
    internal static func image(of scene: SculptureScene, entry: SculptureGalleryEntry) throws -> CGImage? {
        try Task.checkCancellation()
        let image: CGImage?
        switch scene {
        case .voxels(let sculpture):
            image = cubes(try reduced(sculpture), camera: camera(for: entry))
        case .composition(let composition):
            image = cubes(try reduced(composition.expanded()), camera: camera(for: entry))
        case .world(let world):
            image = try plan(of: world)
        }
        try Task.checkCancellation()
        return image
    }

    /// Reduces a volume by whole blocks until no axis exceeds `maximumAxis`. Each reduced cell keeps the topmost
    /// occupied glyph of its block, so surfaces keep their colors. Smaller volumes are returned unchanged.
    /// - Parameters:
    ///   - sculpture: The full volume.
    ///   - maximumAxis: The largest axis to keep.
    /// - Returns: A volume at most `maximumAxis` cells on every axis.
    internal static func reduced(_ sculpture: Sculpture, maximumAxis: Int = maximumAxis) throws -> Sculpture {
        let largest = max(sculpture.width, sculpture.height, sculpture.depth)
        guard largest > maximumAxis, maximumAxis > 0 else { return sculpture }
        let factor = (largest + maximumAxis - 1) / maximumAxis
        let width = (sculpture.width + factor - 1) / factor
        let height = (sculpture.height + factor - 1) / factor
        let depth = (sculpture.depth + factor - 1) / factor
        var layers: [[UInt8]] = []
        layers.reserveCapacity(depth)
        for blockZ in 0..<depth {
            try Task.checkCancellation()
            let sources = (blockZ * factor..<min((blockZ + 1) * factor, sculpture.depth)).map { sculpture.layers[$0] }
            var layer = [UInt8](repeating: Sculpture.empty, count: width * height)
            for blockY in 0..<height {
                let rows = blockY * factor..<min((blockY + 1) * factor, sculpture.height)
                for blockX in 0..<width {
                    let columns = blockX * factor..<min((blockX + 1) * factor, sculpture.width)
                    layer[blockY * width + blockX] = topmost(in: sources, rows: rows, columns: columns, of: sculpture)
                }
            }
            layers.append(layer)
        }
        return try Sculpture(title: sculpture.title, width: width, height: height, layers: layers)
    }

    /// Draws a world from above: every placement's footprint shows its model's top surface, shaded by height.
    /// Each referenced model is resolved once, within the library's own bounded volume budget.
    /// - Parameters:
    ///   - world: The sparse world.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    /// - Returns: The plan, or nil for a world without placements.
    internal static func plan(of world: SculptureWorld, width: Int = width, height: Int = height) throws -> CGImage? {
        guard !world.instances.isEmpty, width > 0, height > 0 else { return nil }
        var surfaces: [String: TopSurface] = [:]
        for id in Set(world.instances.map(\.modelID)).sorted() {
            try Task.checkCancellation()
            surfaces[id] = TopSurface(try world.library.expanded(modelID: id), samples: planSamples)
        }
        let footprints = world.instances.compactMap { instance in
            surfaces[instance.modelID].map { Footprint(instance: instance, surface: $0) }
        }
        guard let first = footprints.first else { return nil }
        var bounds = (minX: first.minX, maxX: first.maxX, minZ: first.minZ, maxZ: first.maxZ)
        var heights = (top: first.top, bottom: first.top)
        for footprint in footprints {
            bounds = (
                min(bounds.minX, footprint.minX), max(bounds.maxX, footprint.maxX),
                min(bounds.minZ, footprint.minZ), max(bounds.maxZ, footprint.maxZ)
            )
            heights = (min(heights.top, footprint.top), max(heights.bottom, footprint.top))
        }
        let margin = 12.0
        let spanX = max(1, bounds.maxX - bounds.minX)
        let spanZ = max(1, bounds.maxZ - bounds.minZ)
        let scale = min((Double(width) - 2 * margin) / spanX, (Double(height) - 2 * margin) / spanZ)
        let offsetX = (Double(width) - spanX * scale) / 2
        let offsetZ = (Double(height) - spanZ * scale) / 2
        var canvas = PlanCanvas(width: width, height: height)
        for (index, footprint) in footprints.enumerated() {
            if index.isMultiple(of: 512) { try Task.checkCancellation() }
            let left = offsetX + (footprint.minX - bounds.minX) * scale
            let top = offsetZ + (footprint.minZ - bounds.minZ) * scale
            canvas.draw(
                footprint,
                left: left,
                top: top,
                right: left + (footprint.maxX - footprint.minX) * scale,
                bottom: top + (footprint.maxZ - footprint.minZ) * scale,
                heights: heights
            )
        }
        return canvas.image()
    }


    // MARK: - Private Methods

    private static func cubes(_ sculpture: Sculpture, camera: SculptureCamera) -> CGImage? {
        SculptureImageRenderer.image(sculpture: sculpture, camera: camera, style: .cubes, width: width, height: height)
    }

    /// Document Y grows downward, so scanning rows first finds the top of the block.
    private static func topmost(
        in layers: [[UInt8]],
        rows: Range<Int>,
        columns: Range<Int>,
        of sculpture: Sculpture
    ) -> UInt8 {
        for y in rows {
            let offset = y * sculpture.width
            for layer in layers {
                for x in columns where layer[offset + x] != Sculpture.empty {
                    return layer[offset + x]
                }
            }
        }
        return Sculpture.empty
    }
}

/// One model's top surface, sampled on a bounded grid of columns seen from above.
private struct TopSurface {
    let width: Int
    let height: Int
    let depth: Int
    let columns: Int
    let rows: Int
    /// The glyph and its row for each sampled column, or nil where the column is empty.
    let samples: [(glyph: UInt8, row: Int)?]
    /// The highest sampled cell, which stands for the whole model when its footprint is only a few pixels wide.
    let representative: (glyph: UInt8, row: Int)?

    init(_ sculpture: Sculpture, samples count: Int) {
        width = sculpture.width
        height = sculpture.height
        depth = sculpture.depth
        columns = min(count, sculpture.width)
        rows = min(count, sculpture.depth)
        var samples: [(glyph: UInt8, row: Int)?] = []
        samples.reserveCapacity(columns * rows)
        var representative: (glyph: UInt8, row: Int)?
        for row in 0..<rows {
            let z = min(sculpture.depth - 1, (2 * row + 1) * sculpture.depth / (2 * rows))
            let layer = sculpture.layers[z]
            for column in 0..<columns {
                let x = min(sculpture.width - 1, (2 * column + 1) * sculpture.width / (2 * columns))
                let top = (0..<sculpture.height).first { layer[$0 * sculpture.width + x] != Sculpture.empty }
                let sample = top.map { (glyph: layer[$0 * sculpture.width + x], row: $0) }
                samples.append(sample)
                if let sample, sample.row < (representative?.row ?? Int.max) { representative = sample }
            }
        }
        self.samples = samples
        self.representative = representative
    }
}

/// A placement's footprint in world X and Z. An odd quarter turn swaps the model's X and Y extents, as the world view
/// does; its top surface is then stretched over the turned footprint, which is close enough for a thumbnail.
private struct Footprint {
    let surface: TopSurface
    let originY: Int64
    let minX: Double
    let maxX: Double
    let minZ: Double
    let maxZ: Double
    /// World Y of the highest sampled cell. Smaller is higher.
    let top: Double

    init(instance: SculptureWorldInstance, surface: TopSurface) {
        let odd = !instance.quarterTurns.isMultiple(of: 2)
        self.surface = surface
        originY = instance.origin.y
        minX = Double(instance.origin.x)
        maxX = minX + Double(odd ? surface.height : surface.width)
        minZ = Double(instance.origin.z)
        maxZ = minZ + Double(surface.depth)
        top = Double(instance.origin.y) + Double(surface.representative?.row ?? surface.height)
    }
}

/// An RGBA pixel buffer with a height buffer, so a higher surface covers a lower one.
private struct PlanCanvas {
    /// The smallest footprint drawn, in pixels, so a model a trillion cells away still shows as a mark.
    static let marker = 4.0

    let width: Int
    let height: Int
    var pixels: [UInt8]
    var depth: [Double]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        depth = [Double](repeating: .infinity, count: width * height)
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<width * height {
            pixels[index * 4] = 17
            pixels[index * 4 + 1] = 22
            pixels[index * 4 + 2] = 26
            pixels[index * 4 + 3] = 255
        }
    }

    mutating func draw(
        _ footprint: Footprint,
        left: Double,
        top: Double,
        right: Double,
        bottom: Double,
        heights: (top: Double, bottom: Double)
    ) {
        let surface = footprint.surface
        guard right - left >= Self.marker, bottom - top >= Self.marker else {
            // Too small to show its surface: one mark in the model's highest color.
            guard let sample = surface.representative else { return }
            let centerX = (left + right) / 2
            let centerY = (top + bottom) / 2
            let half = Self.marker / 2
            for py in span(from: centerY - half, to: centerY + half, limit: height) {
                for px in span(from: centerX - half, to: centerX + half, limit: width) {
                    plot(sample, at: py * width + px, originY: footprint.originY, heights: heights)
                }
            }
            return
        }
        for py in span(from: top, to: bottom, limit: height) {
            let v = min(0.999_999, max(0, (Double(py) + 0.5 - top) / (bottom - top)))
            let row = Int(v * Double(surface.rows))
            for px in span(from: left, to: right, limit: width) {
                let u = min(0.999_999, max(0, (Double(px) + 0.5 - left) / (right - left)))
                guard let sample = surface.samples[row * surface.columns + Int(u * Double(surface.columns))] else {
                    continue
                }
                plot(sample, at: py * width + px, originY: footprint.originY, heights: heights)
            }
        }
    }

    func image() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// The pixel indices a span covers, at least one, clamped to the image.
    private func span(from start: Double, to end: Double, limit: Int) -> Range<Int> {
        let lower = max(0, min(limit - 1, Int(start.rounded(.down))))
        return lower..<max(lower + 1, min(limit, Int(end.rounded(.up))))
    }

    /// Writes one sample unless a higher surface already covers the pixel. Higher surfaces are lighter.
    private mutating func plot(
        _ sample: (glyph: UInt8, row: Int),
        at index: Int,
        originY: Int64,
        heights: (top: Double, bottom: Double)
    ) {
        let level = Double(originY) + Double(sample.row)
        guard level < depth[index] else { return }
        depth[index] = level
        let tint = SculptureVoxelRasterizer.color(for: sample.glyph)
        let shade = 0.55 + 0.45 * (1 - min(1, max(0, (level - heights.top) / max(1, heights.bottom - heights.top))))
        pixels[index * 4] = UInt8(max(0, min(255, tint.red * shade * 255)))
        pixels[index * 4 + 1] = UInt8(max(0, min(255, tint.green * shade * 255)))
        pixels[index * 4 + 2] = UInt8(max(0, min(255, tint.blue * shade * 255)))
    }
}
