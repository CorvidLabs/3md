import Foundation
import RookSculpture
import Testing

@Test func sculptureRoundTripsThroughRealThreeMDParser() throws {
    var sculpture = Sculpture.orb()
    let changed = sculpture.paint(SculptureCell(x: 2, y: 3, z: 4), glyph: 64)
    #expect(changed)
    try sculpture.rename("My \"orb\" \\ studio")
    let data = SculptureCodec.encode(sculpture)
    #expect(String(decoding: data, as: UTF8.self).contains("axis: space"))
    #expect(try SculptureCodec.decode(data) == sculpture)
}

@Test func rejectsOversizedAndUnrelatedDocuments() {
    #expect(throws: SculptureError.oversizedFile) {
        try SculptureCodec.decode(Data(repeating: 35, count: SculptureCodec.maximumBytes + 1))
    }
    #expect(throws: (any Error).self) {
        try SculptureCodec.decode(Data("---\n3md: 1.0\naxis: time\n---\n@plane z=0\n# Planner\n".utf8))
    }
}

@Test func fileSizeGuardAcceptsItsExactBoundaryBeforeValidatingUTF8() {
    // Invalid UTF-8 avoids asking ThreeMD to allocate a 20 MiB malformed document.
    #expect(throws: SculptureError.invalidGrid) {
        try SculptureCodec.decode(Data(repeating: 255, count: SculptureCodec.maximumBytes))
    }
    #expect(throws: SculptureError.oversizedFile) {
        try SculptureCodec.decode(Data(repeating: 255, count: SculptureCodec.maximumBytes + 1))
    }
}

@Test func refusesMalformedDimensionsRowsGlyphsAndDepth() throws {
    let original = String(decoding: SculptureCodec.encode(.blank()), as: UTF8.self)
    let invalid = [
        original.replacingOccurrences(of: "width: 16", with: "width: 999999"),
        original.replacingOccurrences(of: "@plane z=0", with: "@plane z=0.5"),
        original.replacingOccurrences(of: "................", with: "...!............"),
        original.replacingOccurrences(of: "................", with: "..............."),
        original.replacingOccurrences(of: "axis: space", with: "axis: frame"),
        original.replacingOccurrences(of: "```ascii", with: "```markdown"),
    ]
    for source in invalid {
        #expect(throws: (any Error).self) { try SculptureCodec.decode(Data(source.utf8)) }
    }
}

@Test func protectsGridBoundsAndRejectsInvalidGlyphs() {
    var sculpture = Sculpture.blank()
    let changes = [
        sculpture.paint(SculptureCell(x: -1, y: 0, z: 0), glyph: 35),
        sculpture.paint(SculptureCell(x: 16, y: 0, z: 0), glyph: 35),
        sculpture.paint(SculptureCell(x: 0, y: 0, z: 1), glyph: 35),
        sculpture.paint(SculptureCell(x: 0, y: 0, z: 0), glyph: 10),
    ]
    #expect(changes.allSatisfy { !$0 })
    #expect(sculpture.occupiedCount == 0)
}

@Test func duplicatedLayerIsIndependentAndLastLayerIsProtected() throws {
    var sculpture = Sculpture.blank()
    sculpture.paint(SculptureCell(x: 1, y: 2, z: 0), glyph: 64)
    try sculpture.addLayer(after: 0, duplicate: true)
    sculpture.paint(SculptureCell(x: 1, y: 2, z: 1), glyph: 35)
    #expect(sculpture.glyph(at: SculptureCell(x: 1, y: 2, z: 0)) == 64)
    #expect(sculpture.glyph(at: SculptureCell(x: 1, y: 2, z: 1)) == 35)
    try sculpture.removeLayer(at: 1)
    #expect(throws: SculptureError.lastLayer) { try sculpture.removeLayer(at: 0) }
}

@Test func quarterTurnMovesCellAndFourTurnsRestoreLayer() throws {
    var sculpture = Sculpture.blank()
    sculpture.paint(SculptureCell(x: 1, y: 2, z: 0), glyph: 64)
    let original = sculpture
    try sculpture.rotateLayer(at: 0)
    #expect(sculpture.glyph(at: SculptureCell(x: 13, y: 1, z: 0)) == 64)
    for _ in 0..<3 { try sculpture.rotateLayer(at: 0) }
    #expect(sculpture == original)
}

