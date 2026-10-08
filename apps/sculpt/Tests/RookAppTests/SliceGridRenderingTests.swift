import CoreGraphics
import Foundation
import RookSculpture
import Testing

@testable import RookApp

@Test func fittedLargeSliceKeepsEveryCellAndRectangularPaddingDoesNotClipRows() {
    let square = SliceGridGeometry(width: 256, height: 256, viewport: CGSize(width: 384, height: 448), zoom: 1)
    let fitted = SliceGridVisibleRegion(
        geometry: square,
        viewport: CGSize(width: 384, height: 448),
        canvasOrigin: .zero
    )
    #expect(fitted.columns == 0..<256 && fitted.rows == 0..<256)
    #expect(fitted.cellCount == 65_536)
    let rectangular = SliceGridGeometry(width: 192, height: 64, viewport: CGSize(width: 576, height: 480), zoom: 1)
    let centered = SliceGridVisibleRegion(
        geometry: rectangular,
        viewport: CGSize(width: 576, height: 480),
        canvasOrigin: CGPoint(x: 0, y: 144)
    )
    #expect(centered.columns == 0..<192 && centered.rows == 0..<64)
}

@Test func zoomedSliceDrawsTheVisibleNeighborhoodAndKeepsTheLastCellReachable() {
    let viewport = CGSize(width: 384, height: 384)
    let geometry = SliceGridGeometry(width: 256, height: 256, viewport: viewport, zoom: 16)
    let middle = SliceGridVisibleRegion(
        geometry: geometry,
        viewport: viewport,
        canvasOrigin: CGPoint(x: -3_072, y: -3_072)
    )
    #expect(middle.columns == 127..<145 && middle.rows == 127..<145)
    #expect(middle.cellCount == 324)
    #expect(middle.drawingBounds(geometry: geometry) == CGRect(x: 3_048, y: 3_048, width: 432, height: 432))
    #expect(middle.drawingBounds(geometry: geometry).width < geometry.gridSize.width / 10)
    let end = SliceGridVisibleRegion(
        geometry: geometry,
        viewport: viewport,
        canvasOrigin: CGPoint(x: -5_760, y: -5_760)
    )
    #expect(end.columns == 239..<256 && end.rows == 239..<256)
    #expect(end.contains(column: 255, row: 255))
    #expect(end.drawingBounds(geometry: geometry).maxX == geometry.gridSize.width)
    #expect(end.drawingBounds(geometry: geometry).maxY == geometry.gridSize.height)
    let canvasPoint = CGPoint(x: 255.5 * geometry.cellSize, y: 255.5 * geometry.cellSize)
    #expect(geometry.cell(at: canvasPoint, layer: 255) == SculptureCell(x: 255, y: 255, z: 255))
    // Culling affects draws only: the drag still uses the same full-precision local point.
    let viewportPoint = CGPoint(x: canvasPoint.x - 5_760, y: canvasPoint.y - 5_760)
    #expect(viewportPoint == CGPoint(x: 372, y: 372))
}

@Test func fractionalScrollEdgesHaveAnAntialiasingFringeAndInvalidRegionsStayEmpty() {
    let viewport = CGSize(width: 384, height: 384)
    let geometry = SliceGridGeometry(width: 256, height: 256, viewport: viewport, zoom: 16)
    let clipped = SliceGridVisibleRegion(
        geometry: geometry,
        viewport: viewport,
        canvasOrigin: CGPoint(x: -3_011.75, y: -3_011.75)
    )
    #expect(clipped.columns == 124..<143 && clipped.rows == 124..<143)
    for origin in [CGPoint(x: 7_000, y: 0), CGPoint(x: -7_000, y: 0), CGPoint(x: CGFloat.nan, y: 0)] {
        let region = SliceGridVisibleRegion(geometry: geometry, viewport: viewport, canvasOrigin: origin)
        #expect(region.cellCount == 0)
    }
    let noViewport = SliceGridVisibleRegion(geometry: geometry, viewport: .zero, canvasOrigin: .zero)
    #expect(noViewport.cellCount == 0)
}

