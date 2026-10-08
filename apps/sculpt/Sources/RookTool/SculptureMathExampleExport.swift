import Darwin
import Foundation
import RookRendering
import RookSculpture

/// Development-only math ladder artifacts. The app never imports or launches this target.
///
/// `generate(in:)` writes only `Examples/Math`: readable 3md and a PNG preview for the 16 to 128 cell models, a PNG
/// preview of the 256 cell model and a manifest. The 256 cell model is not committed as a file;
/// `write(arguments:workingDirectory:progress:)` writes any ladder model to a new output chosen by the caller.
internal enum SculptureMathExampleExport {
    /// The manifest schema for `Examples/Math/manifest.json`.
    internal static let manifestSchema = "sculpt-math-ladder-1"
    /// The largest model whose readable 3md is committed. The 128 cell document is about 2 MB.
    internal static let largestCommittedDocument = 128

    // MARK: - Generation

    /// Generates every ladder entry, then publishes `Examples/Math` with the manifest last.
    /// Existing gallery, composition and Blockhaven artifacts are not read or written.
    /// - Parameter root: The repository root that contains `Examples`.
    internal static func generate(in root: URL) async throws {
        let examples = root.appendingPathComponent("Examples", isDirectory: true)
        let output = examples.appendingPathComponent("Math", isDirectory: true)
        try SculptureExampleExport.safeDirectory(examples)
        try SculptureExampleExport.safeDirectory(output)
        var artifacts: [Artifact] = []
        for entry in SculptureGalleryCatalog.mathLadder {
            try Task.checkCancellation()
            FileHandle.standardOutput.write(Data("Generating math ladder entry: \(entry.title) (\(entry.id))\n".utf8))
            artifacts.append(try await artifact(for: entry))
        }
        try Task.checkCancellation()
        // Preflight every destination before publishing the completed payload. The manifest is written last.
        let manifestURL = output.appendingPathComponent("manifest.json")
        try SculptureExampleExport.safeDirectory(output)
        for artifact in artifacts {
            for file in artifact.files { try SculptureExampleExport.safeFile(output.appendingPathComponent(file.name)) }
        }
        try SculptureExampleExport.safeFile(manifestURL)
        for artifact in artifacts {
            for file in artifact.files {
                try file.data.write(to: output.appendingPathComponent(file.name), options: .atomic)
            }
        }
        try manifestData(Manifest(schema: manifestSchema, entries: artifacts.map(\.record)))
            .write(to: manifestURL, options: .atomic)
        let count = artifacts.reduce(0) { $0 + $1.files.count }
        FileHandle.standardOutput.write(Data("Generated \(count) math ladder files and manifest.json.\n".utf8))
    }

    /// Creates one ladder entry's scene through the gallery catalog, with its manifest record and committed files.
    /// - Parameter entry: A `SculptureGalleryCatalog.mathLadder` entry.
    /// - Returns: The record and the files `generate(in:)` publishes for this entry, in a stable order.
    internal static func artifact(for entry: SculptureGalleryEntry) async throws -> Artifact {
        guard let formula = entry.formula, SculptureGalleryCatalog.mathLadder.contains(entry) else {
            throw MathExportError.unknownEntry(entry.id)
        }
        switch try await SculptureGalleryCatalog.scene(for: entry) {
        case .voxels(let sculpture):
            guard let model = SculptureMathExamples.Model.allCases.first(where: { $0.id == entry.id }) else {
                throw MathExportError.unknownEntry(entry.id)
            }
            let preview = Preview.standard(for: model)
            guard
                let png = SculptureImageRenderer.png(
                    sculpture: sculpture,
                    camera: SculptureCamera(yaw: preview.yaw, pitch: preview.pitch, zoom: preview.zoom),
                    style: .cubes,
                    opacity: preview.opacity
                )
            else { throw SculptureExampleExport.GenerationError.renderingFailed }
            var files: [File] = []
            if sculpture.width <= largestCommittedDocument {
                files.append(File(name: "\(entry.id).3md", data: SculptureCodec.encode(sculpture)))
            }
            files.append(File(name: "\(entry.id).png", data: png))
            let record = Record(
                id: entry.id,
                title: entry.title,
                kind: entry.kind,
                extent: SculptureGalleryExtent(of: .voxels(sculpture)),
                formula: formula,
                occupiedCells: sculpture.occupiedCount,
                placementCount: nil,
                libraryModelCount: nil,
                tileModelCount: nil,
                preview: preview,
                files: Dictionary(uniqueKeysWithValues: files.map { ($0.name, $0.data.count) }),
                writeCommand: "RookTool sculpture math \(entry.id) NEW.3md|NEW.3mdb"
            )
            return Artifact(record: record, files: files)
        case .world, .composition:
            throw MathExportError.unknownEntry(entry.id)
        }
    }