@Test func nearestCellWinsOcclusionAndCanBePicked() throws {
    let sculpture = try Sculpture(title: "Depth", width: 1, height: 1, layers: [[35], [64]])
    let frame = SculptureProjection.frame(sculpture, camera: SculptureCamera(yaw: 0, pitch: 0))
    let visible = try #require(frame.pixels.compactMap { $0 }.first)
    #expect(visible.glyph == 64)
    #expect(visible.cell.z == 1)
    #expect(frame.cell(column: frame.columns / 2, row: frame.rows / 2)?.z == 1)
    #expect(frame.cell(column: -1, row: 0) == nil)
}

@Test func cameraOrbitChangesProjectionAndNonFiniteValuesRemainSafe() throws {
    var sculpture = Sculpture.blank()
    sculpture.paint(SculptureCell(x: 2, y: 3, z: 0), glyph: 35)
    let front = SculptureProjection.frame(sculpture, camera: SculptureCamera(yaw: 0, pitch: 0))
    let side = SculptureProjection.frame(sculpture, camera: SculptureCamera(yaw: 1, pitch: 0.5))
    #expect(front != side)
    let bounded = SculptureProjection.frame(
        sculpture,
        camera: SculptureCamera(yaw: .nan, pitch: .infinity, zoom: -.infinity),
        columns: Int.max,
        rows: Int.min
    )
    #expect(bounded.columns == 160)
    #expect(bounded.rows == 8)
    #expect(bounded.pixels.count == 1280)
}

@Test func emptyProjectionExportsSpacesWithoutInventingCharacters() {
    let frame = SculptureProjection.frame(.blank(), camera: SculptureCamera())
    #expect(frame.pixels.allSatisfy { $0 == nil })
    #expect(frame.text.utf8.allSatisfy { $0 == 32 || $0 == 10 })
}

@Test func titleCannotInjectFrontmatterAndLayerLimitIsEnforced() throws {
    var sculpture = Sculpture.blank()
    #expect(throws: SculptureError.invalidTitle) { try sculpture.rename("Scene\naxis: time") }
    for _ in 1..<Sculpture.maximumDimension { try sculpture.addLayer(after: 0) }
    #expect(throws: SculptureError.tooManyLayers) { try sculpture.addLayer(after: 0) }
    #expect(sculpture.depth == Sculpture.maximumDimension)
}

@Test func maximumTwoHundredFiftySixCubeRoundTripsWithinTwentyMiB() throws {
    let dimension = Sculpture.maximumDimension
    #expect(dimension == 256)
    #expect(SculptureCodec.maximumBytes == 20 * 1_048_576)
    let layer = Array(repeating: UInt8(35), count: dimension * dimension)
    let sculpture = try Sculpture(
        title: "Maximum volume",
        width: dimension,
        height: dimension,
        layers: Array(repeating: layer, count: dimension)
    )
    #expect(sculpture.occupiedCount == 16_777_216)
    let data = SculptureCodec.encode(sculpture)
    #expect(data.count > 16_777_216)
    #expect(data.count < SculptureCodec.maximumBytes)
    #expect(try SculptureCodec.decode(data) == sculpture)
    #expect(sculpture.glyph(at: SculptureCell(x: 255, y: 255, z: 255)) == 35)
}

@Test func dimensionsAboveTwoHundredFiftySixAreRejectedOnEveryAxis() {
    for dimensions in [(257, 1, 1), (1, 257, 1), (1, 1, 257)] {
        #expect(throws: SculptureError.invalidDimensions) {
            try Sculpture(
                title: "Too large",
                width: dimensions.0,
                height: dimensions.1,
                layers: Array(
                    repeating: Array(repeating: Sculpture.empty, count: dimensions.0 * dimensions.1),
                    count: dimensions.2
                )
            )
        }
    }
}

