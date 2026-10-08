import Foundation
import Observation
import RookRendering
import RookSculpture
import SwiftUI
import UniformTypeIdentifiers

internal enum SculptureExportKind: String, CaseIterable, Identifiable, Sendable {
    case gif = "GIF"
    case movie = "MP4 video"
    case mesh = "OBJ mesh"

    var id: Self { self }
    var contentType: UTType {
        switch self {
        case .gif: .gif
        case .movie: .mpeg4Movie
        case .mesh: .sculptureMesh
        }
    }
    var fileExtension: String {
        switch self {
        case .gif: "gif"
        case .movie: "mp4"
        case .mesh: "obj"
        }
    }

    var explanation: String {
        switch self {
        case .gif: "A looping turntable of your sculpture."
        case .movie: "A full rotation of your sculpture, ready to share."
        case .mesh: "A 3D surface made from the occupied cells. Characters become solid voxels."
        }
    }
}

@MainActor
@Observable
internal final class SculptureExportJob {
    private(set) var progress = 0.0
    private(set) var isRunning = false
    private(set) var output: URL?
    private(set) var error: String?
    @ObservationIgnored private var worker: Task<URL, any Error>?
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var generation = UUID()

    static func filename(title: String, kind: SculptureExportKind) -> String {
        let safe = title.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
                ? character : "-"
        }
        let base = String(safe).split(separator: "-").joined(separator: "-")
        return "\(base.isEmpty ? "Sculpture" : base).\(kind.fileExtension)"
    }

    func start(
        sculpture: Sculpture,
        camera: SculptureCamera,
        style: SculptureRenderStyle = .ascii,
        opacity: Double = 0.35,
        kind: SculptureExportKind,
        duration: Int,
        framesPerSecond: Int,
        columns: Int,
        rows: Int
    ) {
        guard !isRunning else { return }
        cleanup()
        let identifier = UUID()
        generation = identifier
        progress = 0
        error = nil
        isRunning = true
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RookExport-\(identifier.uuidString)", isDirectory: true)
        directory = folder
        let destination = folder.appendingPathComponent(Self.filename(title: sculpture.title, kind: kind))
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try Task.checkCancellation()
                if kind == .mesh {
                    let data = try SculptureOBJExporter.data(for: sculpture)
                    try Task.checkCancellation()
                    try data.write(to: destination, options: .atomic)
                } else {
                    let configuration = try SculptureTurntableConfiguration(
                        durationSeconds: duration,
                        framesPerSecond: framesPerSecond,
                        columns: columns,
                        rows: rows
                    )
                    _ = try await SculptureAnimationExporter.export(
                        sculpture: sculpture,
                        camera: camera,
                        style: style,
                        opacity: opacity,
                        format: kind == .gif ? .gif : .mp4,
                        configuration: configuration,
                        destination: destination
                    ) { [weak self] value in
                        await self?.updateProgress(value, generation: identifier)
                    }
                }
                try Task.checkCancellation()
                return destination
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
        }
        worker = task
        Task { [weak self] in
            do {
                let url = try await task.value
                guard let self, self.generation == identifier else {
                    try? FileManager.default.removeItem(at: folder)
                    return
                }
                self.output = url
                self.progress = 1
                self.isRunning = false
                self.worker = nil
            } catch {
                guard let self, self.generation == identifier else { return }
                self.error = error is CancellationError ? "Export cancelled." : error.localizedDescription
                self.isRunning = false
                self.worker = nil
                self.directory = nil
            }
        }
    }

    func cancel() { worker?.cancel() }

    private func updateProgress(_ value: Double, generation: UUID) {
        guard self.generation == generation, isRunning else { return }
        progress = value
    }

    func cleanup() {
        generation = UUID()
        worker?.cancel()
        worker = nil
        isRunning = false
        output = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
}