    /// Encodes a manifest in the existing example manifest style.
    internal static func manifestData(_ manifest: Manifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    // MARK: - Explicit Output

    /// `sculpture math ENTRY_ID NEW.3md|NEW.3mdb`: writes one ladder model to a new file chosen by the caller.
    /// Readable 3md or compact storage follows the output extension. The encoded document must reopen to the
    /// generated scene before it is published, and an existing output is never replaced.
    /// - Parameters:
    ///   - arguments: The entry identity and the new output path.
    ///   - workingDirectory: The base for a relative output path.
    ///   - progress: Receives a line at each tenth of generation; standard error by default.
    /// - Returns: The JSON receipt, ending with a newline.
    internal static func write(
        arguments: [String],
        workingDirectory: URL,
        progress: @escaping @Sendable (String) -> Void = standardErrorProgress
    ) async throws -> Data {
        try Task.checkCancellation()
        guard arguments.count == 2 else { throw MathExportError.usage }
        guard let entry = SculptureGalleryCatalog.mathLadder.first(where: { $0.id == arguments[0] }) else {
            throw MathExportError.unknownEntry(arguments[0])
        }
        guard entry.kind == .model else { throw MathExportError.unknownEntry(entry.id) }
        let output = try SculptureCommandTool.fileURL(arguments[1], relativeTo: workingDirectory)
        let modelFormat = try SculptureCommandTool.storageFormat(for: output)
        // Fail before generating; publication checks again atomically and never replaces an entry.
        var information = stat()
        if lstat(output.path, &information) == 0 { throw MathExportError.outputExists(output) }
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: output.deletingLastPathComponent().path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw MathExportError.outputDirectory(output) }
        let steps = ProgressSteps(label: entry.id, sink: progress)
        let scene = try await SculptureGalleryCatalog.scene(for: entry) { await steps.report($0) }
        guard case .voxels(let sculpture) = scene else { throw MathExportError.unknownEntry(entry.id) }
        let data = try SculptureDocumentCodec.encode(sculpture, format: modelFormat)
        try Task.checkCancellation()
        guard try SculptureSceneReader.decode(data).scene == scene else { throw MathExportError.roundTrip(entry.id) }
        let receipt = try SculptureCommandTool.json(
            WriteReceipt(
                id: entry.id,
                title: entry.title,
                kind: entry.kind,
                extent: SculptureGalleryExtent(of: scene),
                formula: entry.formula ?? "",
                output: output.path,
                format: modelFormat.rawValue,
                bytes: data.count,
                occupiedCells: sculpture.occupiedCount
            )
        )
        try Task.checkCancellation()
        try SculptureCommandTool.publishNewFile(data, at: output)
        return receipt
    }

    /// Writes one progress line to standard error, keeping standard output for the JSON receipt.
    internal static func standardErrorProgress(_ message: String) {
        FileHandle.standardError.write(Data("sculpture math \(message)\n".utf8))
    }

    // MARK: - Types

    /// One published file.
    internal struct File: Sendable {
        internal let name: String
        internal let data: Data
    }

    /// One ladder entry's manifest record and committed files.
    internal struct Artifact: Sendable {
        internal let record: Record
        internal let files: [File]
    }

    /// `Examples/Math/manifest.json`.
    internal struct Manifest: Codable, Equatable, Sendable {
        internal let schema: String
        internal let entries: [Record]
    }

