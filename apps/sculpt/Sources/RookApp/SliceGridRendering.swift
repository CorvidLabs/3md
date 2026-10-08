import CoreGraphics
import RookSculpture
import SwiftUI

/// Scroll position limits drawing, never the document coordinates used for painting.
internal struct SliceGridVisibleRegion: Equatable {
    let columns: Range<Int>
    let rows: Range<Int>
    var cellCount: Int { columns.count * rows.count }

    init(geometry: SliceGridGeometry, viewport: CGSize, canvasOrigin: CGPoint) {
        guard geometry.cellSize > 0, viewport.width.isFinite, viewport.height.isFinite,
            viewport.width > 0, viewport.height > 0, canvasOrigin.x.isFinite, canvasOrigin.y.isFinite
        else {
            columns = 0..<0
            rows = 0..<0
            return
        }
        let visible = CGRect(origin: CGPoint(x: -canvasOrigin.x, y: -canvasOrigin.y), size: viewport)
            .intersection(CGRect(origin: .zero, size: geometry.gridSize))
        guard !visible.isNull, !visible.isEmpty else {
            columns = 0..<0
            rows = 0..<0
            return
        }
        // One extra cell retains antialiasing and selection strokes across clipped edges.
        let firstColumn = max(0, Int(floor(visible.minX / geometry.cellSize)) - 1)
        let lastColumn = min(geometry.width, Int(ceil(visible.maxX / geometry.cellSize)) + 1)
        let firstRow = max(0, Int(floor(visible.minY / geometry.cellSize)) - 1)
        let lastRow = min(geometry.height, Int(ceil(visible.maxY / geometry.cellSize)) + 1)
        columns = firstColumn..<lastColumn
        rows = firstRow..<lastRow
    }

    func contains(column: Int, row: Int) -> Bool { columns.contains(column) && rows.contains(row) }

    func drawingBounds(geometry: SliceGridGeometry) -> CGRect {
        guard cellCount > 0 else { return .zero }
        return CGRect(
            x: CGFloat(columns.lowerBound) * geometry.cellSize,
            y: CGFloat(rows.lowerBound) * geometry.cellSize,
            width: CGFloat(columns.count) * geometry.cellSize,
            height: CGFloat(rows.count) * geometry.cellSize
        )
    }
}

/// Resolve each material and tint once per draw, rather than laying out a Text for each cell.
internal struct SliceGridGlyphCache {
    private var values: [UInt16: GraphicsContext.ResolvedText] = [:]
    private(set) var resolutionCount = 0

    mutating func text(
        for glyph: UInt8,
        previous: Bool,
        size: CGFloat,
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText {
        let key = UInt16(glyph) * 2 + (previous ? 1 : 0)
        if let existing = values[key] { return existing }
        let color = previous ? Brand.secondary.opacity(0.35) : Brand.ink
        let resolved = context.resolve(
            Text(String(UnicodeScalar(glyph)))
                .font(.system(size: size * 0.65, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        )
        values[key] = resolved
        resolutionCount += 1
        return resolved
    }
}

/// Only the slice bytes and resolved appearance invalidate a thumbnail; other slices do not.
internal struct SliceThumbnailRequest: Equatable, Sendable {
    let glyphs: [UInt8]
    let width: Int
    let height: Int
    let occupiedCount: Int
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let pixelSize: Int

    func image() -> CGImage? {
        guard !Task.isCancelled, (1...Sculpture.maximumDimension).contains(width),
            (1...Sculpture.maximumDimension).contains(height), glyphs.count == width * height,
            (1...256).contains(pixelSize), red.isFinite, green.isFinite, blue.isFinite, alpha.isFinite,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let tint = CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha]),
            let context = CGContext(
                data: nil,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: pixelSize * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        let cellSize = CGFloat(pixelSize) / CGFloat(max(width, height))
        context.translateBy(x: 0, y: CGFloat(pixelSize))
        context.scaleBy(x: 1, y: -1)
        // The resolved SwiftUI components are sRGB; matching both spaces prevents an implicit profile conversion.
        context.setFillColor(tint)
        if occupiedCount > 0 {
            for y in 0..<height {
                guard !Task.isCancelled else { return nil }
                let offset = y * width
                for x in 0..<width where glyphs[offset + x] != Sculpture.empty {
                    context.fill(
                        CGRect(x: CGFloat(x) * cellSize, y: CGFloat(y) * cellSize, width: cellSize, height: cellSize)
                    )
                }
            }
        }
        return Task.isCancelled ? nil : context.makeImage()
    }
}

/// CGImage is immutable after the detached renderer completes.
internal struct SliceThumbnailImage: @unchecked Sendable {
    let request: SliceThumbnailRequest
    let image: CGImage?
}
