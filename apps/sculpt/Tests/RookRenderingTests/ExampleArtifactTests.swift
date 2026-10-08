import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import RookRendering
import RookSculpture
import Testing

@Suite(.serialized)
struct ExampleArtifactTests {
    @Test func galleryManifestMatchesAllPublishedFilesAndDownloadLinks() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples", isDirectory: true)
        let manifest = try JSONDecoder().decode(
            ExampleManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        )
        let readme = try String(contentsOf: directory.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(manifest.schema == "sculpt-examples-1")
        #expect(manifest.columns == 64 && manifest.rows == 36)
        #expect(manifest.pixelWidth == 576 && manifest.pixelHeight == 648)
        #expect(manifest.durationSeconds == 4 && manifest.framesPerSecond == 10)
        #expect(manifest.examples.count == SculptureExamples.all.count)
        #expect(Set(manifest.examples.map(\.id)) == Set(SculptureExamples.all.map(\.id)))
        for entry in manifest.examples {
            let example = try catalogExample(entry.id)
            #expect(entry.title == example.title)
            #expect(entry.occupiedCells == example.sculpture.occupiedCount)
            #expect(entry.renderStyle == (example.sculpture.width >= 64 ? "cubes" : "ascii"))
            #expect(Set(entry.files.keys) == Set(["3md", "png", "gif", "mp4", "obj"]))
            for (format, bytes) in entry.files {
                let file = artifact(example, format)
                #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == bytes)
                #expect(readme.contains("\(entry.id).\(format)"))
            }
        }
    }

    @Test(arguments: SculptureExamples.all.map(\.id))
    func everyExampleHasFiveCompleteArtifacts(_ id: String) throws {
        let example = try catalogExample(id)
        for format in ["3md", "png", "gif", "mp4", "obj"] {
            let file = artifact(example, format)
            let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            #expect(attributes.isRegularFile == true)
            #expect((attributes.fileSize ?? 0) > 0)
            let limit = format == "3md" ? SculptureCodec.maximumBytes : 16 * 1_024 * 1_024
            #expect((attributes.fileSize ?? 0) < limit)
        }
        #expect(try SculptureCodec.decode(Data(contentsOf: artifact(example, "3md"))) == example.sculpture)
    }

    @Test(arguments: SculptureExamples.all.map(\.id))
    func everyPNGDecodesAtThePublishedSizeWithVisibleGeometry(_ id: String) throws {
        let example = try catalogExample(id)
        let source = try #require(CGImageSourceCreateWithURL(artifact(example, "png") as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 1)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 576)
        #expect(image.height == 648)
        #expect(try visibleCharacterPixels(image) > 100)
    }

