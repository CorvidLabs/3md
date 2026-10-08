import CoreGraphics
import Foundation
import ImageIO
import RookSculpture
import Testing

@testable import RookTool

@Suite("Math ladder artifacts", .serialized)
internal struct SculptureMathExampleExportTests {
    private typealias Export = SculptureMathExampleExport

    @Test func manifestListsTheLadderInOrderWithCatalogFacts() throws {
        let manifest = try committedManifest()
        #expect(manifest.schema == "sculpt-math-ladder-1")
        #expect(manifest.entries.map(\.id) == SculptureGalleryCatalog.mathLadder.map(\.id))
        for (record, entry) in zip(manifest.entries, SculptureGalleryCatalog.mathLadder) {
            #expect(record.title == entry.title)
            #expect(record.kind == entry.kind)
            #expect(record.extent == entry.extent)
            #expect(record.formula == entry.formula)
            #expect(record.occupiedCells > 0)
            #expect(record.writeCommand.hasPrefix("RookTool sculpture math \(entry.id) NEW.3md"))
            #expect(entry.kind == .model)
            let preview = try #require(record.preview)
            #expect(preview.renderStyle == "cubes")
            #expect(preview.pixelWidth == 576 && preview.pixelHeight == 648)
            #expect(record.placementCount == nil && record.libraryModelCount == nil && record.tileModelCount == nil)
        }
    }

