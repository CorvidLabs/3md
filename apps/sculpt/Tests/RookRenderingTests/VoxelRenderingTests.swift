import CoreGraphics
import Foundation
import RookRendering
import RookSculpture
import Testing

struct VoxelRenderingTests {
    @Test func excessiveDisconnectedSurfaceReturnsAnExplicitBudgetFailureWithoutPartialPicking() throws {
        let size = 64
        let layers = (0..<size).map { z in
            (0..<(size * size)).map { index in
                (index % size + index / size + z).isMultiple(of: 2) ? UInt8(35) : Sculpture.empty
            }
        }
        let sculpture = try Sculpture(title: "Surface budget", width: size, height: size, layers: layers)
        let frame = SculptureVoxelProjection.frame(
            sculpture,
            camera: SculptureCamera(yaw: 0.8, pitch: 0.7),
            width: 320,
            height: 320
        )
        #expect(frame.isOverBudget)
        #expect(frame.quads.isEmpty)
        #expect(frame.hitTest(x: 160, y: 160) == nil)
        #expect(SculptureVoxelRasterizer.image(frame) == nil)
        #expect(
            !SculptureProjection.frame(sculpture, camera: .init()).text.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
    }

    @Test func frontFacePickingAddsOnlyToAnEmptyInBoundsNeighbor() throws {
        let cell = SculptureCell(x: 1, y: 1, z: 1)
        let frame = try projection(cells: [cell])
        let hit = try #require(frame.hitTest(x: 160, y: 160))
        #expect(hit.cell == cell)
        #expect(hit.face == .front)
        #expect(!hit.isEmpty)
        #expect(hit.paintCell == SculptureCell(x: 1, y: 1, z: 2))
        #expect(frame.quads.count == 1)
        #expect(frame.quads[0].vertices.count == 4)

        let boundary = try projection(cells: [SculptureCell(x: 1, y: 1, z: 2)])
        let boundaryHit = try #require(boundary.hitTest(x: 160, y: 160))
        #expect(boundaryHit.cell.z == 2)
        #expect(boundaryHit.paintCell == nil)
    }

    @Test func joinedCubesCullSharedFacesAndPickTheNearestVisibleCube() throws {
        let rear = SculptureCell(x: 1, y: 1, z: 1)
        let front = SculptureCell(x: 1, y: 1, z: 2)
        let joined = try projection(cells: [rear, front])
        #expect(joined.quads.count == 1)
        #expect(joined.quads[0].cell == front)
        #expect(joined.hitTest(x: 160, y: 160)?.cell == front)

        let separatedFront = SculptureCell(x: 1, y: 1, z: 4)
        let separated = try projection(
            depth: 5,
            cells: [SculptureCell(x: 1, y: 1, z: 0), separatedFront]
        )
        #expect(separated.quads.count == 2)
        #expect(separated.quads.first!.depth < separated.quads.last!.depth)
        #expect(separated.hitTest(x: 160, y: 160)?.cell == separatedFront)
    }

    @Test func cameraRotationChangesThePaintableFaceAndNeighbor() throws {
        let cell = SculptureCell(x: 1, y: 1, z: 1)
        let left = try projection(cells: [cell], camera: SculptureCamera(yaw: .pi / 2, pitch: 0))
        let leftHit = try #require(left.hitTest(x: 160, y: 160))
        #expect(leftHit.face == .left)
        #expect(leftHit.paintCell == SculptureCell(x: 0, y: 1, z: 1))

        let right = try projection(cells: [cell], camera: SculptureCamera(yaw: -.pi / 2, pitch: 0))
        let rightHit = try #require(right.hitTest(x: 160, y: 160))
        #expect(rightHit.face == .right)
        #expect(rightHit.paintCell == SculptureCell(x: 2, y: 1, z: 1))

        let above = try projection(cells: [cell], camera: SculptureCamera(yaw: 0, pitch: 1.4))
        let top = try #require(above.quads.first { $0.face == .top })
        let point = centroid(top)
        let topHit = try #require(above.hitTest(x: point.x, y: point.y))
        #expect(topHit.face == .top)
        #expect(topHit.paintCell == SculptureCell(x: 1, y: 0, z: 1))
    }

    @Test func selectedEmptySliceProvidesRealPickableCellsWithoutInventingCubes() throws {
        let frame = try projection(cells: [], selectedLayer: 1)
        #expect(frame.quads.count == 9)
        #expect(frame.quads.allSatisfy { $0.isEmpty })
        let hit = try #require(frame.hitTest(x: 160, y: 160))
        #expect(hit.isEmpty)
        #expect(hit.face == nil)
        #expect(hit.cell == SculptureCell(x: 1, y: 1, z: 1))
        #expect(hit.paintCell == hit.cell)

        let document = try volume(cells: [])
        let hidden = SculptureVoxelProjection.frame(
            document,
            camera: frontCamera,
            width: 320,
            height: 320,
            selectedLayer: 1,
            showsEmptyCells: false
        )
        #expect(hidden.quads.isEmpty)
        let invalid = SculptureVoxelProjection.frame(
            document,
            camera: frontCamera,
            width: 320,
            height: 320,
            selectedLayer: 3
        )
        #expect(invalid.quads.isEmpty)
    }