internal struct SculptureExportStudio: View {
    let sculpture: Sculpture
    let camera: SculptureCamera
    var style: SculptureRenderStyle = .ascii
    var opacity = 0.35
    let completed: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var job = SculptureExportJob()
    @State private var kind = SculptureExportKind.gif
    @State private var duration = 4
    @State private var framesPerSecond = 10
    @State private var highResolution = false
    @State private var choosingDestination = false
    @State private var exportDocument: SculptureExport?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Export sculpture").font(.title2.weight(.semibold))
            Text("\(sculpture.title) · \(kind == .mesh ? "Voxel geometry" : style.rawValue)").foregroundStyle(
                Brand.secondary
            )
            Picker("Format", selection: $kind) {
                ForEach(SculptureExportKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(job.isRunning || job.output != nil)
            Text(kind.explanation).font(.callout).foregroundStyle(Brand.secondary)
            if kind != .mesh {
                HStack {
                    Picker("Duration", selection: $duration) {
                        Text("2 seconds").tag(2)
                        Text("4 seconds").tag(4)
                        Text("6 seconds").tag(6)
                    }
                    Picker("Smoothness", selection: $framesPerSecond) {
                        if kind == .gif { Text("5 fps").tag(5) }
                        Text("10 fps").tag(10)
                        if kind == .movie {
                            Text("20 fps").tag(20)
                            Text("30 fps").tag(30)
                        }
                    }
                }
                .disabled(job.isRunning || job.output != nil)
                Toggle("Larger image (864 × 864)", isOn: $highResolution)
                    .disabled(job.isRunning || job.output != nil)
                Text(highResolution ? "96 columns × 48 rows" : "576 × 648 pixels · 64 columns × 36 rows")
                    .font(.caption).foregroundStyle(Brand.secondary)
            }
            if job.isRunning {
                ProgressView(value: job.progress)
                Text("Rendering rotation… \(Int(job.progress * 100))%")
                    .font(.caption).monospacedDigit()
            } else if let error = job.error {
                Text(error).font(.callout).foregroundStyle(.red)
            } else if job.output != nil {
                Text("Your export is ready. Choose where to save it.").font(.callout)
            } else {
                Text("Choose where to save when rendering finishes.")
                    .font(.caption).foregroundStyle(Brand.secondary)
            }
            HStack {
                Button(job.isRunning ? "Cancel export" : "Close") {
                    if job.isRunning { job.cancel() } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(job.output == nil ? "Export" : "Save export…") {
                    if job.output != nil {
                        choosingDestination = true
                    } else {
                        job.start(
                            sculpture: sculpture,
                            camera: camera,
                            style: style,
                            opacity: opacity,
                            kind: kind,
                            duration: duration,
                            framesPerSecond: framesPerSecond,
                            columns: highResolution ? 96 : 64,
                            rows: highResolution ? 48 : 36
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(job.isRunning || (job.output != nil && exportDocument == nil))
            }
        }
        .padding(28)
        .frame(width: 510)
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
        .tint(Brand.accent)
        .interactiveDismissDisabled(job.isRunning)
        .onChange(of: kind) { _, _ in framesPerSecond = 10 }
        .task(id: job.output) {
            guard let output = job.output else { exportDocument = nil; return }
            do {
                let data = try await Task.detached {
                    try Data(contentsOf: output, options: .mappedIfSafe)
                }.value
                guard !Task.isCancelled, job.output == output else { return }
                exportDocument = SculptureExport(data: data)
                choosingDestination = true
            } catch { job.reportSaveError(error) }
        }
        .fileExporter(
            isPresented: $choosingDestination,
            document: exportDocument,
            contentTypes: [kind.contentType],
            defaultFilename: job.output?.lastPathComponent
        ) { result in
            switch result {
            case .success(let url):
                completed(url)
                job.cleanup()
                dismiss()
            case .failure(let error):
                // The generated file stays available for another save attempt.
                job.reportSaveError(error)
            }
        } onCancellation: {
            choosingDestination = false
        }
        .onDisappear { job.cleanup() }
    }
}

extension SculptureExportJob {
    func reportSaveError(_ error: any Error) { self.error = error.localizedDescription }
}
