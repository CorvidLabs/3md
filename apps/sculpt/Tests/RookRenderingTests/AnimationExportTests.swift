import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import RookRendering
import RookSculpture
import Testing

@Suite(.serialized)
struct AnimationExportTests {
    @Test func configurationRejectsUnboundedWorkAndOddMovieDimensions() {
        for dimensions in [
            (0, 10, 64, 36), (11, 10, 64, 36), (1, 60, 64, 36), (1, 10, 63, 36), (1, 10, 130, 36), (1, 10, 64, 73),
        ] {
            #expect(throws: SculptureAnimationExportError.invalidConfiguration) {
                try SculptureTurntableConfiguration(
                    durationSeconds: dimensions.0,
                    framesPerSecond: dimensions.1,
                    columns: dimensions.2,
                    rows: dimensions.3
                )
            }
        }
        #expect(SculptureTurntableConfiguration.standard.frameCount == 40)
    }

    @Test func gifLoopsWithCorrectFrameTimingAndChangingDecodedImages() async throws {
        let folder = try ExportFolder("gif")
        defer { folder.cleanUp() }
        let output = folder.url.appendingPathComponent("turntable.gif")
        let progress = ProgressHistory()
        let configuration = try SculptureTurntableConfiguration(
            durationSeconds: 1,
            framesPerSecond: 10,
            columns: 16,
            rows: 12
        )
        let result = try await SculptureAnimationExporter.export(
            sculpture: asymmetricSculpture(),
            camera: SculptureCamera(),
            format: .gif,
            configuration: configuration,
            destination: output,
            progress: { await progress.record($0) }
        )
        #expect(result == output)
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 10)
        let properties = try #require(CGImageSourceCopyProperties(source, nil) as? [String: Any])
        let gif = try #require(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
        #expect((gif[kCGImagePropertyGIFLoopCount as String] as? NSNumber)?.intValue == 0)
        var decodedFrames: Set<Data> = []
        var totalDelay = 0.0
        for frame in 0..<CGImageSourceGetCount(source) {
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [String: Any])
            let gif = try #require(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
            let delay = try #require(gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber).doubleValue
            #expect(abs(delay - 0.1) < 0.000_001)
            totalDelay += delay
            let image = try #require(CGImageSourceCreateImageAtIndex(source, frame, nil))
            #expect(image.width == configuration.pixelWidth)
            #expect(image.height == configuration.pixelHeight)
            decodedFrames.insert(try rgbaData(image))
        }
        #expect(abs(totalDelay - 1) < 0.000_001)
        #expect(decodedFrames.count > 3)
        try await progress.verifyCompleted(frameCount: configuration.frameCount)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == ["turntable.gif"])
    }

    @Test(arguments: [10, 30])
    func mp4DecodesEveryFrameWithCorrectDurationDimensionsAndVisibleGlyphs(_ framesPerSecond: Int) async throws {
        let folder = try ExportFolder("mp4")
        defer { folder.cleanUp() }
        let output = folder.url.appendingPathComponent("turntable.mp4")
        let configuration = try SculptureTurntableConfiguration(
            durationSeconds: 1,
            framesPerSecond: framesPerSecond,
            columns: 16,
            rows: 12
        )
        let progress = ProgressHistory()
        _ = try await SculptureAnimationExporter.export(
            sculpture: asymmetricSculpture(),
            camera: SculptureCamera(),
            format: .mp4,
            configuration: configuration,
            destination: output,
            progress: { await progress.record($0) }
        )
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 1) < 0.02)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try #require(tracks.first)
        let size = try await track.load(.naturalSize)
        #expect(Int(size.width) == configuration.pixelWidth)
        #expect(Int(size.height) == configuration.pixelHeight)
        let reader = try AVAssetReader(asset: asset)
        let samples = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        #expect(reader.canAdd(samples))
        reader.add(samples)
        #expect(reader.startReading())
        var count = 0
        var visiblePixels = 0
        while let sample = samples.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            #expect(abs(time.seconds - Double(count) / Double(framesPerSecond)) < 0.001)
            let buffer = try #require(CMSampleBufferGetImageBuffer(sample))
            visiblePixels += try brightPixelCount(buffer)
            count += 1
        }
        #expect(reader.status == .completed)
        #expect(count == framesPerSecond)
        #expect(visiblePixels > 100)
        try await progress.verifyCompleted(frameCount: configuration.frameCount)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == ["turntable.mp4"])
    }

    @Test(arguments: SculptureAnimationFormat.allCases)
    func cancellationRemovesPartialAnimationAndOwnedStagingFile(_ format: SculptureAnimationFormat) async throws {
        let folder = try ExportFolder("cancel-\(format.rawValue)")
        defer { folder.cleanUp() }
        let gate = ExportGate()
        let task = Task {
            try await SculptureAnimationExporter.export(
                sculpture: asymmetricSculpture(),
                camera: SculptureCamera(),
                format: format,
                configuration: try SculptureTurntableConfiguration(durationSeconds: 1, columns: 16, rows: 12),
                destination: folder.url.appendingPathComponent("cancelled.\(format.rawValue)"),
                progress: { value in
                    if value > 0 && value < 1 {
                        await gate.signal()
                        try? await Task.sleep(for: .seconds(10))
                    }
                }
            )
        }
        defer { task.cancel() }
        try await gate.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path).isEmpty)
    }

    @Test func existingDestinationIsPreservedAndUnsupportedGIFRateCreatesNothing() async throws {
        let folder = try ExportFolder("refusal")
        defer { folder.cleanUp() }
        let existing = folder.url.appendingPathComponent("keep.gif")
        let original = Data("Preserve this file".utf8)
        try original.write(to: existing)
        await #expect(throws: SculptureAnimationExportError.destinationExists) {
            try await SculptureAnimationExporter.export(
                sculpture: .orb(),
                camera: SculptureCamera(),
                format: .gif,
                destination: existing
            )
        }
        #expect(try Data(contentsOf: existing) == original)
        await #expect(throws: SculptureAnimationExportError.invalidConfiguration) {
            try await SculptureAnimationExporter.export(
                sculpture: .orb(),
                camera: SculptureCamera(),
                format: .gif,
                configuration: try SculptureTurntableConfiguration(framesPerSecond: 30),
                destination: folder.url.appendingPathComponent("unsupported.gif")
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == ["keep.gif"])
    }
}