@Test func thumbnailCacheKeyIgnoresOtherSliceEditsAndInvalidatesForItsOwnPixelsAndAppearance() throws {
    var sculpture = try Sculpture(
        title: "Thumbnail keys",
        width: 2,
        height: 2,
        layers: [Array("#...".utf8), Array("....".utf8)]
    )
    let before = thumbnailRequest(sculpture, layer: 0)
    sculpture.paint(SculptureCell(x: 1, y: 1, z: 1), glyph: 64)
    #expect(thumbnailRequest(sculpture, layer: 0) == before)
    sculpture.paint(SculptureCell(x: 1, y: 1, z: 0), glyph: 35)
    #expect(thumbnailRequest(sculpture, layer: 0) != before)
    let dark = thumbnailRequest(sculpture, layer: 0, red: 0.3, green: 0.8)
    #expect(dark != thumbnailRequest(sculpture, layer: 0))
    let lightPixels = try #require(thumbnailRequest(sculpture, layer: 0).image()?.dataProvider?.data)
    let darkPixels = try #require(dark.image()?.dataProvider?.data)
    #expect(lightPixels as Data != darkPixels as Data)
}

@Test func thumbnailPixelsPreserveRectangularEmptyPaddingAndMaterialTint() throws {
    let sculpture = try Sculpture(title: "Thumbnail pixels", width: 2, height: 1, layers: [Array("#.".utf8)])
    let image = try #require(thumbnailRequest(sculpture, layer: 0).image())
    #expect(image.width == 16 && image.height == 16)
    #expect(image.colorSpace?.name == CGColorSpace.sRGB)
    let data = try #require(image.dataProvider?.data)
    let bytes = data as Data
    let alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
    #expect(alpha.filter { $0 > 0 }.count == 64)
    #expect(alpha.filter { $0 == 0 }.count == 192)
    let first = try #require(alpha.firstIndex(where: { $0 > 0 })) * 4
    #expect(abs(Int(bytes[first]) - 204) <= 1)
    #expect(abs(Int(bytes[first + 1]) - 51) <= 1)
    #expect(bytes[first + 2] == 0)
    #expect(abs(Int(bytes[first + 3]) - 204) <= 1)
    let transparent = try Sculpture(title: "Empty thumbnail", width: 2, height: 1, layers: [Array("..".utf8)])
    let emptyImage = try #require(thumbnailRequest(transparent, layer: 0).image())
    let emptyData = try #require(emptyImage.dataProvider?.data)
    #expect((emptyData as Data).allSatisfy { $0 == 0 })
}

@MainActor @Test func canceledThumbnailPreparationDoesNotPublishPixels() async throws {
    let sculpture = Sculpture.orb()
    let request = thumbnailRequest(sculpture, layer: 0)
    let worker = Task { SliceThumbnailImage(request: request, image: request.image()) }
    worker.cancel()
    let result = await worker.value
    #expect(result.image == nil)
}

@Test func thumbnailRowsMatchTheTopLeftOriginOfTheEditableSlice() throws {
    for (glyphs, expectedRow) in [("#.......", 0), ("......#.", 12)] {
        let sculpture = try Sculpture(
            title: "Asymmetric slice",
            width: 2,
            height: 4,
            layers: [Array(glyphs.utf8)]
        )
        let image = try #require(thumbnailRequest(sculpture, layer: 0).image())
        let bytes = try #require(image.dataProvider?.data) as Data
        for y in 0..<16 {
            for x in 0..<16 {
                let expected = (expectedRow..<(expectedRow + 4)).contains(y) && x < 4
                #expect((bytes[y * image.bytesPerRow + x * 4 + 3] > 0) == expected)
            }
        }
    }
}