@Test(arguments: [32, 64]) func formerCubeDocumentsRemainCompatible(dimension: Int) throws {
    var sculpture = try Sculpture(
        title: "Original size",
        width: dimension,
        height: dimension,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: dimension * dimension), count: dimension)
    )
    sculpture.paint(SculptureCell(x: dimension - 1, y: dimension - 1, z: dimension - 1), glyph: 64)
    let data = SculptureCodec.encode(sculpture)
    #expect(try SculptureCodec.decode(data) == sculpture)
    #expect(sculpture.occupiedCount == 1)
}

@Test func codecRejectsExcessiveDirectivesBeforeAllocatingThreeMDPlanes() {
    let source =
        String(decoding: SculptureCodec.encode(.blank()), as: UTF8.self)
        + String(repeating: "\n@plane z=0\n```ascii\n.\n```\n", count: Sculpture.maximumDimension)
    #expect(source.utf8.count < SculptureCodec.maximumBytes)
    // Duplicate positions would fail in ThreeMD. The sculpture plane budget is checked first.
    #expect(throws: SculptureError.unsupportedSchema) { try SculptureCodec.decode(Data(source.utf8)) }
}

@Test func codecRejectsExcessiveBlankLinesBeforeThreeMDAllocatesTheirArray() {
    var source = SculptureCodec.encode(.blank())
    source.append(Data(repeating: 10, count: 100_001))
    #expect(source.count < SculptureCodec.maximumBytes)
    // ThreeMD otherwise accepts trailing blank lines after collapsing the plane body.
    #expect(throws: SculptureError.invalidGrid) { try SculptureCodec.decode(source) }
}

@Test func occupiedCountRemainsAccurateAcrossEveryMutationAndValueCopy() throws {
    var sculpture = Sculpture.blank()
    let cell = SculptureCell(x: 2, y: 3, z: 0)
    sculpture.paint(cell, glyph: 35)
    #expect(sculpture.occupiedCount == 1)
    let original = sculpture
    sculpture.paint(cell, glyph: 64)
    #expect(sculpture.occupiedCount == 1)
    let unchanged = sculpture.paint(cell, glyph: 64)
    let outside = sculpture.paint(SculptureCell(x: -1, y: 0, z: 0), glyph: 35)
    let invalid = sculpture.paint(cell, glyph: 10)
    #expect(!unchanged)
    #expect(!outside)
    #expect(!invalid)
    try sculpture.addLayer(after: 0, duplicate: true)
    #expect(sculpture.occupiedCount == 2)
    try sculpture.rotateLayer(at: 1)
    #expect(sculpture.occupiedCount == 2)
    try sculpture.removeLayer(at: 1)
    #expect(sculpture.occupiedCount == 1)
    sculpture.paint(cell, glyph: Sculpture.empty)
    #expect(sculpture.occupiedCount == 0)
    try sculpture.addLayer(after: 0)
    try sculpture.rename("Counted volume")
    #expect(sculpture.occupiedCount == 0)
    #expect(sculpture.occupiedCount == sculpture.layers.joined().reduce(0) { $0 + ($1 == Sculpture.empty ? 0 : 1) })
    #expect(original.occupiedCount == 1)
    #expect(original.glyph(at: cell) == 35)
}

@Test func projectionCanPickTheNearestCellBeyondTheOldDepthLimit() throws {
    var layers = Array(repeating: [UInt8(35)], count: 256)
    layers[255] = [64]
    let sculpture = try Sculpture(title: "Deep volume", width: 1, height: 1, layers: layers)
    let frame = SculptureProjection.frame(sculpture, camera: SculptureCamera(yaw: 0, pitch: 0))
    let visible = try #require(frame.pixels.compactMap { $0 }.first)
    #expect(visible.glyph == 64)
    #expect(visible.cell == SculptureCell(x: 0, y: 0, z: 255))
    #expect(frame.cell(column: frame.columns / 2, row: frame.rows / 2)?.z == 255)
}

