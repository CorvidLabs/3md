import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import Metal
import RookSculpture
import UniformTypeIdentifiers

public enum SculptureAnimationFormat: String, CaseIterable, Sendable {
    case gif
    case mp4
}

/// A bounded turntable. Frames sample one revolution without duplicating the first frame at the end.
public struct SculptureTurntableConfiguration: Equatable, Sendable {
    public let durationSeconds: Int
    public let framesPerSecond: Int
    public let columns: Int
    public let rows: Int
    public var frameCount: Int { durationSeconds * framesPerSecond }
    public var pixelWidth: Int { columns * 9 }
    public var pixelHeight: Int { rows * 18 }

    public static let standard = try! Self()

    public init(durationSeconds: Int = 4, framesPerSecond: Int = 10, columns: Int = 64, rows: Int = 36) throws {
        guard (1...10).contains(durationSeconds), [5, 10, 20, 25, 30].contains(framesPerSecond),
            (8...128).contains(columns), columns.isMultiple(of: 2), (8...72).contains(rows)
        else { throw SculptureAnimationExportError.invalidConfiguration }
        self.durationSeconds = durationSeconds
        self.framesPerSecond = framesPerSecond
        self.columns = columns
        self.rows = rows
    }
}

public enum SculptureAnimationExportError: Error, LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case invalidDestination
    case destinationExists
    case frameRenderingFailed
    case encodingFailed(String)
    case stalledWriter

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Use 1–10 seconds, 5/10/20/25/30 frames per second, an even 8–128 columns, and 8–72 rows. GIF uses 5 or 10 frames per second."
        case .invalidDestination: "Choose a new output file in an existing folder."
        case .destinationExists: "The export destination already exists. Choose a new file."
        case .frameRenderingFailed: "The turntable frame could not be rendered."
        case .encodingFailed(let detail): "The animation could not be encoded: \(detail)"
        case .stalledWriter: "The video encoder stopped accepting frames. Try the export again."
        }
    }
}

/// Produces an ASCII or cube GIF or silent H.264 MP4 on a private worker actor.
/// The caller supplies a new file URL, then offers the completed file through its save dialog.
public enum SculptureAnimationExporter {
    public static func export(
        sculpture: Sculpture,
        camera: SculptureCamera,
        style: SculptureRenderStyle = .ascii,
        opacity: Double = 0.35,
        format: SculptureAnimationFormat,
        configuration: SculptureTurntableConfiguration = .standard,
        destination: URL,
        progress: @escaping @Sendable (Double) async -> Void = { _ in }
    ) async throws -> URL {
        let job = AnimationJob()
        return try await job.export(
            sculpture: sculpture,
            camera: camera,
            style: style,
            opacity: opacity,
            format: format,
            configuration: configuration,
            destination: destination,
            progress: progress
        )
    }
}