@Test func perSliceOccupancyRemainsCorrectAcrossPaletteEditsRotationDuplicationAndStorage() throws {
    var sculpture = try Sculpture(
        title: "Cached slice counts",
        width: 2,
        height: 2,
        layers: [Array("#...".utf8), Array(".@@.".utf8)]
    )
    #expect(sculpture.occupiedCount(inLayer: 0) == 1)
    #expect(sculpture.occupiedCount(inLayer: 1) == 2)
    #expect(sculpture.occupiedCount(inLayer: -1) == 0 && sculpture.occupiedCount(inLayer: 2) == 0)
    sculpture.paint(SculptureCell(x: 0, y: 0, z: 0), glyph: 64)
    #expect(sculpture.occupiedCount(inLayer: 0) == 1)
    sculpture.paint(SculptureCell(x: 1, y: 1, z: 0), glyph: 35)
    #expect(sculpture.occupiedCount(inLayer: 0) == 2)
    try sculpture.rotateLayer(at: 0)
    try sculpture.addLayer(after: 0, duplicate: true)
    #expect((0..<sculpture.depth).map { sculpture.occupiedCount(inLayer: $0) } == [2, 2, 2])
    try sculpture.removeLayer(at: 1)
    sculpture.paint(SculptureCell(x: 1, y: 0, z: 0), glyph: Sculpture.empty)
    #expect(sculpture.occupiedCount(inLayer: 0) == 1 && sculpture.occupiedCount(inLayer: 1) == 2)
    for format in [SculptureStorageFormat.readable, .compact] {
        let decoded = try SculptureDocumentCodec.decode(SculptureDocumentCodec.encode(sculpture, format: format))
        for layer in decoded.layers.indices {
            #expect(
                decoded.occupiedCount(inLayer: layer) == decoded.layers[layer].filter { $0 != Sculpture.empty }.count
            )
        }
    }
}

@MainActor @Test func scrolledLastCellStrokeStillHasOneExactUndoAndPreviousSliceBytesStayUnchanged() throws {
    let workspace = SculptureWorkspace()
    let plane = [UInt8](repeating: Sculpture.empty, count: 256 * 256)
    var original = try Sculpture(title: "Last-cell stroke", width: 256, height: 256, layers: [plane, plane])
    original.paint(SculptureCell(x: 255, y: 255, z: 0), glyph: 64)
    workspace.replace(with: original, opened: true)
    workspace.layer = 1
    let geometry = SliceGridGeometry(width: 256, height: 256, viewport: CGSize(width: 384, height: 384), zoom: 16)
    let first = try #require(
        geometry.cell(at: CGPoint(x: 253.5 * geometry.cellSize, y: 255.5 * geometry.cellSize), layer: 1)
    )
    let last = try #require(
        geometry.cell(at: CGPoint(x: 255.5 * geometry.cellSize, y: 255.5 * geometry.cellSize), layer: 1)
    )
    workspace.paint(first, start: true)
    workspace.paint(last, start: false)
    workspace.endStroke()
    #expect(workspace.sculpture.occupiedCount(inLayer: 1) == 3)
    #expect(workspace.sculpture.layers[0] == original.layers[0])
    workspace.undo()
    #expect(workspace.sculpture == original && !workspace.isDirty)
    workspace.redo()
    #expect(workspace.sculpture.occupiedCount(inLayer: 1) == 3)
}

private func thumbnailRequest(
    _ sculpture: Sculpture,
    layer: Int,
    red: Double = 1,
    green: Double = 0.25
) -> SliceThumbnailRequest {
    SliceThumbnailRequest(
        glyphs: sculpture.layers[layer],
        width: sculpture.width,
        height: sculpture.height,
        occupiedCount: sculpture.occupiedCount(inLayer: layer),
        red: red,
        green: green,
        blue: 0,
        alpha: 0.8,
        pixelSize: 16
    )
}