private struct ExportFolder: Sendable {
    let url: URL
    let retained: Bool

    init(_ label: String) throws {
        let evidence = ProcessInfo.processInfo.environment["ROOK_EXPORT_EVIDENCE_DIR"]
        retained = evidence != nil
        let root =
            evidence.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        url = root.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func cleanUp() {
        if !retained { try? FileManager.default.removeItem(at: url) }
    }
}

private actor ProgressHistory {
    var values: [Double] = []

    func record(_ value: Double) { values.append(value) }

    func verifyCompleted(frameCount: Int) throws {
        #expect(values.count == frameCount + 2)
        #expect(values.first == 0)
        #expect(values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }
}

private actor ExportGate {
    private var reached = false

    func signal() { reached = true }

    func wait() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while !reached {
            guard ContinuousClock.now < deadline else { throw SculptureAnimationExportError.stalledWriter }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private func asymmetricSculpture() throws -> Sculpture {
    var layers = Array(repeating: Array(repeating: Sculpture.empty, count: 64), count: 8)
    for x in 1...6 { layers[1][6 * 8 + x] = 35 }
    for y in 1...6 { layers[2][y * 8 + 1] = 64 }
    for z in 1...6 { layers[z][3 * 8 + 4] = 42 }
    return try Sculpture(title: "Turntable fixture", width: 8, height: 8, layers: layers)
}

private func rgbaData(_ image: CGImage) throws -> Data {
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
    let bytes = try #require(context.data)
    return Data(bytes: bytes, count: image.width * image.height * 4)
}

private func brightPixelCount(_ buffer: CVPixelBuffer) throws -> Int {
    #expect(CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let bytes = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    var count = 0
    for row in 0..<height {
        for column in 0..<width {
            let offset = row * stride + column * 4
            if bytes[offset + 1] > 100 && Int(bytes[offset + 1]) > Int(bytes[offset + 2]) * 2 { count += 1 }
        }
    }
    return count
}
