import Darwin
import Foundation
import Observation
import RookSculpture
import ThreeMD

internal enum SculpturePortableFormat: String, Sendable {
    case readable, binary

    func encode(_ snapshot: SculptureThreeMDSnapshot) throws -> Data {
        try SculptureThreeMDCodec.encode(snapshot, format: self == .readable ? .text : .binary(compression: .none))
    }
}

internal enum SculpturePortableDiagnostic {
    static func message(_ error: any Error) -> String {
        SculptureDiagnosticMessage.describe(error)
    }
}

internal struct SculpturePortableModelResult: Sendable {
    let snapshot: SculptureThreeMDSnapshot?
    let scene: SculptureScene
    var usedLegacyCapacityFallback: Bool { snapshot == nil }
}

/// UUID guards remain with the native draft; the core transaction also checks its exact captured revision.
internal enum SculpturePortableModelEditing {
    static func replace(
        scene: SculptureScene,
        preserving snapshot: SculptureThreeMDSnapshot?,
        modelID: String,
        expected: Sculpture,
        replacement: Sculpture
    ) throws -> SculpturePortableModelResult {
        try Task.checkCancellation()
        let legacy: SculptureScene
        switch scene {
        case .composition(let parent):
            legacy = .composition(
                try SculptureModelEditing.replacingVoxelModel(
                    in: parent,
                    modelID: modelID,
                    expected: expected,
                    with: replacement
                )
            )
        case .world(let parent):
            legacy = .world(
                try SculptureModelEditing.replacingVoxelModel(
                    in: parent,
                    modelID: modelID,
                    expected: expected,
                    with: replacement
                )
            )
        case .voxels:
            throw SculptureModelEditingError.voxelModelRequired(modelID)
        }
        do {
            let current = try SculptureThreeMDCodec.capture(scene, preserving: snapshot)
            let edited = try SculptureThreeMDEditing.replacingVoxelModel(
                in: current,
                modelID: modelID,
                expectedRevision: current.revision,
                with: replacement
            )
            try Task.checkCancellation()
            return SculpturePortableModelResult(snapshot: edited, scene: edited.scene)
        } catch {
            guard SculptureThreeMDCodec.isCapacityError(error) else { throw error }
            try Task.checkCancellation()
            return SculpturePortableModelResult(snapshot: nil, scene: legacy)
        }
    }
}

internal struct SculpturePreparedPortable: Sendable {
    let id = UUID()
    let scene: SculptureScene
    let snapshot: SculptureThreeMDSnapshot
    let format: SculpturePortableFormat
    let data: Data
    let documentGeneration: UUID
}

/// A portable export prepares a copy and never changes a native saved baseline or storage format.
@MainActor
@Observable
internal final class SculpturePortableSaveJob {
    private(set) var isRunning = false
    private(set) var result: SculpturePreparedPortable?
    private(set) var error: String?
    @ObservationIgnored private var worker: Task<SculpturePreparedPortable, any Error>?
    @ObservationIgnored private var generation = UUID()

    func start(
        _ scene: SculptureScene,
        preserving snapshot: SculptureThreeMDSnapshot? = nil,
        format: SculpturePortableFormat,
        documentGeneration: UUID
    ) {
        cancel()
        let identifier = UUID()
        generation = identifier
        isRunning = true
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let captured = try SculptureThreeMDCodec.capture(scene, preserving: snapshot)
            let data = try format.encode(captured)
            try Task.checkCancellation()
            return SculpturePreparedPortable(
                scene: scene,
                snapshot: captured,
                format: format,
                data: data,
                documentGeneration: documentGeneration
            )
        }
        worker = task
        Task { [weak self] in
            do {
                let prepared = try await task.value
                guard let self, self.generation == identifier else { return }
                self.result = prepared
                self.isRunning = false
                self.worker = nil
            } catch {
                guard let self, self.generation == identifier else { return }
                self.error = error is CancellationError ? nil : SculpturePortableDiagnostic.message(error)
                self.isRunning = false
                self.worker = nil
            }
        }
    }

    func cancel() {
        generation = UUID()
        worker?.cancel()
        worker = nil
        isRunning = false
        result = nil
        error = nil
    }
}

internal struct SculptureOpenedScene: Sendable {
    let scene: SculptureScene
    let snapshot: SculptureThreeMDSnapshot?

    static func read(_ url: URL) throws -> Self {
        try decode(readData(url))
    }

    static func readData(_ url: URL, maximumBytes: Int = SculptureDocumentCodec.maximumBytes) throws -> Data {
        try Task.checkCancellation()
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw OpenFailure.invalidFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
            information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
        else { throw OpenFailure.invalidFile }
        let maximum = min(maximumBytes, SculptureDocumentCodec.maximumBytes)
        guard maximum > 0 else { throw SculptureError.oversizedFile }
        guard information.st_size <= maximum else { throw SculptureError.oversizedFile }
        var data = Data()
        while data.count <= maximum {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: min(65_536, maximum + 1 - data.count)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw SculptureError.oversizedFile
    }

    private enum OpenFailure: LocalizedError {
        case invalidFile
        var errorDescription: String? { "Choose a readable regular 3md or 3mdb file." }
    }

    static func decode(_ data: Data) throws -> Self {
        let opened = try SculptureSceneReader.decode(data)
        return Self(scene: opened.scene, snapshot: opened.snapshot)
    }
}