@Test func denseSixtyFourVolumeProjectionStaysBoundedAndPicksActualSourceCells() throws {
    let sculpture = try Sculpture(
        title: "Dense projection",
        width: 64,
        height: 64,
        layers: Array(repeating: Array(repeating: UInt8(35), count: 4_096), count: 64)
    )
    let frame = SculptureProjection.frame(sculpture, camera: SculptureCamera(), columns: Int.max, rows: Int.max)
    #expect(frame.columns == 160 && frame.rows == 100)
    #expect(frame.pixels.count == 16_000)
    let visible = frame.pixels.compactMap { $0 }
    #expect(!visible.isEmpty)
    for pixel in visible { #expect(sculpture.glyph(at: pixel.cell) == pixel.glyph) }
    #expect(frame == SculptureProjection.frame(sculpture, camera: SculptureCamera(), columns: 160, rows: 100))
}

@Test func maximumCoordinatesStayEditableAndProjectionCachesFollowLayerChanges() throws {
    var sculpture = try Sculpture(
        title: "High corner",
        width: 256,
        height: 256,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: 65_536), count: 256)
    )
    let corner = SculptureCell(x: 255, y: 255, z: 255)
    let painted = sculpture.paint(corner, glyph: 64)
    #expect(painted)
    #expect(sculpture.occupiedCount == 1)
    let original = sculpture
    let camera = SculptureCamera(yaw: 0, pitch: 0)
    let front = SculptureProjection.frame(sculpture, camera: camera)
    #expect(front.pixels.compactMap { $0 }.map(\.cell) == [corner])
    for cell in [
        SculptureCell(x: 256, y: 255, z: 255), SculptureCell(x: 255, y: 256, z: 255),
        SculptureCell(x: 255, y: 255, z: 256),
    ] {
        let changed = sculpture.paint(cell, glyph: 35)
        #expect(!changed)
        #expect(sculpture.glyph(at: cell) == nil)
    }
    try sculpture.rotateLayer(at: 255)
    let rotated = SculptureCell(x: 0, y: 255, z: 255)
    #expect(sculpture.glyph(at: rotated) == 64)
    #expect(SculptureProjection.frame(sculpture, camera: camera).pixels.compactMap { $0 }.map(\.cell) == [rotated])
    try sculpture.removeLayer(at: 0)
    #expect(sculpture.depth == 255)
    try sculpture.addLayer(after: 254, duplicate: true)
    #expect(sculpture.depth == 256)
    #expect(sculpture.occupiedCount == 2)
    #expect(SculptureProjection.frame(sculpture, camera: camera).pixels.compactMap { $0 }.map(\.cell) == [rotated])
    sculpture.paint(rotated, glyph: Sculpture.empty)
    sculpture.paint(SculptureCell(x: 0, y: 255, z: 254), glyph: Sculpture.empty)
    #expect(sculpture.occupiedCount == 0)
    #expect(SculptureProjection.frame(sculpture, camera: camera).pixels.allSatisfy { $0 == nil })
    #expect(original.occupiedCount == 1)
    #expect(original.glyph(at: corner) == 64)
}

@Test func cancelledSculptureDecodeDoesNotReturnAPartialVolume() async throws {
    let source = SculptureCodec.encode(.orb())
    let barrier = SculptureCancellationBarrier()
    let operation = Task {
        await barrier.wait()
        return try SculptureCodec.decode(source)
    }
    operation.cancel()
    await barrier.release()
    await #expect(throws: CancellationError.self) { try await operation.value }
}

@Test func cancelledASCIIProjectionReturnsABoundedEmptyFrameWithoutPartialPicking() async throws {
    let sculpture = Sculpture.orb()
    let camera = SculptureCamera()
    let complete = SculptureProjection.frame(sculpture, camera: camera, columns: Int.max, rows: Int.min)
    #expect(complete.pixels.contains { $0 != nil })
    let barrier = SculptureCancellationBarrier()
    let operation = Task {
        await barrier.wait()
        return SculptureProjection.frame(sculpture, camera: camera, columns: Int.max, rows: Int.min)
    }
    operation.cancel()
    await barrier.release()
    let frame = await operation.value
    #expect(frame.columns == 160 && frame.rows == 8)
    #expect(frame.pixels.count == 1_280)
    #expect(frame.pixels.allSatisfy { $0 == nil })
    #expect(frame.text.utf8.count == 161 * 8)
    #expect(frame.text.utf8.allSatisfy { $0 == 32 || $0 == 10 })
    #expect(frame.cell(column: 0, row: 0) == nil)
    #expect(frame.cell(column: 80, row: 4) == nil)
    #expect(frame.cell(column: 159, row: 7) == nil)
}

private actor SculptureCancellationBarrier {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}
