import Foundation
import Observation
import RookSculpture

internal struct SculpturePreparedSave: Sendable {
    let id = UUID()
    let documentGeneration: UUID
    let sculpture: Sculpture
    let format: SculptureStorageFormat
    let data: Data
}

/// Prepare an immutable file away from the main actor; only the native panel writes it.
@MainActor
@Observable
internal final class SculptureSaveJob {
    private(set) var isRunning = false
    private(set) var result: SculpturePreparedSave?
    private(set) var error: String?
    @ObservationIgnored private var worker: Task<SculpturePreparedSave, any Error>?
    @ObservationIgnored private var generation = UUID()

    func start(_ sculpture: Sculpture, format: SculptureStorageFormat, documentGeneration: UUID) {
        guard !isRunning else { return }
        cancel()
        let identifier = UUID()
        generation = identifier
        isRunning = true
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try SculptureDocumentCodec.encode(sculpture, format: format)
            try Task.checkCancellation()
            return SculpturePreparedSave(
                documentGeneration: documentGeneration,
                sculpture: sculpture,
                format: format,
                data: data
            )
        }
        worker = task
        Task { [weak self] in
            do {
                let result = try await task.value
                guard let self, self.generation == identifier else { return }
                self.result = result
                self.isRunning = false
                self.worker = nil
            } catch {
                guard let self, self.generation == identifier else { return }
                self.error = error is CancellationError ? nil : error.localizedDescription
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

internal enum SculptureGraphDocument: Equatable, Sendable {
    case composition(SculptureComposition), world(SculptureWorld)

    var title: String {
        switch self {
        case .composition(let document): document.title
        case .world(let document): document.title
        }
    }

    func encoded() throws -> Data {
        switch self {
        case .composition(let document): try SculptureCompositionCodec.encode(document)
        case .world(let document): try SculptureWorldCodec.encode(document)
        }
    }
}

internal struct SculpturePreparedGraph: Sendable {
    let id = UUID()
    let document: SculptureGraphDocument
    let data: Data
}

/// Native save panels temporarily dismiss the reference sheet, but keep its exact editing session alive.
@MainActor
internal enum SculptureReferenceDraft {
    case composition(SculptureCompositionDraft), world(SculptureWorldDraft)

    var hasChanges: Bool {
        switch self {
        case .composition(let draft): draft.hasChanges
        case .world(let draft): draft.hasChanges
        }
    }

    func document() throws -> SculptureGraphDocument {
        switch self {
        case .composition(let draft): .composition(try draft.composition())
        case .world(let draft): .world(try draft.world())
        }
    }
}

/// The exact immutable graph prepared for writing is the only graph that may become the saved baseline.
@MainActor
internal final class SculptureReferenceSaveSession {
    let draft: SculptureReferenceDraft
    let document: SculptureGraphDocument
    private(set) var isFinished = false

    init(draft: SculptureReferenceDraft) throws {
        self.draft = draft
        document = try draft.document()
    }

    func finish(written: Bool) -> SculptureReferenceDraft {
        guard !isFinished else { return draft }
        isFinished = true
        if written {
            switch (draft, document) {
            case (.composition(let draft), .composition(let snapshot)): draft.markSaved(snapshot)
            case (.world(let draft), .world(let snapshot)): draft.markSaved(snapshot)
            default: preconditionFailure("A reference save must retain the same document kind.")
            }
        }
        return draft
    }
}

/// Graph saves preserve an immutable reference document independently of the voxel workspace.
@MainActor
@Observable
internal final class SculptureGraphSaveJob {
    private(set) var isRunning = false
    private(set) var result: SculpturePreparedGraph?
    private(set) var error: String?
    @ObservationIgnored private var worker: Task<SculpturePreparedGraph, any Error>?
    @ObservationIgnored private var generation = UUID()

    func start(_ document: SculptureGraphDocument) {
        cancel()
        let identifier = UUID()
        generation = identifier
        isRunning = true
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try document.encoded()
            try Task.checkCancellation()
            return SculpturePreparedGraph(document: document, data: data)
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
                self.error = error is CancellationError ? nil : error.localizedDescription
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