    @Test func committedFilesMatchTheManifestAndOmitTheLargestEntries() throws {
        let manifest = try committedManifest()
        let expected: [String: Set<String>] = [
            "math-ripple-16": ["math-ripple-16.3md", "math-ripple-16.png"],
            "math-torus-32": ["math-torus-32.3md", "math-torus-32.png"],
            "math-gyroid-64": ["math-gyroid-64.3md", "math-gyroid-64.png"],
            "math-harmonic-sphere-128": ["math-harmonic-sphere-128.3md", "math-harmonic-sphere-128.png"],
            "math-terrain-256": ["math-terrain-256.png"],
        ]
        let readme = try String(contentsOf: Self.directory.appendingPathComponent("README.md"), encoding: .utf8)
        var total = 0
        for record in manifest.entries {
            #expect(Set(record.files.keys) == expected[record.id], "\(record.id)")
            #expect(readme.contains(record.id), "\(record.id)")
            #expect(readme.contains("`\(record.formula)`"), "\(record.id) formula")
            for (name, bytes) in record.files {
                let file = Self.directory.appendingPathComponent(name)
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                #expect(values.isRegularFile == true && values.isSymbolicLink != true, "\(name)")
                #expect(values.fileSize == bytes, "\(name)")
                #expect(readme.contains("(\(name))"), "\(name)")
                total += bytes
            }
        }
        let listed = Set(manifest.entries.flatMap(\.files.keys)).union(["manifest.json", "README.md"])
        #expect(try Self.visibleEntries(of: Self.directory) == listed)
        // The 128-cell readable document is the largest committed file; nothing larger is committed.
        #expect(manifest.entries.allSatisfy { $0.files.values.allSatisfy { $0 < 2_500_000 } })
        #expect(total < 4 * 1_048_576)
        for record in manifest.entries where record.kind == .model {
            let source = try #require(
                CGImageSourceCreateWithURL(Self.directory.appendingPathComponent("\(record.id).png") as CFURL, nil)
            )
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 576 && image.height == 648, "\(record.id)")
        }
    }

    @Test(arguments: [
        SculptureMathExamples.Model.ripple, .torus, .gyroid, .harmonicSphere,
    ])
    func regeneratedModelArtifactsMatchTheCommittedFiles(_ model: SculptureMathExamples.Model) async throws {
        let entry = try #require(SculptureGalleryCatalog.entry(id: model.id))
        let artifact = try await Export.artifact(for: entry)
        let committed = try #require(try committedManifest().entries.first { $0.id == model.id })
        // PNG byte counts depend on the system encoder, so previews compare decoded pixels instead.
        #expect(Self.withoutPreviewBytes(artifact.record) == Self.withoutPreviewBytes(committed))
        #expect(artifact.files.map(\.name) == ["\(model.id).3md", "\(model.id).png"])
        for file in artifact.files {
            let stored = try Data(contentsOf: Self.directory.appendingPathComponent(file.name))
            if file.name.hasSuffix(".png") {
                let storedPixels = try Self.pixels(stored)
                #expect(storedPixels.count == 576 * 648 * 4 && storedPixels.contains { $0 != storedPixels[0] })
                // Bound first, so a failure reports the file instead of every pixel.
                let matches = try Self.previewsMatch(storedPixels, Self.pixels(file.data))
                #expect(matches, "\(file.name)")
            } else {
                #expect(stored == file.data, "\(file.name)")
            }
        }
        let document = try Data(contentsOf: Self.directory.appendingPathComponent("\(model.id).3md"))
        let reopened = try SculptureSceneReader.decode(document)
        #expect(reopened.snapshot == nil)
        guard case .voxels(let sculpture) = reopened.scene else {
            Issue.record("\(model.id).3md did not reopen as a voxel model.")
            return
        }
        #expect(sculpture.title == model.title)
        #expect(SculptureGalleryExtent(of: reopened.scene) == entry.extent)
        #expect(sculpture.occupiedCount == committed.occupiedCells)
    }

    @Test func regeneratedTerrainMatchesItsCommittedRecordAndPreview() async throws {
        let model = SculptureMathExamples.Model.terrain
        let entry = try #require(SculptureGalleryCatalog.entry(id: model.id))
        let artifact = try await Export.artifact(for: entry)
        let committed = try #require(try committedManifest().entries.first { $0.id == model.id })
        #expect(artifact.record.extent == committed.extent)
        #expect(artifact.record.extent == SculptureGalleryExtent(width: 256, height: 256, depth: 256))
        #expect(artifact.record.occupiedCells == committed.occupiedCells)
        #expect(Self.withoutPreviewBytes(artifact.record) == Self.withoutPreviewBytes(committed))
        #expect(artifact.files.map(\.name) == ["math-terrain-256.png"])
        let preview = try #require(artifact.files.first)
        let storedPixels = try Self.pixels(Data(contentsOf: Self.directory.appendingPathComponent(preview.name)))
        #expect(storedPixels.count == 576 * 648 * 4 && storedPixels.contains { $0 != storedPixels[0] })
        let matches = try Self.previewsMatch(storedPixels, Self.pixels(preview.data))
        #expect(matches, "\(preview.name)")
    }

    @Test func previewComparisonToleratesAntialiasingButNotChangedContent() throws {
        let torus = try Self.pixels(Data(contentsOf: Self.directory.appendingPathComponent("math-torus-32.png")))
        let gyroid = try Self.pixels(Data(contentsOf: Self.directory.appendingPathComponent("math-gyroid-64.png")))
        // Every byte off by at most 2, as a different rasterizer's rounding would leave it.
        let rounded = torus.enumerated().map { index, byte in
            index.isMultiple(of: 2) ? max(byte, 2) - 2 : min(byte, 253) + 2
        }
        // A few edge pixels with different antialiasing coverage: 1 in 400 bytes.
        var edges = torus
        for index in stride(from: 0, to: edges.count, by: 400) { edges[index] ^= 0x80 }
        // Changed content: 1 in 100 bytes, a different model, or a different size.
        var changed = torus
        for index in stride(from: 0, to: changed.count, by: 100) { changed[index] ^= 0x80 }
        let cases: [(name: String, pixels: [UInt8], matches: Bool)] = [
            ("identical", torus, true),
            ("rounded", rounded, true),
            ("edges", edges, true),
            ("changed", changed, false),
            ("gyroid", gyroid, false),
            ("smaller", Array(torus.dropLast(4)), false),
        ]
        for (name, pixels, expected) in cases {
            // Bound first, so a failure reports the case instead of every pixel.
            let matches = Self.previewsMatch(torus, pixels)
            #expect(matches == expected, "\(name)")
        }
    }

    @Test func directoryListingIgnoresOnlyHiddenEntries() throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in [".DS_Store", "math-ripple-16.png", "stray.3md"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        #expect(try Self.visibleEntries(of: folder) == ["math-ripple-16.png", "stray.3md"])
    }

    @Test func readmeWritesEachUncommittedEntryOutsideTheRepository() throws {
        let manifest = try committedManifest()
        let readme = try String(contentsOf: Self.directory.appendingPathComponent("README.md"), encoding: .utf8)
        let uncommitted = manifest.entries.filter { !$0.files.keys.contains { $0.hasSuffix(".3md") } }.map(\.id)
        #expect(uncommitted == ["math-terrain-256"])
        let writes = readme.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
            .filter { $0.starts(with: ["swift", "run", "--quiet", "RookTool", "sculpture", "math"]) && $0.count == 8 }
        #expect(writes.map { $0[6] } == uncommitted)
        for words in writes {
            // Large outputs stay outside the checkout, matching Examples/agent-commands.md.
            #expect(words[7].hasPrefix("/private/tmp/"), "\(words.joined(separator: " "))")
        }
    }

    @Test func writesModelEntriesAsReadableOrCompactByExtension() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let ripple = try await SculptureMathExamples.sculpture(.ripple)
        for (name, format) in [("ripple.3md", SculptureStorageFormat.readable), ("ripple.3MDB", .compact)] {
            let receipt = try await Export.write(
                arguments: ["math-ripple-16", folder.appendingPathComponent(name).path],
                workingDirectory: folder,
                progress: { _ in }
            )
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            #expect(SculptureDocumentCodec.format(of: data) == format)
            #expect(try SculptureSceneReader.decode(data).scene == .voxels(ripple))
            let json = try #require(JSONSerialization.jsonObject(with: receipt) as? [String: Any])
            #expect(json["format"] as? String == format.rawValue)
            #expect(json["occupiedCells"] as? Int == ripple.occupiedCount)
            #expect(json["placementCount"] == nil)
        }
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["ripple.3md", "ripple.3MDB"])
    }

    @Test func refusesExistingOutputsAndInvalidRequestsWithoutWriting() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let existing = folder.appendingPathComponent("existing.3md")
        try Data("keep".utf8).write(to: existing)
        let link = folder.appendingPathComponent("dangling.3md")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: folder.appendingPathComponent("target.3md")
        )
        let refusals: [([String], String)] = [
            (["math-terrain-256", "existing.3md"], "outputExists"),
            (["math-ripple-16", "dangling.3md"], "outputExists"),
            (["math-world-1024", "world.3mdb"], "unknownEntry"),
            (["math-ripple-16", "ripple.obj"], "unsupportedOutputExtension"),
            (["math-ripple-16", "missing/ripple.3md"], "outputDirectory"),
            (["math-ripple-16", "existing.3md/ripple.3md"], "outputDirectory"),
            (["math-mystery-8", "mystery.3md"], "unknownEntry"),
            (["math-ripple-16"], "usage"),
            (["math-ripple-16", "a.3md", "b.3md"], "usage"),
        ]
        for (arguments, expected) in refusals {
            do {
                _ = try await Export.write(arguments: arguments, workingDirectory: folder, progress: { _ in })
                Issue.record("\(arguments) unexpectedly wrote an output.")
            } catch {
                #expect(Self.refusalKind(error) == expected, "\(arguments): \(error)")
            }
        }
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path).hasSuffix("/target.3md"))
        #expect(
            Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["existing.3md", "dangling.3md"]
        )
    }

    @Test func anOutputCreatedDuringGenerationIsPreserved() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("racing.3md")
        do {
            _ = try await Export.write(
                arguments: ["math-torus-32", output.path],
                workingDirectory: folder,
                progress: { _ in try? Data("keep".utf8).write(to: output, options: .withoutOverwriting) }
            )
            Issue.record("A racing output was replaced.")
        } catch {
            #expect(error.localizedDescription.contains("Refusing existing output"))
        }
        #expect(try Data(contentsOf: output) == Data("keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["racing.3md"])
    }

    @Test func cancellationDuringGenerationWritesNothing() async throws {
        let folder = try Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let task = Task {
            try await Export.write(
                arguments: ["math-gyroid-64", "gyroid.3md"],
                workingDirectory: folder,
                progress: { _ in withUnsafeCurrentTask { $0?.cancel() } }
            )
        }
        do {
            _ = try await task.value
            Issue.record("A cancelled write unexpectedly published a file.")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    // MARK: - Private Methods

    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Examples/Math", isDirectory: true)

    private func committedManifest() throws -> Export.Manifest {
        try JSONDecoder().decode(
            Export.Manifest.self,
            from: Data(contentsOf: Self.directory.appendingPathComponent("manifest.json"))
        )
    }

    private static func withoutPreviewBytes(_ record: Export.Record) -> Export.Record {
        Export.Record(
            id: record.id,
            title: record.title,
            kind: record.kind,
            extent: record.extent,
            formula: record.formula,
            occupiedCells: record.occupiedCells,
            placementCount: record.placementCount,
            libraryModelCount: record.libraryModelCount,
            tileModelCount: record.tileModelCount,
            preview: record.preview,
            // PNG names stay listed with a zero byte count; document byte counts are compared exactly.
            files: record.files.reduce(into: [:]) { files, file in
                files[file.key] = file.key.hasSuffix(".png") ? 0 : file.value
            },
            writeCommand: record.writeCommand
        )
    }

    /// Directory entries a checkout tracks. Hidden entries such as Finder's `.DS_Store` are ignored.
    private static func visibleEntries(of folder: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") })
    }

    /// Whether a fresh preview matches a committed one. Antialiased edges can shift slightly between macOS
    /// releases, so both images must have the same size and at most 1 in 200 bytes may differ by more than 2.
    private static func previewsMatch(_ stored: [UInt8], _ fresh: [UInt8]) -> Bool {
        guard stored.count == fresh.count else { return false }
        let differing = zip(stored, fresh).reduce(0) { count, pair in
            abs(Int(pair.0) - Int(pair.1)) > 2 ? count + 1 : count
        }
        return differing <= stored.count / 200
    }

    /// Decoded RGBA bytes of a PNG, drawn into one fixed sRGB layout.
    private static func pixels(_ png: Data) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return bytes
    }

    private static func refusalKind(_ error: any Error) -> String {
        switch error as? Export.MathExportError {
        case .usage?: "usage"
        case .unknownEntry?: "unknownEntry"
        case .outputExists?: "outputExists"
        case .outputDirectory?: "outputDirectory"
        case .roundTrip?: "roundTrip"
        case nil:
            error.localizedDescription.contains("Unsupported output extension")
                ? "unsupportedOutputExtension" : "\(error)"
        }
    }

    private static func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "rook-math-ladder-\(UUID())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }
}

/// Collects progress lines from the synchronous progress sink. Unchecked because every access holds `lock`;
/// `Mutex` needs macOS 15 and the package targets macOS 14.
fileprivate final class MessageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    fileprivate var values: [String] { lock.withLock { lines } }

    fileprivate func append(_ line: String) { lock.withLock { lines.append(line) } }
}
