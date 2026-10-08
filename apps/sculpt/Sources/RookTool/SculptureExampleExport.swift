import CoreGraphics
import Foundation
import ImageIO
import RookRendering
import RookSculpture

/// Development-only generation. The app never imports or launches this target.
internal enum SculptureExampleExport {
    static func generate(in root: URL) async throws {
        let manager = FileManager.default
        let output = root.appendingPathComponent("Examples", isDirectory: true)
        if manager.fileExists(atPath: output.path),
            try output.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
        {
            throw GenerationError.unsafeDestination
        }
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        let manifestURL = output.appendingPathComponent("manifest.json")
        if (try? manifestURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw GenerationError.unsafeDestination
        }
        let manifestSize = (try? manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
        let previous =
            manifestSize <= 1_048_576
            ? try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL)) : nil
        var records: [ArtifactRecord] = []
        for example in SculptureExamples.all {
            try Task.checkCancellation()
            let style: SculptureRenderStyle = example.sculpture.width >= 64 ? .cubes : .ascii
            let styleName = style.rawValue.lowercased()
            let encoded = SculptureCodec.encode(example.sculpture)
            if let previous, previous.columns == 64, previous.rows == 36, previous.durationSeconds == 4,
                previous.framesPerSecond == 10,
                let record = previous.examples.first(where: { $0.id == example.id }),
                record.title == example.title,
                (record.renderStyle ?? "ascii") == styleName,
                record.occupiedCells == example.sculpture.occupiedCount,
                record.files.count == 5,
                record.files["3md"] == encoded.count,
                Set(record.files.keys) == Set(["3md", "png", "gif", "mp4", "obj"]),
                record.files.allSatisfy({ format, bytes in
                    let url = output.appendingPathComponent("\(example.id).\(format)")
                    guard
                        let values = try? url.resourceValues(forKeys: [
                            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
                        ])
                    else { return false }
                    return values.isRegularFile == true && values.isSymbolicLink != true && values.fileSize == bytes
                }),
                (try? Data(contentsOf: output.appendingPathComponent("\(example.id).3md"))) == encoded
            {
                records.append(
                    ArtifactRecord(
                        id: record.id,
                        title: record.title,
                        occupiedCells: record.occupiedCells,
                        files: record.files,
                        renderStyle: styleName
                    )
                )
                FileHandle.standardOutput.write(Data("Kept verified unchanged formats: \(example.title)\n".utf8))
                continue
            }
            FileHandle.standardOutput.write(Data("Generating \(styleName) formats: \(example.title)\n".utf8))
            let staging = manager.temporaryDirectory.appendingPathComponent(
                "SculptExample-\(UUID())",
                isDirectory: true
            )
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: staging) }
            let camera = SculptureCamera(
                yaw: -0.6,
                pitch: ["Maps", "Worlds", "Space"].contains(example.category) ? 0.7 : 0.35,
                zoom: example.category == "Space" ? 0.9 : style == .cubes ? 1.05 : 1.3
            )
            guard let png = SculptureImageRenderer.png(sculpture: example.sculpture, camera: camera, style: style)
            else { throw GenerationError.renderingFailed }
            let formats: [(String, Data)] = [
                ("3md", encoded),
                ("png", png),
                ("obj", try SculptureOBJExporter.data(for: example.sculpture)),
            ]
            for (fileExtension, data) in formats {
                try data.write(to: staging.appendingPathComponent("\(example.id).\(fileExtension)"), options: .atomic)
            }
            for format in SculptureAnimationFormat.allCases {
                _ = try await SculptureAnimationExporter.export(
                    sculpture: example.sculpture,
                    camera: camera,
                    style: style,
                    format: format,
                    destination: staging.appendingPathComponent("\(example.id).\(format.rawValue)")
                )
            }
            var files: [String: Int] = [:]
            for fileExtension in ["3md", "png", "gif", "mp4", "obj"] {
                let name = "\(example.id).\(fileExtension)"
                let target = output.appendingPathComponent(name)
                if manager.fileExists(atPath: target.path),
                    try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
                {
                    throw GenerationError.unsafeDestination
                }
                let data = try Data(contentsOf: staging.appendingPathComponent(name))
                try data.write(to: target, options: .atomic)
                files[fileExtension] = data.count
            }
            records.append(
                ArtifactRecord(
                    id: example.id,
                    title: example.title,
                    occupiedCells: example.sculpture.occupiedCount,
                    files: files,
                    renderStyle: styleName
                )
            )
            FileHandle.standardOutput.write(Data("Generated five formats: \(example.title)\n".utf8))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let manifest = Manifest(
            schema: "sculpt-examples-1",
            columns: 64,
            rows: 36,
            pixelWidth: 576,
            pixelHeight: 648,
            durationSeconds: 4,
            framesPerSecond: 10,
            examples: records
        )
        if manager.fileExists(atPath: manifestURL.path),
            try manifestURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
        {
            throw GenerationError.unsafeDestination
        }
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try await generateComposition(in: output)
        try await generateBlockhaven(in: root)
        try await SculptureMathExampleExport.generate(in: root)
    }

    /// Generates only Blockhaven, leaving the original gallery and courtyard artifacts untouched.
    static func generateBlockhaven(in root: URL) async throws {
        try Task.checkCancellation()
        let manager = FileManager.default
        let examples = root.appendingPathComponent("Examples", isDirectory: true)
        let output = examples.appendingPathComponent("Blockhaven", isDirectory: true)
        try safeDirectory(examples)
        try safeDirectory(output)
        let composition = try SculptureBlockWorldExamples.composition()
        let world = try SculptureBlockWorldExamples.world()
        let sculpture = try composition.expanded()
        let compositionData = try SculptureCompositionCodec.encode(composition)
        let worldData = try SculptureWorldCodec.encode(world)
        let compactData = try SculptureBinaryCodec.encode(sculpture)
        let camera = SculptureCamera(yaw: -0.6, pitch: 0.75, zoom: 0.9)
        let configuration = SculptureTurntableConfiguration.standard
        let opacity = 0.8
        let fileNames = [
            "blockhaven.3md", "blockhaven-world.3md", "blockhaven.3mdb", "blockhaven.png",
            "blockhaven.gif", "blockhaven.mp4", "blockhaven.obj",
        ]
        let manifestURL = output.appendingPathComponent("manifest.json")
        for name in fileNames + ["manifest.json"] { try safeFile(output.appendingPathComponent(name)) }
        let manifestSize = (try? manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
        if manifestSize <= 1_048_576,
            let previous = try? JSONDecoder().decode(
                BlockhavenArtifactRecord.self,
                from: Data(contentsOf: manifestURL)
            ),
            previous.schema == "sculpt-blockhaven-example-1", previous.title == sculpture.title,
            previous.width == sculpture.width, previous.height == sculpture.height, previous.depth == sculpture.depth,
            previous.modelCount == composition.models.count, previous.instanceCount == world.instances.count,
            previous.occupiedCells == sculpture.occupiedCount,
            previous.pngWidth == 1152, previous.pngHeight == 1296,
            previous.videoWidth == configuration.pixelWidth, previous.videoHeight == configuration.pixelHeight,
            previous.durationSeconds == configuration.durationSeconds,
            previous.framesPerSecond == configuration.framesPerSecond,
            previous.frameCount == configuration.frameCount, previous.renderStyle == "cubes",
            previous.opacity == opacity,
            previous.yaw == camera.yaw, previous.pitch == camera.pitch, previous.zoom == camera.zoom,
            Set(previous.files.keys) == Set(fileNames),
            previous.files.allSatisfy({ name, bytes in
                let file = output.appendingPathComponent(name)
                guard
                    let values = try? file.resourceValues(forKeys: [
                        .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                    ])
                else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true && values.fileSize == bytes
            }),
            (try? Data(contentsOf: output.appendingPathComponent("blockhaven.3md"))) == compositionData,
            (try? Data(contentsOf: output.appendingPathComponent("blockhaven-world.3md"))) == worldData,
            (try? Data(contentsOf: output.appendingPathComponent("blockhaven.3mdb"))) == compactData
        {
            FileHandle.standardOutput.write(Data("Kept verified unchanged Blockhaven artifacts.\n".utf8))
            return
        }
        try Task.checkCancellation()
        let staging = manager.temporaryDirectory.appendingPathComponent("SculptBlockhaven-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        guard
            let image = SculptureImageRenderer.image(
                sculpture: sculpture,
                camera: camera,
                style: .cubes,
                opacity: opacity,
                width: 1152,
                height: 1296
            )
        else { throw GenerationError.renderingFailed }
        let staticFiles: [(String, Data)] = [
            ("blockhaven.3md", compositionData), ("blockhaven-world.3md", worldData),
            ("blockhaven.3mdb", compactData), ("blockhaven.png", try encodePNG(image)),
            ("blockhaven.obj", try SculptureOBJExporter.data(for: sculpture)),
        ]
        for (name, data) in staticFiles {
            try Task.checkCancellation()
            try data.write(to: staging.appendingPathComponent(name), options: .atomic)
        }
        for format in SculptureAnimationFormat.allCases {
            _ = try await SculptureAnimationExporter.export(
                sculpture: sculpture,
                camera: camera,
                style: .cubes,
                opacity: opacity,
                format: format,
                configuration: configuration,
                destination: staging.appendingPathComponent("blockhaven.\(format.rawValue)")
            )
        }
        try Task.checkCancellation()
        // Preflight every destination before publishing the completed payload. The manifest is written last.
        try safeDirectory(output)
        for name in fileNames + ["manifest.json"] { try safeFile(output.appendingPathComponent(name)) }
        var files: [String: Int] = [:]
        for name in fileNames {
            let data = try Data(contentsOf: staging.appendingPathComponent(name))
            try data.write(to: output.appendingPathComponent(name), options: .atomic)
            files[name] = data.count
        }
        let record = BlockhavenArtifactRecord(
            schema: "sculpt-blockhaven-example-1",
            title: sculpture.title,
            width: sculpture.width,
            height: sculpture.height,
            depth: sculpture.depth,
            modelCount: composition.models.count,
            instanceCount: world.instances.count,
            occupiedCells: sculpture.occupiedCount,
            pngWidth: image.width,
            pngHeight: image.height,
            videoWidth: configuration.pixelWidth,
            videoHeight: configuration.pixelHeight,
            durationSeconds: configuration.durationSeconds,
            framesPerSecond: configuration.framesPerSecond,
            frameCount: configuration.frameCount,
            renderStyle: "cubes",
            opacity: opacity,
            yaw: camera.yaw,
            pitch: camera.pitch,
            zoom: camera.zoom,
            files: files
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(record).write(to: manifestURL, options: .atomic)
        FileHandle.standardOutput.write(Data("Generated seven Blockhaven source and export artifacts.\n".utf8))
    }

    internal static func safeDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw GenerationError.unsafeDestination
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw GenerationError.unsafeDestination }
    }

    internal static func safeFile(_ file: URL) throws {
        if let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]),
            values.isSymbolicLink == true || values.isRegularFile != true
        {
            throw GenerationError.unsafeDestination
        }
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw GenerationError.renderingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GenerationError.renderingFailed }
        return data as Data
    }

    private static func generateComposition(in examples: URL) async throws {
        let manager = FileManager.default
        let output = examples.appendingPathComponent("Compositions", isDirectory: true)
        if (try? output.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw GenerationError.unsafeDestination
        }
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        let composition = try SculptureCompositionExamples.courtyard()
        let world = try SculptureWorldExamples.wideWorld()
        let sculpture = try composition.expanded()
        let camera = SculptureCamera(yaw: -0.6, pitch: 0.7, zoom: 1.1)
        guard let png = SculptureImageRenderer.png(sculpture: sculpture, camera: camera, style: .cubes) else {
            throw GenerationError.renderingFailed
        }
        let staging = manager.temporaryDirectory.appendingPathComponent(
            "SculptComposition-\(UUID())",
            isDirectory: true
        )
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        let staticFormats: [(String, Data)] = [
            ("3md", try SculptureCompositionCodec.encode(composition)),
            ("3mdb", try SculptureBinaryCodec.encode(sculpture)),
            ("png", png),
            ("obj", try SculptureOBJExporter.data(for: sculpture)),
        ]
        let worldTarget = output.appendingPathComponent("wide-world.3md")
        if (try? worldTarget.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw GenerationError.unsafeDestination
        }
        try SculptureWorldCodec.encode(world).write(to: worldTarget, options: .atomic)
        for (fileExtension, data) in staticFormats {
            try data.write(to: staging.appendingPathComponent("courtyard.\(fileExtension)"), options: .atomic)
        }
        for format in SculptureAnimationFormat.allCases {
            _ = try await SculptureAnimationExporter.export(
                sculpture: sculpture,
                camera: camera,
                style: .cubes,
                format: format,
                destination: staging.appendingPathComponent("courtyard.\(format.rawValue)")
            )
        }
        var files: [String: Int] = [:]
        for fileExtension in ["3md", "3mdb", "png", "gif", "mp4", "obj"] {
            let name = "courtyard.\(fileExtension)"
            let target = output.appendingPathComponent(name)
            if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw GenerationError.unsafeDestination
            }
            let data = try Data(contentsOf: staging.appendingPathComponent(name))
            try data.write(to: target, options: .atomic)
            files[fileExtension] = data.count
        }
        let manifestURL = output.appendingPathComponent("manifest.json")
        if (try? manifestURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw GenerationError.unsafeDestination
        }
        let manifest = CompositionArtifactRecord(
            schema: "sculpt-composition-example-1",
            modelCount: composition.models.count,
            occupiedCells: sculpture.occupiedCount,
            files: files
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        FileHandle.standardOutput.write(
            Data("Generated nested courtyard composition and five expanded formats.\n".utf8)
        )
    }

    private struct CompositionArtifactRecord: Encodable {
        let schema: String
        let modelCount: Int
        let occupiedCells: Int
        let files: [String: Int]
    }

    private struct BlockhavenArtifactRecord: Codable {
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
        let yaw: Double
        let pitch: Double
        let zoom: Double
        let files: [String: Int]
    }

    private struct ArtifactRecord: Codable {
        let id: String
        let title: String
        let occupiedCells: Int
        let files: [String: Int]
        let renderStyle: String?
    }

    private struct Manifest: Codable {
        let schema: String
        let columns: Int
        let rows: Int
        let pixelWidth: Int
        let pixelHeight: Int
        let durationSeconds: Int
        let framesPerSecond: Int
        let examples: [ArtifactRecord]
    }

    internal enum GenerationError: Error {
        case unsafeDestination, renderingFailed
    }
}
