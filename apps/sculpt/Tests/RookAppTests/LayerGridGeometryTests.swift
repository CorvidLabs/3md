import CoreGraphics
import RookSculpture
import Testing

@testable import RookApp

@Test func largeSliceGridFitAndZoomKeepSquareCellsWithinTheirCanvas() {
    let viewport = CGSize(width: 384, height: 448)
    let scales: [CGFloat] = [1, 2, 4]
    for scale in scales {
        let geometry = SliceGridGeometry(width: 64, height: 64, viewport: viewport, zoom: scale)
        #expect(geometry.cellSize == 6 * scale)
        #expect(geometry.gridSize == CGSize(width: 384 * scale, height: 384 * scale))
        #expect(geometry.cell(at: .zero, layer: 63) == SculptureCell(x: 0, y: 0, z: 63))
        #expect(
            geometry.cell(at: CGPoint(x: geometry.gridSize.width - 0.01, y: geometry.gridSize.height - 0.01), layer: 63)
                == SculptureCell(x: 63, y: 63, z: 63)
        )
    }
}

@Test func rectangularSliceGridUsesItsActualAspectRatioAtEveryZoom() {
    let geometry = SliceGridGeometry(width: 64, height: 32, viewport: CGSize(width: 512, height: 384), zoom: 2)
    #expect(geometry.cellSize == 16)
    #expect(geometry.gridSize == CGSize(width: 1_024, height: 512))
    #expect(geometry.cell(at: CGPoint(x: 511, y: 255), layer: 4) == SculptureCell(x: 31, y: 15, z: 4))
}

@Test func maximumVolumeGridZoomCanReachTheLastCellPrecisely() {
    for option in [SliceGridZoom.eightTimes, .sixteenTimes] {
        let geometry = SliceGridGeometry(
            width: 256,
            height: 256,
            viewport: CGSize(width: 384, height: 384),
            zoom: option.scale
        )
        #expect(geometry.cellSize >= 12)
        let point = CGPoint(x: 255.5 * geometry.cellSize, y: 255.5 * geometry.cellSize)
        #expect(geometry.cell(at: point, layer: 255) == SculptureCell(x: 255, y: 255, z: 255))
        #expect(geometry.cell(at: CGPoint(x: geometry.gridSize.width, y: point.y), layer: 255) == nil)
    }
}

@Test func scrollingChangesViewportPositionWithoutChangingLocalCellCoordinates() {
    let geometry = SliceGridGeometry(width: 64, height: 64, viewport: CGSize(width: 384, height: 384), zoom: 4)
    let cellCenter = CGPoint(x: 1_212, y: 972)
    #expect(geometry.cell(at: cellCenter, layer: 8) == SculptureCell(x: 50, y: 40, z: 8))
    let scrollOffset = CGPoint(x: 1_080, y: 840)
    let viewportPosition = CGPoint(x: cellCenter.x - scrollOffset.x, y: cellCenter.y - scrollOffset.y)
    #expect(viewportPosition == CGPoint(x: 132, y: 132))
    // DragGesture is attached to the canvas in .local coordinates, including the scrolled content's origin.
    let canvasPosition = CGPoint(x: viewportPosition.x + scrollOffset.x, y: viewportPosition.y + scrollOffset.y)
    #expect(geometry.cell(at: canvasPosition, layer: 8) == SculptureCell(x: 50, y: 40, z: 8))
}

@Test func gridHitTestingRejectsOutsideNonFiniteAndUnavailableGeometry() {
    let geometry = SliceGridGeometry(width: 64, height: 64, viewport: CGSize(width: 384, height: 384), zoom: 2)
    for point in [
        CGPoint(x: -0.01, y: 0), CGPoint(x: 0, y: -0.01),
        CGPoint(x: 768, y: 0), CGPoint(x: 0, y: 768),
        CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity),
    ] {
        #expect(geometry.cell(at: point, layer: 0) == nil)
    }
    #expect(geometry.cell(at: .zero, layer: -1) == nil)
    let unavailable = SliceGridGeometry(width: 64, height: 64, viewport: .zero, zoom: 4)
    #expect(unavailable.cellSize == 0 && unavailable.gridSize == .zero)
    #expect(unavailable.cell(at: .zero, layer: 0) == nil)
    let nonFinite = SliceGridGeometry(width: 64, height: 64, viewport: CGSize(width: 384, height: 384), zoom: .infinity)
    #expect(nonFinite.cell(at: .zero, layer: 0) == nil)
}
