import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import RookRendering
import RookSculpture
import Testing

@Suite(.serialized)
struct CubeExportTests {
    @Test func cubePNGAndASCIIRepresentTheSameDocumentWithDifferentImages() throws {
        let sculpture = Sculpture.orb()
        let cubeData = try #require(
            SculptureImageRenderer.png(sculpture: sculpture, camera: SculptureCamera(), style: .cubes)
        )
        let asciiData = try #require(
            SculptureImageRenderer.png(sculpture: sculpture, camera: SculptureCamera(), style: .ascii)
        )
        #expect(cubeData != asciiData)
        let source = try #require(CGImageSourceCreateWithData(cubeData as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 576 && image.height == 648)
        let opaque = try #require(
            SculptureImageRenderer.png(sculpture: sculpture, camera: SculptureCamera(), style: .cubes, opacity: 1)
        )
        #expect(cubeData != opaque)
        #expect(sculpture == Sculpture.orb())
    }

    @Test(arguments: SculptureAnimationFormat.allCases)
    func cubeTurntableEncodesActualGeometryFrames(_ format: SculptureAnimationFormat) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CubeExportTests-\(UUID())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("cube.\(format.rawValue)")
        let configuration = try SculptureTurntableConfiguration(
            durationSeconds: 1,
            framesPerSecond: 5,
            columns: 32,
            rows: 16
        )
        let sculpture = Sculpture.orb()
        _ = try await SculptureAnimationExporter.export(
            sculpture: sculpture,
            camera: SculptureCamera(),
            style: .cubes,
            format: format,
            configuration: configuration,
            destination: destination
        )
        if format == .gif {
            let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
            #expect(CGImageSourceGetCount(source) == 5)
            let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let second = try #require(CGImageSourceCreateImageAtIndex(source, 1, nil))
            #expect(first.width == 288 && first.height == 288)
            #expect(first.dataProvider?.data != second.dataProvider?.data)
        } else {
            let asset = AVURLAsset(url: destination)
            #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
            #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
            #expect(abs(try await asset.load(.duration).seconds - 1) < 0.02)
            let image = try await AVAssetImageGenerator(asset: asset).image(at: .zero).image
            #expect(image.width == 288 && image.height == 288)
        }
        #expect(sculpture == Sculpture.orb())
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [destination.lastPathComponent])
    }
}