    @Test(arguments: SculptureExamples.all.map(\.id))
    func everyGIFLoopsForFourSecondsWithFortyTimedFrames(_ id: String) throws {
        let example = try catalogExample(id)
        let source = try #require(CGImageSourceCreateWithURL(artifact(example, "gif") as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 40)
        let properties = try #require(CGImageSourceCopyProperties(source, nil) as? [String: Any])
        let gif = try #require(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
        #expect((gif[kCGImagePropertyGIFLoopCount as String] as? NSNumber)?.intValue == 0)
        var duration = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any])
            let timing = try #require(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
            let delay = try #require(timing[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber).doubleValue
            #expect(abs(delay - 0.1) < 0.000_001)
            duration += delay
        }
        #expect(abs(duration - 4) < 0.000_001)
        for index in [0, 11, 23] {
            let image = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
            #expect(image.width == 576)
            #expect(image.height == 648)
            #expect(try visibleCharacterPixels(image) > 100)
        }
    }

    @Test(arguments: SculptureExamples.all.map(\.id))
    func everyMP4HasOneSilentFourSecondVideoTrackAndDecodableFrames(_ id: String) async throws {
        let example = try catalogExample(id)
        let asset = AVURLAsset(url: artifact(example, "mp4"))
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 4) < 0.02)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        let track = try #require(tracks.first)
        let size = try await track.load(.naturalSize)
        #expect(Int(size.width) == 576)
        #expect(Int(size.height) == 648)
        let frameRate = try await track.load(.nominalFrameRate)
        #expect(abs(frameRate - 10) < 0.01)
        let images = AVAssetImageGenerator(asset: asset)
        images.requestedTimeToleranceBefore = .zero
        images.requestedTimeToleranceAfter = .zero
        for seconds in [0.0, 1.1, 2.3] {
            let result = try await images.image(at: CMTime(seconds: seconds, preferredTimescale: 10))
            #expect(abs(result.actualTime.seconds - seconds) < 0.001)
            #expect(result.image.width == 576)
            #expect(result.image.height == 648)
            #expect(try visibleCharacterPixels(result.image) > 100)
        }
    }

    @Test(arguments: SculptureExamples.all.map(\.id))
    func everyOBJContainsBoundedOutwardFacingVoxelGeometry(_ id: String) throws {
        let example = try catalogExample(id)
        let data = try Data(contentsOf: artifact(example, "obj"))
        let text = try #require(String(data: data, encoding: .utf8))
        var vertices: [SIMD3<Double>] = []
        var normals: [SIMD3<Double>] = []
        var faces: [[Int]] = []
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ")
            if fields.first == "v" || fields.first == "vn" {
                try #require(fields.count == 4)
                let values = try fields.dropFirst().map { try #require(Double($0)) }
                let vector = SIMD3(values[0], values[1], values[2])
                if fields.first == "vn" {
                    normals.append(vector)
                } else {
                    #expect(abs(vector.x) <= Double(example.sculpture.width) / 2)
                    #expect(abs(vector.y) <= Double(example.sculpture.height) / 2)
                    #expect(abs(vector.z) <= Double(example.sculpture.depth) / 2)
                    vertices.append(vector)
                }
            } else if fields.first == "f" {
                try #require(fields.count == 5)
                let references = try fields.dropFirst().map { field -> (Int, Int) in
                    let indices = field.components(separatedBy: "//")
                    try #require(indices.count == 2)
                    return (try #require(Int(indices[0])), try #require(Int(indices[1])))
                }
                try #require(
                    references.allSatisfy { $0.0 > 0 && $0.0 <= vertices.count && $0.1 > 0 && $0.1 <= normals.count }
                )
                #expect(Set(references.map(\.0)).count == 4)
                #expect(Set(references.map(\.1)).count == 1)
                let a = vertices[references[0].0 - 1]
                let ab = vertices[references[1].0 - 1] - a
                let ac = vertices[references[2].0 - 1] - a
                let cross = SIMD3(ab.y * ac.z - ab.z * ac.y, ab.z * ac.x - ab.x * ac.z, ab.x * ac.y - ab.y * ac.x)
                let normal = normals[references[0].1 - 1]
                #expect(cross.x * normal.x + cross.y * normal.y + cross.z * normal.z > 0)
                faces.append(references.map(\.0))
            }
        }
        #expect(vertices.count > 8)
        #expect(normals.count == 6)
        #expect(faces.count > 6)
        #expect(Set(faces).count == faces.count)
        #expect(text.contains("# \(example.title)\n"))
        #expect(data == (try SculptureOBJExporter.data(for: example.sculpture)))
    }

    @Test func blockhavenManifestMatchesSelfContainedSourcesCompactVolumeAndAllDownloadLinks() throws {
        let directory = blockhavenDirectory()
        let manifest = try JSONDecoder().decode(
            BlockhavenManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        )
        let readme = try String(contentsOf: directory.appendingPathComponent("README.md"), encoding: .utf8)
        let composition = try SculptureCompositionCodec.decode(
            Data(contentsOf: directory.appendingPathComponent("blockhaven.3md"))
        )
        let world = try SculptureWorldCodec.decode(
            Data(contentsOf: directory.appendingPathComponent("blockhaven-world.3md"))
        )
        let compactData = try Data(contentsOf: directory.appendingPathComponent("blockhaven.3mdb"))
        let volume = try SculptureDocumentCodec.decode(compactData)
        #expect(manifest.schema == "sculpt-blockhaven-example-1")
        #expect(manifest.title == volume.title && manifest.title.contains("Blockhaven"))
        #expect(manifest.width == 192 && manifest.height == 64 && manifest.depth == 192)
        #expect(manifest.modelCount == 37 && manifest.instanceCount == 36)
        #expect(manifest.modelCount == composition.models.count && manifest.instanceCount == world.instances.count)
        #expect(manifest.occupiedCells == volume.occupiedCount && volume.occupiedCount > 100_000)
        #expect(SculptureDocumentCodec.format(of: compactData) == .compact)
        #expect(volume == (try composition.expanded()))
        #expect(composition == (try SculptureBlockWorldExamples.composition()))
        #expect(world == (try SculptureBlockWorldExamples.world()))
        #expect(world.library == composition)
        #expect(manifest.renderStyle == "cubes" && manifest.opacity == 0.8)
        #expect(manifest.pngWidth == 1152 && manifest.pngHeight == 1296)
        #expect(manifest.videoWidth == 576 && manifest.videoHeight == 648)
        #expect(manifest.durationSeconds == 4 && manifest.framesPerSecond == 10 && manifest.frameCount == 40)
        let names = Set([
            "blockhaven.3md", "blockhaven-world.3md", "blockhaven.3mdb", "blockhaven.png", "blockhaven.gif",
            "blockhaven.mp4", "blockhaven.obj",
        ])
        #expect(Set(manifest.files.keys) == names)
        for (name, bytes) in manifest.files {
            let file = directory.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            #expect(values.isRegularFile == true && values.isSymbolicLink != true)
            #expect(values.fileSize == bytes && bytes > 0)
            #expect(readme.contains("(\(name))"))
        }
        #expect(readme.contains("(manifest.json)"))
    }

    @Test func blockhavenPNGAndLoopingGIFDecodeWithVisibleChangingLandscapeAndPublishedTiming() throws {
        let directory = blockhavenDirectory()
        let pngSource = try #require(
            CGImageSourceCreateWithURL(directory.appendingPathComponent("blockhaven.png") as CFURL, nil)
        )
        #expect(CGImageSourceGetCount(pngSource) == 1)
        let png = try #require(CGImageSourceCreateImageAtIndex(pngSource, 0, nil))
        #expect(png.width == 1152 && png.height == 1296)
        #expect(try visibleCharacterPixels(png) > 10_000)
        let gifSource = try #require(
            CGImageSourceCreateWithURL(directory.appendingPathComponent("blockhaven.gif") as CFURL, nil)
        )
        #expect(CGImageSourceGetCount(gifSource) == 40)
        let properties = try #require(CGImageSourceCopyProperties(gifSource, nil) as? [String: Any])
        let gif = try #require(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
        #expect((gif[kCGImagePropertyGIFLoopCount as String] as? NSNumber)?.intValue == 0)
        var duration = 0.0
        for index in 0..<CGImageSourceGetCount(gifSource) {
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(gifSource, index, nil) as? [String: Any])
            let timing = try #require(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
            let delay = try #require(timing[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber).doubleValue
            #expect(abs(delay - 0.1) < 0.000_001)
            duration += delay
        }
        #expect(abs(duration - 4) < 0.000_001)
        var frames = Set<Data>()
        for index in [0, 13, 27] {
            let image = try #require(CGImageSourceCreateImageAtIndex(gifSource, index, nil))
            #expect(image.width == 576 && image.height == 648)
            #expect(try visibleCharacterPixels(image) > 1_000)
            frames.insert(try #require(image.dataProvider?.data) as Data)
        }
        #expect(frames.count == 3)
    }

    @Test func blockhavenVideoHasThePublishedSilentTimingAndDecodableLandscape() async throws {
        let asset = AVURLAsset(url: blockhavenDirectory().appendingPathComponent("blockhaven.mp4"))
        #expect(abs(try await asset.load(.duration).seconds - 4) < 0.02)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        let track = try #require(tracks.first)
        let size = try await track.load(.naturalSize)
        #expect(Int(size.width) == 576 && Int(size.height) == 648)
        #expect(abs(try await track.load(.nominalFrameRate) - 10) < 0.01)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for seconds in [0.0, 1.3, 2.7] {
            let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 10))
            #expect(abs(result.actualTime.seconds - seconds) < 0.001)
            #expect(result.image.width == 576 && result.image.height == 648)
            #expect(try visibleCharacterPixels(result.image) > 1_000)
        }
    }

    @Test func blockhavenOBJHasEveryExteriorFaceWithCorrectBoundsMaterialsAndOutwardWinding() throws {
        let directory = blockhavenDirectory()
        let source = try SculptureDocumentCodec.decode(
            Data(contentsOf: directory.appendingPathComponent("blockhaven.3mdb"))
        )
        let scene = try SculptureVoxelSurfaceExtractor.extract(source)
        let text = try String(contentsOf: directory.appendingPathComponent("blockhaven.obj"), encoding: .utf8)
        var vertices: [SIMD3<Double>] = []
        var normals: [SIMD3<Double>] = []
        var surfaces = Set<String>()
        var glyph: UInt8?
        var count = 0
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ")
            if fields.first == "v" || fields.first == "vn" {
                try #require(fields.count == 4)
                let values = try fields.dropFirst().map { try #require(Double($0)) }
                let point = SIMD3(values[0], values[1], values[2])
                if fields.first == "vn" {
                    normals.append(point)
                } else {
                    #expect(
                        abs(point.x) <= Double(source.width) / 2 && abs(point.y) <= Double(source.height) / 2
                            && abs(point.z) <= Double(source.depth) / 2
                    )
                    vertices.append(point)
                }
            } else if fields.first == "g" {
                try #require(fields.count == 2)
                glyph = UInt8(fields[1].replacingOccurrences(of: "glyph_", with: ""))
                #expect(Sculpture.palette.contains(try #require(glyph)))
            } else if fields.first == "f" {
                try #require(fields.count == 5)
                let references = try fields.dropFirst().map { field -> (Int, Int) in
                    let indices = field.components(separatedBy: "//")
                    try #require(indices.count == 2)
                    let vertex = try #require(Int(indices[0]))
                    let normal = try #require(Int(indices[1]))
                    try #require((1...vertices.count).contains(vertex) && (1...normals.count).contains(normal))
                    return (vertex, normal)
                }
                let a = vertices[references[0].0 - 1]
                let ab = vertices[references[1].0 - 1] - a
                let ac = vertices[references[2].0 - 1] - a
                let cross = SIMD3(ab.y * ac.z - ab.z * ac.y, ab.z * ac.x - ab.x * ac.z, ab.x * ac.y - ab.y * ac.x)
                let normal = normals[references[0].1 - 1]
                #expect(cross.x * normal.x + cross.y * normal.y + cross.z * normal.z > 0)
                let center = references.reduce(SIMD3<Double>(repeating: 0)) { $0 + vertices[$1.0 - 1] } / 4
                let interior = center - normal / 2
                let cell = SculptureCell(
                    x: Int(floor(interior.x + Double(source.width) / 2)),
                    y: Int(floor(Double(source.height) / 2 - interior.y)),
                    z: Int(floor(interior.z + Double(source.depth) / 2))
                )
                #expect(source.glyph(at: cell) == glyph)
                let neighbor = SculptureCell(
                    x: cell.x + Int(normal.x),
                    y: cell.y - Int(normal.y),
                    z: cell.z + Int(normal.z)
                )
                #expect(source.glyph(at: neighbor) == nil || source.glyph(at: neighbor) == Sculpture.empty)
                #expect(surfaces.insert("\(cell.x),\(cell.y),\(cell.z):\(references[0].1)").inserted)
                count += 1
            }
        }
        #expect(normals.count == 6)
        #expect(count == scene.surfaces.count && count > 1_000 && count <= SculptureOBJExporter.maximumFaces)
        #expect(text.contains("# \(source.title)\n"))
    }

    private func blockhavenDirectory() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Examples/Blockhaven", isDirectory: true)
    }

    private func catalogExample(_ id: String) throws -> SculptureExample {
        try #require(SculptureExamples.all.first { $0.id == id })
    }

    private func artifact(_ example: SculptureExample, _ format: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/\(example.id).\(format)")
    }

    private func visibleCharacterPixels(_ image: CGImage) throws -> Int {
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
        var count = 0
        for pixel in 0..<image.width * image.height {
            let offset = pixel * 4
            let difference = max(
                abs(Int(bytes[offset]) - 17),
                abs(Int(bytes[offset + 1]) - 22),
                abs(Int(bytes[offset + 2]) - 26)
            )
            if difference > 45 { count += 1 }
        }
        return count
    }
}

private struct ExampleManifest: Decodable {
    let schema: String
    let columns: Int
    let rows: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let durationSeconds: Int
    let framesPerSecond: Int
    let examples: [Entry]

    struct Entry: Decodable {
        let id: String
        let title: String
        let occupiedCells: Int
        let files: [String: Int]
        let renderStyle: String
    }
}

private struct BlockhavenManifest: Decodable {
    let schema: String
    let title: String
    let width: Int
    let height: Int
    let depth: Int
    let modelCount: Int
    let instanceCount: Int
    let occupiedCells: Int
    let pngWidth: Int
    let pngHeight: Int
    let videoWidth: Int
    let videoHeight: Int
    let durationSeconds: Int
    let framesPerSecond: Int
    let frameCount: Int
    let renderStyle: String
    let opacity: Double
    let files: [String: Int]
}
