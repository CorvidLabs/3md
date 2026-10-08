import Foundation
import Observation
import RookSculpture

/// The Examples gallery: every catalog entry grouped by kind and category, bounded thumbnails, and one cancellable
/// opening at a time. Listing reads catalog metadata only. Nothing is generated until a thumbnail or an opening asks
/// for that one entry, and only small voxel models load their thumbnails without being asked.
@MainActor
@Observable
internal final class SculptureGalleryBrowserModel {
    /// Creates one entry's scene and reports its completed fraction.
    internal typealias Generate =
        @Sendable (SculptureGalleryEntry, @escaping @Sendable (Double) async -> Void) async throws -> SculptureScene
    /// Prepares a created scene for the editor that opens it. Runs on a worker.
    internal typealias Prepare = @Sendable (SculptureGalleryEntry, SculptureScene) throws -> SculptureGalleryOpened

    /// The category filter value that shows every category.
    nonisolated internal static let allCategories = "All examples"

    /// Placement counts of the built-in worlds, so their sizes show without generating them. A test generates every
    /// world entry and compares.
    nonisolated internal static let placementCounts: [String: Int] = [
        "gardens-wide-world": 4,
        "blockhaven-world": 36,
        "solid-1024-world": 4_096,
        "skyreach-1024-world": 280,
    ]

    /// Entries of one kind and category, in catalog order.
    internal struct Section: Identifiable, Equatable {
        internal let kind: SculptureGalleryKind
        internal let category: String
        internal let entries: [SculptureGalleryEntry]

        internal var id: String { "\(kind.rawValue).\(category)" }
        internal var title: String { "\(SculptureGalleryBrowserModel.title(for: kind)) · \(category)" }
    }

    /// The visible step of an opening.
    internal enum Stage: Equatable, Sendable {
        case generating
        case preparingGeometry

        internal var label: String {
            switch self {
            case .generating: "Generating"
            case .preparingGeometry: "Preparing geometry"
            }
        }
    }

    /// The opening in progress.
    internal struct Loading: Equatable {
        internal let entry: SculptureGalleryEntry
        internal fileprivate(set) var stage: Stage
        /// The completed fraction of this stage, or nil while it is not known.
        internal fileprivate(set) var fraction: Double?

        /// The stage, with its percentage when known.
        internal var description: String {
            guard let fraction else { return "\(stage.label)…" }
            return "\(stage.label) \(Int((fraction * 100).rounded(.down)))%"
        }
    }

    /// One entry's thumbnail.
    internal enum Preview {
        /// Rendering for the request with this token. Only that request's worker may publish or clear the thumbnail.
        case loading(UUID)
        case ready(SculptureGalleryPreviewImage)
        case failed(String)
    }

    /// One queued thumbnail and the token of the request that asked for it.
    private struct PreviewRequest {
        let entry: SculptureGalleryEntry
        let token: UUID
    }


    // MARK: - Properties

    internal let entries: [SculptureGalleryEntry]
    internal var search = ""
    /// Nil shows every kind. A category that the chosen kind does not have falls back to every category.
    internal var kind: SculptureGalleryKind? {
        didSet { if !categories.contains(category) { category = Self.allCategories } }
    }
    internal var category = SculptureGalleryBrowserModel.allCategories
    internal private(set) var loading: Loading?
    internal private(set) var error: String?
    internal private(set) var previews: [String: Preview] = [:]
    /// The running opening, for callers that wait for it to settle.
    @ObservationIgnored internal private(set) var openTask: Task<Void, Never>?
    @ObservationIgnored private let generate: Generate
    @ObservationIgnored private let prepare: Prepare
    @ObservationIgnored private var openGeneration = UUID()
    @ObservationIgnored private var previewQueue: [PreviewRequest] = []
    @ObservationIgnored private var previewPump: Task<Void, Never>?
    @ObservationIgnored private var previewPumpID = UUID()
    @ObservationIgnored private var previewWorker:
        (request: PreviewRequest, task: Task<SculptureGalleryPreviewImage, any Error>)?


    // MARK: - Initializers

    /// Lists the given entries. Tests inject the factory and preparation; the app uses the catalog's.
    internal init(
        entries: [SculptureGalleryEntry] = SculptureGalleryCatalog.entries,
        generate: @escaping Generate = { entry, progress in
            try await SculptureGalleryCatalog.scene(for: entry, progress: progress)
        },
        prepare: @escaping Prepare = { entry, scene in try SculptureGalleryOpened.prepare(entry, scene: scene) }
    ) {
        self.entries = entries
        self.generate = generate
        self.prepare = prepare
    }


    // MARK: - Listing

    /// Every category of the chosen kind, after the value that shows them all.
    internal var categories: [String] {
        let names = Set(entries.filter { kind == nil || $0.kind == kind }.map(\.category))
        return [Self.allCategories] + names.sorted()
    }