private actor AnimationJob {
    private var writer: AVAssetWriter?
    private var cubeScene: SculptureVoxelScene?

    func export(
        sculpture: Sculpture,
        camera: SculptureCamera,
        style: SculptureRenderStyle = .ascii,
        opacity: Double = 0.35,
        format: SculptureAnimationFormat,
        configuration: SculptureTurntableConfiguration,
        destination: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        try Task.checkCancellation()
        let files = FileManager.default
        var isDirectory = ObjCBool(false)
        guard destination.isFileURL,
            files.fileExists(atPath: destination.deletingLastPathComponent().path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw SculptureAnimationExportError.invalidDestination }
        guard !files.fileExists(atPath: destination.path) else {
            throw SculptureAnimationExportError.destinationExists
        }
        guard format != .gif || [5, 10].contains(configuration.framesPerSecond) else {
            throw SculptureAnimationExportError.invalidConfiguration
        }
        let stagingDirectory = destination.deletingLastPathComponent()
            .appendingPathComponent(".rook-turntable-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        let staging = stagingDirectory.appendingPathComponent("turntable").appendingPathExtension(format.rawValue)
        defer {
            if writer?.status == .writing { writer?.cancelWriting() }
            writer = nil
            cubeScene = nil
            // ImageIO may create its own atomic-write files. They belong to this job's
            // unique directory, so cancellation cleans them without touching the caller's other files.
            try? files.removeItem(at: stagingDirectory)
        }
        await progress(0)
        if style == .cubes {
            do {
                cubeScene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
            } catch SculptureVoxelSurfaceError.tooManyFaces {
                // Extraction counts every exterior face, while each export frame
                // counts only camera-facing faces. Keep the document path when
                // the complete scene exceeds 500,000 but a frame may still fit.
                cubeScene = nil
            }
        }
        switch format {
        case .gif:
            try await writeGIF(
                sculpture: sculpture,
                camera: camera,
                style: style,
                opacity: opacity,
                configuration: configuration,
                destination: staging,
                progress: progress
            )
        case .mp4:
            try await writeMovie(
                sculpture: sculpture,
                camera: camera,
                style: style,
                opacity: opacity,
                configuration: configuration,
                destination: staging,
                progress: progress
            )
        }
        try Task.checkCancellation()
        // moveItem refuses an existing target, including one created while the encoder was working.
        try files.moveItem(at: staging, to: destination)
        await progress(1)
        return destination
    }

    private func image(
        sculpture: Sculpture,
        camera: SculptureCamera,
        style: SculptureRenderStyle = .ascii,
        opacity: Double = 0.35,
        configuration: SculptureTurntableConfiguration,
        frame: Int
    ) throws -> CGImage {
        var camera = camera
        let startingYaw = camera.yaw.isFinite ? camera.yaw.truncatingRemainder(dividingBy: 2 * .pi) : 0
        camera.yaw = startingYaw + Double(frame) / Double(configuration.frameCount) * 2 * .pi
        let cubeScene = cubeScene
        return try autoreleasepool {
            let rendered: CGImage?
            if let cubeScene {
                rendered = SculptureVoxelRasterizer.image(
                    SculptureVoxelProjection.frame(
                        cubeScene,
                        camera: camera,
                        width: configuration.pixelWidth,
                        height: configuration.pixelHeight
                    ),
                    opacity: opacity
                )
            } else {
                rendered = SculptureImageRenderer.image(
                    sculpture: sculpture,
                    camera: camera,
                    style: style,
                    opacity: opacity,
                    width: configuration.pixelWidth,
                    height: configuration.pixelHeight
                )
            }
            guard
                let image = rendered
            else {
                try Task.checkCancellation()
                throw SculptureAnimationExportError.frameRenderingFailed
            }
            return image
        }
    }

    private func writeGIF(
        sculpture: Sculpture,
        camera: SculptureCamera,
        style: SculptureRenderStyle = .ascii,
        opacity: Double = 0.35,
        configuration: SculptureTurntableConfiguration,
        destination: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        guard
            let output = CGImageDestinationCreateWithURL(
                destination as CFURL,
                UTType.gif.identifier as CFString,
                configuration.frameCount,
                nil
            )
        else { throw SculptureAnimationExportError.encodingFailed("ImageIO could not create the GIF.") }
        CGImageDestinationSetProperties(
            output,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        let delay = 1 / Double(configuration.framesPerSecond)
        let properties =
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                ]
            ] as CFDictionary
        for frame in 0..<configuration.frameCount {
            try Task.checkCancellation()
            let image = try image(
                sculpture: sculpture,
                camera: camera,
                style: style,
                opacity: opacity,
                configuration: configuration,
                frame: frame
            )
            CGImageDestinationAddImage(output, image, properties)
            await progress(Double(frame + 1) / Double(configuration.frameCount) * 0.95)
        }
        try Task.checkCancellation()
        guard CGImageDestinationFinalize(output) else {
            throw SculptureAnimationExportError.encodingFailed("ImageIO could not finish the GIF.")
        }
    }

    private func writeMovie(
        sculpture: Sculpture,
        camera: SculptureCamera,
        style: SculptureRenderStyle = .ascii,
        opacity: Double = 0.35,
        configuration: SculptureTurntableConfiguration,
        destination: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        self.writer = writer
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: configuration.pixelWidth,
                AVVideoHeightKey: configuration.pixelHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: max(500_000, configuration.pixelWidth * configuration.pixelHeight * 4),
                    AVVideoExpectedSourceFrameRateKey: configuration.framesPerSecond,
                    AVVideoMaxKeyFrameIntervalKey: configuration.framesPerSecond,
                ],
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: configuration.pixelWidth,
                kCVPixelBufferHeightKey as String: configuration.pixelHeight,
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
        )
        guard writer.canAdd(input) else {
            throw SculptureAnimationExportError.encodingFailed("H.264 video is unavailable.")
        }
        writer.add(input)
        guard writer.startWriting() else { throw writerError(writer) }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            throw SculptureAnimationExportError.encodingFailed("The encoder could not allocate its frame pool.")
        }
        let renderer: CIContext
        if let device = MTLCreateSystemDefaultDevice() {
            renderer = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            renderer = CIContext(options: [.cacheIntermediates: false])
        }
        for frame in 0..<configuration.frameCount {
            try Task.checkCancellation()
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writerError(writer) }
                guard ContinuousClock.now < deadline else { throw SculptureAnimationExportError.stalledWriter }
                try await Task.sleep(for: .milliseconds(10))
            }
            let image = try image(
                sculpture: sculpture,
                camera: camera,
                style: style,
                opacity: opacity,
                configuration: configuration,
                frame: frame
            )
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
                throw SculptureAnimationExportError.encodingFailed("The encoder could not allocate a frame.")
            }
            renderer.render(
                CIImage(cgImage: image),
                to: buffer,
                bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            let time = CMTime(value: Int64(frame), timescale: Int32(configuration.framesPerSecond))
            guard adaptor.append(buffer, withPresentationTime: time) else { throw writerError(writer) }
            await progress(Double(frame + 1) / Double(configuration.frameCount) * 0.95)
        }
        try Task.checkCancellation()
        writer.endSession(atSourceTime: CMTime(seconds: Double(configuration.durationSeconds), preferredTimescale: 600))
        input.markAsFinished()
        writer.finishWriting {}
        let finishDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while writer.status == .writing {
            try Task.checkCancellation()
            guard ContinuousClock.now < finishDeadline else { throw SculptureAnimationExportError.stalledWriter }
            try await Task.sleep(for: .milliseconds(10))
        }
        try Task.checkCancellation()
        guard writer.status == .completed else { throw writerError(writer) }
    }

    private func writerError(_ writer: AVAssetWriter) -> SculptureAnimationExportError {
        .encodingFailed(writer.error?.localizedDescription ?? "The writer ended with status \(writer.status.rawValue).")
    }
}