    /// One ladder model. Placement and library counts stay optional so an older manifest still decodes; models
    /// leave them unset.
    internal struct Record: Codable, Equatable, Sendable {
        internal let id: String
        internal let title: String
        internal let kind: SculptureGalleryKind
        internal let extent: SculptureGalleryExtent
        internal let formula: String
        /// Occupied cells in the generated model.
        internal let occupiedCells: Int
        internal let placementCount: Int?
        /// Library definitions including the root tile map.
        internal let libraryModelCount: Int?
        /// Library definitions that hold voxels.
        internal let tileModelCount: Int?
        internal let preview: Preview?
        /// Committed file names and their byte counts.
        internal let files: [String: Int]
        /// The explicit command that writes this entry's complete document to a new file.
        internal let writeCommand: String
    }

    /// PNG preview settings, using the gallery renderer and its 576 by 648 pixel size.
    internal struct Preview: Codable, Equatable, Sendable {
        internal let renderStyle: String
        internal let opacity: Double
        internal let yaw: Double
        internal let pitch: Double
        internal let zoom: Double
        internal let pixelWidth: Int
        internal let pixelHeight: Int

        /// Translucent cubes for the closed forms; nearly opaque cubes, seen from higher, for the filled ripple
        /// and terrain. Zoom keeps each whole volume in frame.
        internal static func standard(for model: SculptureMathExamples.Model) -> Self {
            let (opacity, pitch, zoom): (Double, Double, Double)
            switch model {
            case .ripple: (opacity, pitch, zoom) = (0.8, 0.7, 0.85)
            case .torus: (opacity, pitch, zoom) = (0.5, 0.35, 1.3)
            case .gyroid: (opacity, pitch, zoom) = (0.5, 0.35, 1.05)
            case .harmonicSphere: (opacity, pitch, zoom) = (0.5, 0.35, 1.2)
            case .terrain: (opacity, pitch, zoom) = (0.8, 0.7, 0.8)
            }
            return Self(
                renderStyle: "cubes",
                opacity: opacity,
                yaw: -0.6,
                pitch: pitch,
                zoom: zoom,
                pixelWidth: 576,
                pixelHeight: 648
            )
        }
    }

    // MARK: - Private

    private struct WriteReceipt: Encodable {
        let version = 1
        let operation = "math"
        let id: String
        let title: String
        let kind: SculptureGalleryKind
        let extent: SculptureGalleryExtent
        let formula: String
        let output: String
        let format: String
        let bytes: Int
        let occupiedCells: Int
    }

    /// Reports each completed tenth once.
    private actor ProgressSteps {
        private let label: String
        private let sink: @Sendable (String) -> Void
        private var reported = -1

        init(label: String, sink: @escaping @Sendable (String) -> Void) {
            self.label = label
            self.sink = sink
        }

        func report(_ fraction: Double) {
            let step = Int((min(max(fraction, 0), 1) * 10).rounded(.down))
            guard step > reported else { return }
            reported = step
            sink("\(label): \(step * 10)%")
        }
    }

    internal enum MathExportError: Error, CustomStringConvertible, LocalizedError, Equatable {
        case usage
        case unknownEntry(String)
        case outputExists(URL)
        case outputDirectory(URL)
        case roundTrip(String)

        internal var errorDescription: String? { description }

        internal var description: String {
            switch self {
            case .usage:
                "Usage: RookTool sculpture math ENTRY_ID NEW.3md|NEW.3mdb. Entries: "
                    + SculptureGalleryCatalog.mathLadder.map(\.id).joined(separator: ", ")
            case .unknownEntry(let id):
                "Unknown math ladder entry \(id). Choose one of "
                    + SculptureGalleryCatalog.mathLadder.map(\.id).joined(separator: ", ") + "."
            case .outputExists(let file):
                "Refusing existing output or symbolic link at \(file.path). Choose a new output file."
            case .outputDirectory(let file):
                "Cannot write \(file.path): choose a new file inside an existing directory."
            case .roundTrip(let id): "The encoded \(id) document did not reopen to the generated scene."
            }
        }
    }
}