    /// The filtered entries grouped by kind, then category, in catalog order.
    internal var sections: [Section] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var order: [String] = []
        var grouped: [String: (kind: SculptureGalleryKind, category: String, entries: [SculptureGalleryEntry])] = [:]
        for entry in entries where matches(entry, query: query) {
            let key = "\(entry.kind.rawValue).\(entry.category)"
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = (entry.kind, entry.category, [])
            }
            grouped[key]?.entries.append(entry)
        }
        return order.compactMap { key in
            grouped[key].map { Section(kind: $0.kind, category: $0.category, entries: $0.entries) }
        }
    }

    /// Cells on each axis, and placements for a world, for example "192 × 64 × 192 cells · 36 placements".
    nonisolated internal static func sizeLabel(for entry: SculptureGalleryEntry) -> String {
        let cells = cellsLabel(for: entry)
        guard let placements = placementLabel(for: entry) else { return cells }
        return "\(cells) · \(placements)"
    }

    /// Cells on each axis, for example "256 × 256 × 256 cells".
    nonisolated internal static func cellsLabel(for entry: SculptureGalleryEntry) -> String {
        let extent = entry.extent
        return "\(grouped(extent.width)) × \(grouped(extent.height)) × \(grouped(extent.depth)) cells"
    }

    /// A world's placement count, for example "36 placements"; nil for other kinds.
    nonisolated internal static func placementLabel(for entry: SculptureGalleryEntry) -> String? {
        guard entry.kind == .world, let count = placementCounts[entry.id] else { return nil }
        return "\(grouped(count)) \(count == 1 ? "placement" : "placements")"
    }

    /// The same size for speech, with "by" between the axes.
    nonisolated internal static func spokenSize(for entry: SculptureGalleryEntry) -> String {
        let extent = entry.extent
        let cells = "\(grouped(extent.width)) by \(grouped(extent.height)) by \(grouped(extent.depth)) cells"
        guard let placements = placementLabel(for: entry) else { return cells }
        return "\(cells), \(placements)"
    }

    /// A whole number with comma thousands separators, matching the catalog's prose.
    nonisolated internal static func grouped(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index).isMultiple(of: 3) { result.append(",") }
            result.append(character)
        }
        return value < 0 ? "-" + result : result
    }

    /// The plural heading for a kind.
    nonisolated internal static func title(for kind: SculptureGalleryKind) -> String {
        switch kind {
        case .model: "Models"
        case .composition: "Compositions"
        case .world: "Worlds"
        }
    }

    /// Which editor opens an entry, for its Open button.
    nonisolated internal static func openLabel(for entry: SculptureGalleryEntry) -> String {
        switch entry.kind {
        case .model: "Open"
        case .composition: "Open composition"
        case .world: "Open world"
        }
    }


    // MARK: - Previews

    /// Small voxel models show their thumbnail as soon as their card appears. Every other entry waits for Load preview.
    internal func loadsPreviewAutomatically(_ entry: SculptureGalleryEntry) -> Bool {
        let extent = entry.extent
        return entry.kind == .model
            && max(extent.width, extent.height, extent.depth) <= SculptureGalleryPreview.maximumAxis
    }

    /// Queues one thumbnail, rendered on a worker one at a time. A request the person makes goes first. An automatic
    /// request for an entry that is not small is ignored.
    /// - Parameters:
    ///   - entry: The entry to preview.
    ///   - explicitly: True when the person pressed Load preview.
    internal func requestPreview(_ entry: SculptureGalleryEntry, explicitly: Bool = false) {
        switch previews[entry.id] {
        case .loading?, .ready?: return
        case .failed?, nil: break
        }
        guard explicitly || loadsPreviewAutomatically(entry) else { return }
        let request = PreviewRequest(entry: entry, token: UUID())
        previews[entry.id] = .loading(request.token)
        if explicitly { previewQueue.insert(request, at: 0) } else { previewQueue.append(request) }
        pumpPreviews()
    }

    /// Stops one thumbnail and forgets it, so its card offers Load preview again. A worker that is still finishing
    /// for it never touches a later request for the same entry.
    internal func cancelPreview(_ id: String) {
        previewQueue.removeAll { $0.entry.id == id }
        if previewWorker?.request.entry.id == id { previewWorker?.task.cancel() }
        previews[id] = nil
    }

    /// Waits until every queued thumbnail has finished or been cancelled.
    internal func settlePreviews() async {
        while let pump = previewPump { await pump.value }
    }


    // MARK: - Opening

    /// Generates and prepares one entry on a worker, then hands it to `deliver`. Starting another opening or
    /// cancelling discards this one, and nothing is delivered for it.
    /// - Parameters:
    ///   - entry: The entry to open.
    ///   - deliver: Receives the prepared scene on the main actor, once.
    internal func open(
        _ entry: SculptureGalleryEntry,
        then deliver: @escaping @MainActor (SculptureGalleryOpened) -> Void
    ) {
        cancelOpening()
        let generation = UUID()
        openGeneration = generation
        error = nil
        // Math ladder entries report progress per layer or tile; authored entries only start and finish.
        loading = Loading(entry: entry, stage: .generating, fraction: entry.formula == nil ? nil : 0)
        let generate = generate
        let prepare = prepare
        let progress: @Sendable (Double) async -> Void = { [weak self] fraction in
            // Never wait for the main actor inside the generator; late reports are ignored by generation.
            Task { @MainActor in self?.receive(fraction, generation: generation) }
        }
        let enterPreparation: @Sendable () async -> Void = { [weak self] in
            await self?.enterPreparation(generation: generation)
        }
        let worker = Task.detached(priority: .userInitiated) { () throws -> SculptureGalleryOpened in
            let scene = try await generate(entry, progress)
            try Task.checkCancellation()
            await enterPreparation()
            return try prepare(entry, scene)
        }
        openTask = Task { [weak self] in
            let result = await withTaskCancellationHandler {
                await worker.result
            } onCancel: {
                worker.cancel()
            }
            guard let self, self.openGeneration == generation, !Task.isCancelled else { return }
            self.loading = nil
            self.openTask = nil
            switch result {
            case .success(let opened): deliver(opened)
            case .failure(let failure):
                guard !(failure is CancellationError) else { return }
                self.error = "\(entry.title) couldn’t open. \(failure.localizedDescription)"
            }
        }
    }

    /// Stops the opening. Its scene is discarded and nothing is delivered.
    internal func cancelOpening() {
        openGeneration = UUID()
        openTask?.cancel()
        openTask = nil
        loading = nil
    }

    /// Stops the opening and every thumbnail, then closes the gallery. Done uses this, so nothing that finishes while
    /// the sheet is leaving is delivered or published.
    /// - Parameter dismiss: Closes the gallery. It runs after every opening and thumbnail has been stopped.
    internal func close(then dismiss: () -> Void) {
        cancelAll()
        dismiss()
    }

    /// Stops the opening and every thumbnail, as when the gallery closes.
    internal func cancelAll() {
        cancelOpening()
        previewQueue.removeAll()
        previewWorker?.task.cancel()
        previewWorker = nil
        previewPump?.cancel()
        previewPump = nil
        previewPumpID = UUID()
        previews = previews.filter { _, preview in
            if case .loading = preview { false } else { true }
        }
    }

    /// Clears the last opening failure.
    internal func dismissError() { error = nil }


    // MARK: - Private Methods

    private func matches(_ entry: SculptureGalleryEntry, query: String) -> Bool {
        guard kind == nil || entry.kind == kind else { return false }
        guard category == Self.allCategories || entry.category == category else { return false }
        guard !query.isEmpty else { return true }
        let text = "\(entry.title) \(entry.summary) \(entry.category) \(Self.sizeLabel(for: entry))"
        return text.localizedCaseInsensitiveContains(query)
    }

    private func receive(_ fraction: Double, generation: UUID) {
        guard generation == openGeneration, var loading, loading.stage == .generating,
            let current = loading.fraction
        else { return }
        loading.fraction = min(1, max(current, fraction))
        self.loading = loading
    }

    private func enterPreparation(generation: UUID) {
        guard generation == openGeneration, var loading else { return }
        loading.stage = .preparingGeometry
        loading.fraction = nil
        self.loading = loading
    }

    private func pumpPreviews() {
        guard previewPump == nil else { return }
        let identity = UUID()
        previewPumpID = identity
        previewPump = Task { [weak self] in
            while !Task.isCancelled, let self, let request = self.dequeuePreview() {
                await self.renderPreview(request)
            }
            guard let self, self.previewPumpID == identity else { return }
            self.previewPump = nil
        }
    }

    private func dequeuePreview() -> PreviewRequest? {
        previewQueue.isEmpty ? nil : previewQueue.removeFirst()
    }

    private func renderPreview(_ request: PreviewRequest) async {
        let generate = generate
        let entry = request.entry
        let worker = Task.detached(priority: .utility) { () throws -> SculptureGalleryPreviewImage in
            let scene = try await generate(entry) { _ in }
            return SculptureGalleryPreviewImage(image: try SculptureGalleryPreview.image(of: scene, entry: entry))
        }
        previewWorker = (request, worker)
        let result = await worker.result
        if previewWorker?.request.token == request.token { previewWorker = nil }
        // Only the request that started this worker publishes. A cancelled or forgotten thumbnail, or one the person
        // has asked for again since, is left alone; the newer request renders and publishes on its own.
        guard case .loading(let current)? = previews[entry.id], current == request.token else { return }
        switch result {
        case .success(let image): previews[entry.id] = .ready(image)
        case .failure(let failure):
            previews[entry.id] = failure is CancellationError ? nil : .failed(failure.localizedDescription)
        }
    }
}