    @Test func ghostGridCannotStealAnOccludedCubeHit() throws {
        let front = SculptureCell(x: 1, y: 1, z: 2)
        let behind = try projection(cells: [front], selectedLayer: 1)
        let hit = try #require(behind.hitTest(x: 160, y: 160))
        #expect(hit.cell == front)
        #expect(!hit.isEmpty)

        let nearEmpty = try projection(cells: [SculptureCell(x: 1, y: 1, z: 0)], selectedLayer: 2)
        let nearHit = try #require(nearEmpty.hitTest(x: 160, y: 160))
        #expect(nearHit.isEmpty)
        #expect(nearHit.paintCell == SculptureCell(x: 1, y: 1, z: 2))
    }

    @Test func fullSizeSolidVolumeExposesOnlyItsOuterSurface() throws {
        let size = 64
        let document = try Sculpture(
            title: "Full size solid",
            width: size,
            height: size,
            layers: Array(repeating: Array(repeating: UInt8(35), count: size * size), count: size)
        )
        let frame = SculptureVoxelProjection.frame(document, camera: frontCamera, width: 640, height: 640)
        #expect(frame.quads.count == size * size)
        #expect(frame.quads.allSatisfy { $0.cell.z == size - 1 && $0.face == .front })
        #expect(frame.quads.allSatisfy { $0.adjacentCell == nil })
        #expect(frame.hitTest(x: 320, y: 320)?.cell.z == size - 1)
    }

    @Test func rasterOutputHasGenuineTranslucentFacesAndOptionalClearBackground() throws {
        let frame = try projection(cells: [SculptureCell(x: 1, y: 1, z: 1)])
        let clear = try #require(SculptureVoxelRasterizer.image(frame, opacity: 0.35, transparentBackground: true))
        #expect(clear.width == 320 && clear.height == 320)
        let centerAlpha = try alpha(clear, x: 160, y: 160)
        #expect((88...91).contains(centerAlpha))
        #expect(try alpha(clear, x: 0, y: 0) == 0)

        let solid = try #require(SculptureVoxelRasterizer.image(frame, opacity: 1, transparentBackground: true))
        #expect(try alpha(solid, x: 160, y: 160) == 255)
        let background = try #require(SculptureVoxelRasterizer.image(frame))
        #expect(try alpha(background, x: 0, y: 0) == 255)
    }

    @Test func projectionRejectsInvalidHitCoordinatesAndNormalizesNonfiniteCamera() throws {
        let document = try volume(cells: [SculptureCell(x: 1, y: 1, z: 1)])
        let frame = SculptureVoxelProjection.frame(
            document,
            camera: SculptureCamera(yaw: .nan, pitch: .infinity, zoom: -.infinity),
            width: -1,
            height: 100_000
        )
        #expect(frame.width == 64 && frame.height == 2_048)
        #expect(frame == SculptureVoxelProjection.frame(document, camera: frontCamera, width: 64, height: 2_048))
        #expect(frame.quads.flatMap(\.vertices).allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.depth.isFinite })
        #expect(frame.hitTest(x: .nan, y: 0) == nil)
        #expect(frame.hitTest(x: 0, y: .infinity) == nil)
        #expect(frame.hitTest(x: -1, y: 0) == nil)
        #expect(frame.hitTest(x: Double(frame.width), y: 0) == nil)
    }

    @Test func cancelledRenderDoesNotPublishPartialGeometryOrImage() async throws {
        let document = try volume(cells: [SculptureCell(x: 1, y: 1, z: 1)])
        let complete = SculptureVoxelProjection.frame(document, camera: frontCamera, width: 320, height: 320)
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate.stream { break }
            let frame = SculptureVoxelProjection.frame(document, camera: frontCamera, width: 320, height: 320)
            return frame.quads.isEmpty && SculptureVoxelRasterizer.image(complete) == nil
        }
        task.cancel()
        gate.continuation.finish()
        #expect(await task.value)
    }

    private var frontCamera: SculptureCamera { SculptureCamera(yaw: 0, pitch: 0, zoom: 1) }

    private func volume(depth: Int = 3, cells: [SculptureCell]) throws -> Sculpture {
        var sculpture = try Sculpture(
            title: "Picking fixture",
            width: 3,
            height: 3,
            layers: Array(repeating: Array(repeating: Sculpture.empty, count: 9), count: depth)
        )
        for cell in cells {
            let changed = sculpture.paint(cell, glyph: 35)
            try #require(changed)
        }
        return sculpture
    }

    private func projection(
        depth: Int = 3,
        cells: [SculptureCell],
        camera: SculptureCamera? = nil,
        selectedLayer: Int? = nil
    ) throws -> SculptureVoxelFrame {
        SculptureVoxelProjection.frame(
            try volume(depth: depth, cells: cells),
            camera: camera ?? frontCamera,
            width: 320,
            height: 320,
            selectedLayer: selectedLayer
        )
    }

    private func centroid(_ quad: SculptureVoxelQuad) -> (x: Double, y: Double) {
        (quad.vertices.reduce(0) { $0 + $1.x } / 4, quad.vertices.reduce(0) { $0 + $1.y } / 4)
    }

    private func alpha(_ image: CGImage, x: Int, y: Int) throws -> Int {
        let context = try #require(
            CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Int(bytes[(y * image.width + x) * 4 + 3])
    }
}
