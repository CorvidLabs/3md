import CoreGraphics
import Foundation
import ImageIO
import RookRendering
import RookSculpture
import Testing

@Suite(.serialized)
struct PreparedVoxelProjectionTests {
    @Test func directExtractionPreservesAllNeighborsMaterialsBoundariesAndStableOrder() throws {
        for dimensions in [(1, 1, 1), (1, 7, 5), (9, 1, 4), (7, 5, 1), (9, 7, 5)] {
            let sculpture = try fixture(width: dimensions.0, height: dimensions.1, depth: dimensions.2)
            let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
            var expected: [SurfaceRecord] = []
            for z in 0..<sculpture.depth {
                for y in 0..<sculpture.height {
                    for x in 0..<sculpture.width {
                        let cell = SculptureCell(x: x, y: y, z: z)
                        let glyph = try #require(sculpture.glyph(at: cell))
                        guard glyph != Sculpture.empty else { continue }
                        for (face, dx, dy, dz) in neighborDirections {
                            let neighbor = SculptureCell(x: x + dx, y: y + dy, z: z + dz)
                            let value = sculpture.glyph(at: neighbor)
                            guard value == nil || value == Sculpture.empty else { continue }
                            expected.append(
                                SurfaceRecord(
                                    cell: cell,
                                    face: face,
                                    glyph: glyph,
                                    adjacent: value == nil ? nil : neighbor
                                )
                            )
                        }
                    }
                }
            }
            #expect(scene.occupiedCount == sculpture.occupiedCount)
            #expect(
                scene.surfaces.map {
                    SurfaceRecord(cell: $0.cell, face: $0.face, glyph: $0.glyph, adjacent: $0.adjacentCell)
                } == expected
            )
        }
    }

    @Test func preparedFramesHaveExactDocumentProjectionAndPixelParityAcrossCameraPoses() throws {
        let sculpture = try fixture(width: 9, height: 7, depth: 5)
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        let poses: [SculptureCamera] = [
            .init(yaw: 0, pitch: 0, zoom: 1), .init(yaw: .pi / 2, pitch: 0, zoom: 1),
            .init(yaw: -.pi / 2, pitch: 0, zoom: 1), .init(yaw: .pi, pitch: 0, zoom: 1),
            .init(yaw: -0.6, pitch: 0.75, zoom: 0.9), .init(yaw: 2.2, pitch: -1.4, zoom: 2),
            .init(yaw: -18, pitch: 1.4, zoom: 0.5), .init(yaw: .nan, pitch: .infinity, zoom: -.infinity),
        ]
        for pose in poses {
            let document = SculptureVoxelProjection.frame(sculpture, camera: pose, width: 320, height: 240)
            let prepared = SculptureVoxelProjection.frame(scene, camera: pose, width: 320, height: 240)
            #expect(!prepared.isOverBudget && !prepared.quads.isEmpty)
            #expect(prepared == document)
            // Hit checks include overlaps and empty background, rather than only face centroids.
            for y in stride(from: 0, to: 240, by: 23) {
                for x in stride(from: 0, to: 320, by: 29) {
                    #expect(
                        prepared.hitTest(x: Double(x), y: Double(y)) == document.hitTest(x: Double(x), y: Double(y))
                    )
                }
            }
            let first = try #require(SculptureVoxelRasterizer.image(document, opacity: 0.8))
            let second = try #require(SculptureVoxelRasterizer.image(prepared, opacity: 0.8))
            #expect(try pixels(first) == pixels(second))
        }
        #expect(
            SculptureVoxelProjection.frame(scene, camera: .init(), width: -1, height: 100_000)
                == SculptureVoxelProjection.frame(sculpture, camera: .init(), width: -1, height: 100_000)
        )
        #expect(scene == (try SculptureVoxelSurfaceExtractor.extract(sculpture)))
    }

    @Test func preparedEmptyAndCancelledFramesNeverPublishGhostsOrPartialPicking() async throws {
        let empty = try Sculpture(title: "Empty", width: 2, height: 1, layers: [[46, 46]])
        let emptyScene = try SculptureVoxelSurfaceExtractor.extract(empty)
        let emptyFrame = SculptureVoxelProjection.frame(emptyScene, camera: .init(), width: 64, height: 64)
        #expect(emptyFrame.quads.isEmpty && !emptyFrame.isOverBudget)
        #expect(emptyFrame.hitTest(x: 32, y: 32) == nil)
        let scene = try SculptureVoxelSurfaceExtractor.extract(fixture(width: 9, height: 7, depth: 5))
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate.stream { break }
            return SculptureVoxelProjection.frame(scene, camera: .init(), width: 320, height: 240)
        }
        task.cancel()
        gate.continuation.finish()
        let cancelled = await task.value
        #expect(cancelled.quads.isEmpty && !cancelled.isOverBudget)
        #expect(cancelled.hitTest(x: 160, y: 120) == nil)
    }

    @Test func cubeAnimationRetainsPerFrameFallbackWhenCompleteSceneExceedsExtractionBudget() async throws {
        // Every checkerboard cell has six exposed faces. A perspective camera
        // can see three even at pitch zero, except cells in the central Y row:
        // its camera lies within their Y slab, so neither Y face points at it.
        // Those grazing cells keep every yaw below the per-frame limit while
        // the complete scene remains just above the extraction limit.
        let width = 68, height = 63, depth = 39
        let layers = (0..<depth).map { z in
            (0..<(width * height)).map { index in
                (index % width + index / width + z).isMultiple(of: 2) ? UInt8(43) : Sculpture.empty
            }
        }
        let sculpture = try Sculpture(title: "Full scene fallback", width: width, height: height, layers: layers)
        #expect(sculpture.occupiedCount * 6 > SculptureVoxelSurfaceExtractor.maximumFaces)
        let centralRowCount = layers.reduce(0) { count, layer in
            count + layer[((height / 2) * width)..<((height / 2 + 1) * width)].filter { $0 != Sculpture.empty }.count
        }
        #expect(centralRowCount > 0)
        #expect(sculpture.occupiedCount * 3 - centralRowCount < SculptureVoxelProjection.maximumQuads)
        #expect(throws: SculptureVoxelSurfaceError.tooManyFaces) {
            _ = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PreparedCubeFallback-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("fallback.gif")
        let configuration = try SculptureTurntableConfiguration(
            durationSeconds: 1,
            framesPerSecond: 5,
            columns: 8,
            rows: 8
        )
        _ = try await SculptureAnimationExporter.export(
            sculpture: sculpture,
            camera: SculptureCamera(yaw: 0, pitch: 0),
            style: .cubes,
            opacity: 0.8,
            format: .gif,
            configuration: configuration,
            destination: output
        )
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == configuration.frameCount)
        for index in 0..<configuration.frameCount {
            let frame = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
            #expect(frame.width == configuration.pixelWidth && frame.height == configuration.pixelHeight)
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any])
            let gif = try #require(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
            #expect(
                abs(try #require(gif[kCGImagePropertyGIFDelayTime as String] as? NSNumber).doubleValue - 0.2)
                    < 0.000_001
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["fallback.gif"])
    }

    @Test func cubeAnimationFallbackStillRefusesAnOverBudgetFrameAndCleansItsStaging() async throws {
        let size = 64
        let layers = (0..<size).map { z in
            (0..<(size * size)).map { index in
                (index % size + index / size + z).isMultiple(of: 2) ? UInt8(35) : Sculpture.empty
            }
        }
        let sculpture = try Sculpture(title: "Frame budget refusal", width: size, height: size, layers: layers)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PreparedCubeRefusal-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        await #expect(throws: SculptureAnimationExportError.frameRenderingFailed) {
            try await SculptureAnimationExporter.export(
                sculpture: sculpture,
                camera: SculptureCamera(yaw: 0.8, pitch: 0.7),
                style: .cubes,
                format: .gif,
                configuration: SculptureTurntableConfiguration(
                    durationSeconds: 1,
                    framesPerSecond: 5,
                    columns: 8,
                    rows: 8
                ),
                destination: folder.appendingPathComponent("refused.gif")
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    private var neighborDirections: [(SculptureVoxelFace, Int, Int, Int)] {
        [
            (.left, -1, 0, 0), (.right, 1, 0, 0), (.top, 0, -1, 0), (.bottom, 0, 1, 0), (.back, 0, 0, -1),
            (.front, 0, 0, 1),
        ]
    }

    private func fixture(width: Int, height: Int, depth: Int) throws -> Sculpture {
        let layers = (0..<depth).map { z in
            (0..<(width * height)).map { index -> UInt8 in
                let x = index % width, y = index / width
                if z == 2 || y == 3 || (x * 7 + y * 3 + z * 5).isMultiple(of: 4) { return Sculpture.empty }
                return Sculpture.palette[(x + y * 2 + z * 3) % Sculpture.palette.count]
            }
        }
        return try Sculpture(title: "Direct neighbor fixture", width: width, height: height, layers: layers)
    }

    private func pixels(_ image: CGImage) throws -> Data {
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
        return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
    }
}

private struct SurfaceRecord: Equatable {
    let cell: SculptureCell
    let face: SculptureVoxelFace
    let glyph: UInt8
    let adjacent: SculptureCell?
}
