import Foundation
import Observation
import RookRendering
import RookSculpture
import SwiftUI
import UniformTypeIdentifiers

internal enum SculptureCompositionBrush: String, CaseIterable, Identifiable {
    case select = "Select"
    case place = "Place model"
    case erase = "Erase tile"
    var id: Self { self }
}

internal struct SculptureCompositionInsertionTarget: Identifiable, Sendable {
    let cell: SculptureCell
    let incomingTitle: String
    let currentGlyph: UInt8
    let currentTitle: String?
    var id: SculptureCell { cell }
    var location: String { SculptureCompositionInsertionTarget.location(of: cell) }

    static func location(of cell: SculptureCell) -> String {
        "column \(cell.x + 1), row \(cell.y + 1), layer \(cell.z + 1)"
    }
}

internal struct SculptureCompositionInsertionConfirmation: Identifiable, Sendable {
    let id = UUID()
    let parent: SculptureComposition
    let parentSnapshot: SculptureThreeMDSnapshot?
    let parentRevision: UUID
    let start: SculptureCell
    let result: SculptureInsertionResult
    let targets: [SculptureCompositionInsertionTarget]
    var replacementCount: Int { targets.filter { $0.currentGlyph != Sculpture.empty }.count }
    var question: String {
        "Replace \(SculptureInsertionWording.count(replacementCount, "occupied tile"))?"
    }
    var targetSummary: String {
        guard let first = targets.first, let last = targets.last else { return "" }
        return
            "\(SculptureInsertionWording.count(targets.count, "model")), from \(first.location) through \(last.location)."
    }
}

internal struct SculptureCompositionLibraryItem: Identifiable {
    let binding: SculptureModelBinding
    let title: String
    let dimensions: String
    /// The project file that defines the model, in a linked session.
    var path: String? = nil
    var id: UInt8 { binding.glyph }
    var character: String { String(UnicodeScalar(binding.glyph)) }
}

private enum CompositionDraftError: LocalizedError {
    case noAvailableLetter
    case occupiedResize
    case expandedBounds
    case modelDoesNotFit(String, Int, Int, Int)
    case viewOnly

    var errorDescription: String? {
        switch self {
        case .viewOnly: SculptureCompositionDraft.viewOnlyExplanation
        case .noAvailableLetter: "The model library is full. Start another composition."
        case .occupiedResize: "Erase tiles outside the new map size before shrinking it."
        case .expandedBounds: "The expanded map exceeds 256 cells on an axis. Reduce the map or tile size."
        case .modelDoesNotFit(let title, let width, let height, let depth):
            "\(title) needs a tile of at least \(width) × \(height) × \(depth) cells after rotation. Increase the tile size or choose a smaller model."
        }
    }
}

private struct CompositionDraftSnapshot: Equatable {
    let title: String
    let rootID: String
    let width: Int
    let height: Int
    let layers: [[UInt8]]
    let tileWidth: Int
    let tileHeight: Int
    let tileDepth: Int
    let models: [String: SculptureCompositionModel]
    let bindings: [SculptureModelBinding]
    let selectedGlyph: UInt8
    let selectedCell: SculptureCell
    let portableSnapshot: SculptureThreeMDSnapshot?
    let holdsPortableData: Bool

    func hasSameDocument(as other: Self) -> Bool {
        title == other.title && rootID == other.rootID && width == other.width && height == other.height
            && layers == other.layers && tileWidth == other.tileWidth && tileHeight == other.tileHeight
            && tileDepth == other.tileDepth && models == other.models && bindings == other.bindings
    }
}

/// The draft retains the complete model graph. Only an explicit expansion produces detached editable voxels.
@MainActor
@Observable
internal final class SculptureCompositionDraft {
    private(set) var title = "Model garden"
    private(set) var width = 3
    private(set) var height = 3
    private(set) var layers = [[UInt8]]()
    private(set) var tileWidth = 24
    private(set) var tileHeight = 24
    private(set) var tileDepth = 24
    private(set) var rootID = "root"
    private(set) var models: [String: SculptureCompositionModel] = [:]
    private(set) var bindings: [SculptureModelBinding] = []
    private(set) var selectedGlyph: UInt8 = 65
    private(set) var selectedCell = SculptureCell(x: 0, y: 0, z: 0)
    private(set) var preview: Sculpture?
    private(set) var error: String?
    private(set) var isPreparing = false
    private(set) var sharedEdit: SculptureSharedModelSession?
    private(set) var portableSnapshot: SculptureThreeMDSnapshot?
    /// Whether the person has portable ThreeMD data to preserve: the draft was opened or handed off with a
    /// snapshot, exported one, or inserted an input that carried one. A snapshot minted by a shared edit is not
    /// data the person has, so it never forces a later insertion down the portable path. Undo and Redo restore it.
    private(set) var holdsPortableData: Bool
    private(set) var editingNotice: String?
    private(set) var pendingInsertion: SculptureCompositionInsertionConfirmation?
    /// The importer the sheet should present, set by its buttons, the File menu and the command palette.
    private(set) var insertionRequest: SculptureInsertionKind?
    /// Names the first and last tiles of the latest insertion, so a batch that wrapped is never silent.
    private(set) var insertionNotice: String?
    private(set) var revision = UUID()
    /// A linked session's composition. Only the selection and the preview change; edits, insertion, shared-model
    /// edits, editable voxels, world handoff and saving are refused.
    private(set) var isViewOnly = false
    /// Model ID to the project file that defines it, in a linked session.
    private(set) var modelPaths: [String: String] = [:]
    var brush = SculptureCompositionBrush.place
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var preparationID = UUID()
    @ObservationIgnored private var baseline: CompositionDraftSnapshot?
    @ObservationIgnored private var lastSnapshot: CompositionDraftSnapshot?
    @ObservationIgnored private var undoHistory: [CompositionDraftSnapshot] = []
    @ObservationIgnored private var redoHistory: [CompositionDraftSnapshot] = []
    /// Observed counter so menus and views that read `canUndo` or `canRedo` refresh when a history stack changes.
    private var historyVersion = 0
    private var initiallyUnsaved = false

    init(composition: SculptureComposition? = nil, portableSnapshot: SculptureThreeMDSnapshot? = nil) {
        self.portableSnapshot = portableSnapshot
        holdsPortableData = portableSnapshot != nil
        layers = [Array(repeating: Sculpture.empty, count: width * height)]
        if let composition {
            load(composition)
        } else {
            for example in SculptureExamples.compositionStarters.prefix(2) {
                do { try addModel(.sculpture(example.sculpture), id: example.id) } catch {
                    self.error = error.localizedDescription
                }
            }
            if bindings.count == 2 {
                let a = bindings[0].glyph, b = bindings[1].glyph
                layers = [[a, Sculpture.empty, b, Sculpture.empty, a, Sculpture.empty, b, Sculpture.empty, a]]
            }
            selectedGlyph = bindings.first?.glyph ?? 65
        }
        baseline = snapshot
        lastSnapshot = snapshot
    }

    /// An empty 4 × 4 × 4 grid of 64-cell tiles (256 cells per axis, 64 free tiles), so a command that starts by
    /// inserting files never replaces a starter model and a folder of up to 63 models still fits. A model larger
    /// than a tile is refused with its required and current sizes.
    static func insertionCanvas() -> SculptureCompositionDraft {
        guard
            let tileSize = try? SculptureTileSize(width: 64, height: 64, depth: 64),
            let map = try? SculptureTileMap(
                width: 4,
                height: 4,
                layers: Array(repeating: Array(repeating: Sculpture.empty, count: 16), count: 4),
                tileSize: tileSize,
                bindings: []
            ),
            let composition = try? SculptureComposition(
                title: "Inserted models",
                rootID: "root",
                models: ["root": .tiles(map)]
            )
        else { return SculptureCompositionDraft() }
        return SculptureCompositionDraft(composition: composition)
    }

    /// The short explanation shown wherever a linked session refuses an action.
    nonisolated static let viewOnlyExplanation =
        "Linked compositions are view only in this version. Painting, insertion, shared-model edits, world handoff "
        + "and saving are unavailable; Reload Linked Files picks up changes to the files."

    /// A view-only draft of a resolved linked composition, with the project file of each model.
    static func linkedView(_ composition: SculptureComposition, modelPaths: [String: String])
        -> SculptureCompositionDraft
    {
        let draft = SculptureCompositionDraft(composition: composition)
        draft.isViewOnly = true
        draft.brush = .select
        draft.modelPaths = modelPaths
        return draft
    }

    /// Shows a fresh resolution in a view-only draft. It is never recorded as an edit, so the draft stays unchanged
    /// and has no history. The selection is kept where it still exists.
    func showLinked(_ composition: SculptureComposition, modelPaths: [String: String]) {
        guard isViewOnly else { return }
        cancelPreparation()
        let cell = selectedCell
        let selected = selectedGlyph
        load(composition)
        if glyph(at: cell) != nil { selectedCell = cell }
        if bindings.contains(where: { $0.glyph == selected }) { selectedGlyph = selected }
        self.modelPaths = modelPaths
        portableSnapshot = nil
        holdsPortableData = false
        undoHistory.removeAll()
        redoHistory.removeAll()
        historyVersion += 1
        initiallyUnsaved = false
        baseline = snapshot
        lastSnapshot = snapshot
        revision = UUID()
        preview = nil
        error = nil
        editingNotice = nil
        insertionNotice = nil
    }

    var hasChanges: Bool { initiallyUnsaved || (baseline.map { !snapshot.hasSameDocument(as: $0) } ?? false) }
    var canUndo: Bool {
        _ = historyVersion
        return !undoHistory.isEmpty
    }
    var canRedo: Bool {
        _ = historyVersion
        return !redoHistory.isEmpty
    }
    /// The snapshot insertion preserves. A snapshot the person does not actually hold is never passed on.
    var insertionSnapshot: SculptureThreeMDSnapshot? { holdsPortableData ? portableSnapshot : nil }
    var isBusy: Bool { isPreparing || pendingInsertion != nil }
    var canUseInWorld: Bool { !isBusy && !isViewOnly }
    /// The explanation the header and every refused action show, or nil when the composition can be edited.
    internal var viewOnlyNotice: String? { isViewOnly ? Self.viewOnlyExplanation : nil }
    /// Insertion needs a settled, editable parent: no preparation, replacement decision or shared edit in progress.
    var canInsert: Bool { !isBusy && sharedEdit == nil && !isViewOnly }
    var insertionStartDescription: String {
        "Insertion start: column \(selectedCell.x + 1), row \(selectedCell.y + 1), layer \(selectedCell.z + 1)."
    }
    /// Voxel models that can be edited in place. Models that share a title and size are told apart by the
    /// character bound to each, or "unbound", so the menu never makes one look like another.
    var editableModels: [SculptureWorldModelChoice] {
        let choices = models.keys.sorted().compactMap { id -> SculptureWorldModelChoice? in
            guard case .sculpture(let sculpture) = models[id] else { return nil }
            return SculptureWorldModelChoice(
                id: id,
                title: sculpture.title,
                dimensions: "\(sculpture.width) × \(sculpture.height) × \(sculpture.depth)"
            )
        }
        return SculptureWorldModelChoice.disambiguating(choices) { choice in
            let glyphs = bindings.filter { $0.modelID == choice.id }.map { String(UnicodeScalar($0.glyph)) }
            return glyphs.isEmpty ? "unbound" : "bound to " + glyphs.joined(separator: ", ")
        }
    }
    var depth: Int { layers.count }
    var placementCount: Int { layers.reduce(0) { $0 + $1.filter { $0 != Sculpture.empty }.count } }
    var expandedDimensions: String { "\(width * tileWidth) × \(height * tileHeight) × \(depth * tileDepth)" }
    var rawRows: [String] {
        stride(from: 0, to: width * height, by: width).map { offset in
            String(decoding: layers[selectedCell.z][offset..<offset + width], as: UTF8.self)
        }
    }
    var selectedBinding: SculptureModelBinding? { bindings.first { $0.glyph == selectedGlyph } }
    var library: [SculptureCompositionLibraryItem] {
        bindings.map { binding in
            let model = models[binding.modelID]
            let title: String
            let dimensions: String
            switch model {
            case .sculpture(let sculpture):
                title = sculpture.title
                dimensions = "\(sculpture.width) × \(sculpture.height) × \(sculpture.depth)"
            case .tiles(let map):
                title =
                    portableSnapshot.flatMap {
                        SculptureThreeMDCodec.modelTitle(for: binding.modelID, in: $0)
                    } ?? "Nested map"
                dimensions =
                    "\(map.width * map.tileSize.width) × \(map.height * map.tileSize.height) × \(map.layers.count * map.tileSize.depth)"
            case nil:
                title = "Missing model"
                dimensions = binding.modelID
            }
            return SculptureCompositionLibraryItem(
                binding: binding,
                title: title,
                dimensions: dimensions,
                path: modelPaths[binding.modelID]
            )
        }
    }

    func setTitle(_ value: String) {
        guard title != value, !isViewOnly else { return }
        title = value
        changed()
    }

    func select(_ glyph: UInt8) {
        guard bindings.contains(where: { $0.glyph == glyph }) else { return }
        selectedGlyph = glyph
        brush = .place
    }

    func selectLayer(_ layer: Int) {
        guard layers.indices.contains(layer) else { return }
        selectCell(SculptureCell(x: selectedCell.x, y: selectedCell.y, z: layer))
    }

    func selectCell(_ cell: SculptureCell) {
        guard glyph(at: cell) != nil, cell != selectedCell else { return }
        cancelPreparation()
        selectedCell = cell
        lastSnapshot = snapshot
    }

    func glyph(at cell: SculptureCell) -> UInt8? {
        guard (0..<width).contains(cell.x), (0..<height).contains(cell.y), layers.indices.contains(cell.z) else {
            return nil
        }
        return layers[cell.z][cell.y * width + cell.x]
    }

    func paint(_ cell: SculptureCell) {
        guard let current = glyph(at: cell) else { return }
        selectCell(cell)
        guard brush != .select, !isViewOnly else { return }
        let replacement = brush == .erase ? Sculpture.empty : selectedGlyph
        guard replacement == Sculpture.empty || bindings.contains(where: { $0.glyph == replacement }),
            current != replacement
        else { return }
        layers[cell.z][cell.y * width + cell.x] = replacement
        changed()
    }

    func resize(width: Int, height: Int, depth: Int) {
        guard !isViewOnly else { return }
        guard (1...max(8, self.width)).contains(width), (1...max(8, self.height)).contains(height),
            (1...max(8, self.depth)).contains(depth)
        else { return }
        guard width * tileWidth <= 256, height * tileHeight <= 256, depth * tileDepth <= 256 else {
            error = CompositionDraftError.expandedBounds.localizedDescription
            return
        }
        guard width != self.width || height != self.height || depth != self.depth else { return }
        for z in layers.indices {
            for y in 0..<self.height {
                for x in 0..<self.width where z >= depth || y >= height || x >= width {
                    guard layers[z][y * self.width + x] == Sculpture.empty else {
                        error = CompositionDraftError.occupiedResize.localizedDescription
                        return
                    }
                }
            }
        }
        var resized = Array(repeating: Array(repeating: Sculpture.empty, count: width * height), count: depth)
        for z in 0..<min(depth, self.depth) {
            for y in 0..<min(height, self.height) {
                for x in 0..<min(width, self.width) {
                    resized[z][y * width + x] = layers[z][y * self.width + x]
                }
            }
        }
        self.width = width
        self.height = height
        layers = resized
        selectedCell = SculptureCell(
            x: min(selectedCell.x, width - 1),
            y: min(selectedCell.y, height - 1),
            z: min(selectedCell.z, depth - 1)
        )
        changed()
    }

    func setTileSize(width: Int, height: Int, depth: Int) {
        guard !isViewOnly else { return }
        guard (1...256).contains(width), (1...256).contains(height), (1...256).contains(depth) else { return }
        guard self.width * width <= 256, self.height * height <= 256, self.depth * depth <= 256 else {
            error = CompositionDraftError.expandedBounds.localizedDescription
            return
        }
        tileWidth = width
        tileHeight = height
        tileDepth = depth
        changed()
    }

    func rotateSelected(_ quarterTurns: Int) {
        guard !isViewOnly, let index = bindings.firstIndex(where: { $0.glyph == selectedGlyph }) else { return }
        do {
            bindings[index] = try SculptureModelBinding(
                glyph: selectedGlyph,
                modelID: bindings[index].modelID,
                quarterTurns: quarterTurns
            )
            changed()
        } catch { self.error = error.localizedDescription }
    }

    func addExample(_ example: SculptureExample) {
        guard !isViewOnly else { return }
        do {
            try addModel(.sculpture(example.sculpture), id: Self.newModelID())
            changed()
        } catch { self.error = error.localizedDescription }
    }

    /// Shows an assembled preview prepared away from the main actor, when it has the expanded bounds of the current,
    /// unchanged map and no preview or preparation is already showing.
    func adoptPreview(_ expanded: Sculpture) {
        guard preview == nil, !isPreparing, expanded.width == width * tileWidth,
            expanded.height == height * tileHeight, expanded.depth == depth * tileDepth
        else { return }
        preview = expanded
    }

    func replace(with composition: SculptureComposition) {
        guard !isViewOnly else { return }
        cancelPreparation()
        // A portable snapshot describes the replaced graph. Undo restores it with the previous document.
        if (try? self.composition()) != composition {
            portableSnapshot = nil
            holdsPortableData = false
        }
        load(composition)
        changed()
    }

    /// A portable export or save gives the person portable data, so later insertions preserve its identities.
    func retainPortableSnapshot(_ captured: SculptureThreeMDSnapshot) {
        guard !isViewOnly, case .composition(let scene) = captured.scene, (try? composition()) == scene else { return }
        cancelPreparation()
        portableSnapshot = captured
        holdsPortableData = true
        lastSnapshot = snapshot
    }

    func report(_ error: any Error) { self.error = SculpturePortableDiagnostic.message(error) }
    func markUnsaved() { if !isViewOnly { initiallyUnsaved = true } }

    /// Only the saved immutable graph becomes the baseline; newer draft edits remain dirty.
    func markSaved(_ saved: SculptureComposition) {
        guard case .tiles(let map) = saved.models[saved.rootID] else { return }
        var models = saved.models
        models.removeValue(forKey: saved.rootID)
        baseline = CompositionDraftSnapshot(
            title: saved.title,
            rootID: saved.rootID,
            width: map.width,
            height: map.height,
            layers: map.layers,
            tileWidth: map.tileSize.width,
            tileHeight: map.tileSize.height,
            tileDepth: map.tileSize.depth,
            models: models,
            bindings: map.bindings,
            selectedGlyph: selectedGlyph,
            selectedCell: selectedCell,
            portableSnapshot: portableSnapshot,
            holdsPortableData: holdsPortableData
        )
        initiallyUnsaved = false
    }

    func beginSharedEdit(modelID: String) {
        guard sharedEdit == nil else { return }
        guard !isViewOnly else { report(CompositionDraftError.viewOnly); return }
        do {
            let parent = try composition()
            guard case .sculpture(let sculpture) = parent.models[modelID] else {
                throw SculptureModelEditingError.voxelModelRequired(modelID)
            }
            cancelPreparation()
            sharedEdit = SculptureSharedModelSession(modelID: modelID, source: sculpture, parentRevision: revision)
            error = nil
        } catch { report(error) }
    }

    func cancelSharedEdit() { sharedEdit = nil }

    func applySharedEdit() async -> Bool {
        guard let session = sharedEdit, !session.isApplying, session.workspace.commitTitle() else { return false }
        session.isApplying = true
        defer { session.isApplying = false }
        do {
            let parent = try composition()
            let replacement = session.workspace.sculpture
            let modelID = session.modelID
            let expected = session.source
            let preserving = portableSnapshot
            let worker = Task.detached(priority: .userInitiated) {
                try SculpturePortableModelEditing.replace(
                    scene: .composition(parent),
                    preserving: preserving,
                    modelID: modelID,
                    expected: expected,
                    replacement: replacement
                )
            }
            let candidate = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            try Task.checkCancellation()
            guard sharedEdit?.id == session.id, revision == session.parentRevision,
                session.workspace.sculpture == replacement
            else {
                // The model changed while it was validated, so the validated result is stale. The session stays open.
                throw SculptureModelEditingError.expectedModelChanged(session.modelID)
            }
            guard case .composition(let edited) = candidate.scene else { return false }
            if edited != parent {
                let selection = selectedCell
                let glyph = selectedGlyph
                load(edited)
                portableSnapshot = candidate.snapshot
                selectedCell = selection
                selectedGlyph = glyph
                changed()
            }
            editingNotice =
                candidate.usedLegacyCapacityFallback
                ? "Applied in the native Sculpt format because this scene exceeds portable ThreeMD capacity." : nil
            sharedEdit = nil
            return true
        } catch is CancellationError { return false } catch {
            session.error = SculpturePortableDiagnostic.message(error)
            return false
        }
    }

    func undo() {
        guard !isViewOnly, let previous = undoHistory.popLast() else { return }
        redoHistory.append(snapshot)
        historyVersion += 1
        restore(previous)
    }

    func redo() {
        guard !isViewOnly, let next = redoHistory.popLast() else { return }
        undoHistory.append(snapshot)
        historyVersion += 1
        restore(next)
    }

    func composition() throws -> SculptureComposition {
        let tileSize = try SculptureTileSize(width: tileWidth, height: tileHeight, depth: tileDepth)
        let map = try SculptureTileMap(
            width: width,
            height: height,
            layers: layers,
            tileSize: tileSize,
            bindings: bindings
        )
        var graph = models
        graph[rootID] = .tiles(map)
        return try validateGraph(graph)
    }

    func prepare(open: (@MainActor (SculptureComposition, Sculpture) -> Void)? = nil) {
        // A preview assembles the map without changing it. Editable voxels are a route to painting and saving.
        if open != nil, isViewOnly { report(CompositionDraftError.viewOnly); return }
        cancelPreparation()
        do {
            let composition = try composition()
            let identifier = UUID()
            preparationID = identifier
            isPreparing = true
            error = nil
            preparation = Task { [weak self] in
                let worker = Task.detached(priority: .userInitiated) { try composition.expanded() }
                do {
                    let expanded = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    guard !Task.isCancelled, let self, self.preparationID == identifier else { return }
                    self.preview = expanded
                    self.isPreparing = false
                    self.preparation = nil
                    open?(composition, expanded)
                } catch {
                    guard !Task.isCancelled, let self, self.preparationID == identifier else { return }
                    self.error = error.localizedDescription
                    self.isPreparing = false
                    self.preparation = nil
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    // MARK: - Insertion

    /// Asks the sheet to present its importer. Ignored while a preparation, decision or shared edit is pending.
    func requestInsertion(_ kind: SculptureInsertionKind) {
        guard canInsert, insertionRequest == nil else { return }
        insertionRequest = kind
    }

    func finishInsertionRequest() { insertionRequest = nil }

    func importModel(from url: URL) { importModels(from: [url]) }

    func importModels(from urls: [URL]) {
        prepareInsertion { plan in try SculptureInsertionFiles.read(urls, plan: plan) }
    }

    func importFolder(from url: URL) {
        prepareInsertion { plan in try SculptureInsertionFiles.readFolder(url, plan: plan) }
    }

    /// Testable synchronous value publication uses the same immutable operation as file insertion.
    func insert(_ inputs: [SculptureInsertionInput]) throws {
        try Task.checkCancellation()
        guard !isViewOnly else { throw CompositionDraftError.viewOnly }
        cancelPreparation()
        let parent = try composition()
        let preserving = insertionSnapshot
        let parentRevision = revision
        let start = selectedCell
        let result = try SculptureSceneInsertion.intoComposition(
            parent,
            preserving: preserving,
            inputs: inputs,
            at: start
        )
        receiveInsertion(
            result,
            inputs: inputs,
            parent: parent,
            preserving: preserving,
            parentRevision: parentRevision,
            start: start
        )
    }

    @discardableResult
    func confirmInsertion(id: UUID) -> Bool {
        guard !Task.isCancelled else { cancelPendingInsertion(); return false }
        guard let pending = pendingInsertion, pending.id == id else { return false }
        guard revision == pending.parentRevision, insertionSnapshot == pending.parentSnapshot,
            selectedCell == pending.start, (try? composition()) == pending.parent
        else {
            cancelPendingInsertion()
            report(SculptureInsertionFiles.Failure.parentChanged)
            return false
        }
        pendingInsertion = nil
        applyInsertion(pending.result, targets: pending.targets)
        return true
    }

    func cancelPendingInsertion() { pendingInsertion = nil }

    /// Builds the world with this composition's portable data off the main actor, then hands it over once.
    func prepareWorldHandoff(then open: @escaping @MainActor (SculptureWorldHandoff) -> Void) {
        guard !isViewOnly else { report(CompositionDraftError.viewOnly); return }
        cancelPreparation()
        do {
            let composition = try composition()
            let preserving = insertionSnapshot
            let identifier = UUID()
            preparationID = identifier
            isPreparing = true
            error = nil
            preparation = Task { [weak self] in
                do {
                    let handoff = try await SculptureWorldHandoff.prepare(
                        composition: composition,
                        snapshot: preserving
                    )
                    guard !Task.isCancelled, let self, self.preparationID == identifier else { return }
                    self.isPreparing = false
                    self.preparation = nil
                    open(handoff)
                } catch {
                    guard !Task.isCancelled, let self, self.preparationID == identifier else { return }
                    self.report(error)
                    self.isPreparing = false
                    self.preparation = nil
                }
            }
        } catch { report(error) }
    }

    /// Names the first and last tile of a batch, and says when it continued onto another row or layer.
    static func insertionSummary(for cells: [SculptureCell]) -> String? {
        guard let first = cells.first, let last = cells.last else { return nil }
        let models = SculptureInsertionWording.count(cells.count, "model")
        let start = SculptureCompositionInsertionTarget.location(of: first)
        guard cells.count > 1 else { return "Inserted \(models) at \(start)." }
        var summary =
            "Inserted \(models) from \(start) through \(SculptureCompositionInsertionTarget.location(of: last))."
        if first.z != last.z {
            summary += " The batch continued into another layer."
        } else if first.y != last.y {
            summary += " The batch continued onto the next row."
        }
        return summary
    }

    private func receiveInsertion(
        _ result: SculptureInsertionResult,
        inputs: [SculptureInsertionInput],
        parent: SculptureComposition,
        preserving: SculptureThreeMDSnapshot?,
        parentRevision: UUID,
        start: SculptureCell
    ) {
        guard revision == parentRevision, insertionSnapshot == preserving, selectedCell == start,
            (try? composition()) == parent,
            let cells = try? SculptureSceneInsertion.targets(in: parent, count: inputs.count, at: start)
        else {
            report(SculptureInsertionFiles.Failure.parentChanged)
            return
        }
        error = nil
        let targets = zip(inputs, cells).map { input, cell in
            SculptureCompositionInsertionTarget(
                cell: cell.cell,
                incomingTitle: input.scene.title,
                currentGlyph: cell.currentGlyph,
                currentTitle: library.first { $0.id == cell.currentGlyph }?.title
            )
        }
        if targets.contains(where: { $0.currentGlyph != Sculpture.empty }) {
            pendingInsertion = .init(
                parent: parent,
                parentSnapshot: preserving,
                parentRevision: parentRevision,
                start: start,
                result: result,
                targets: targets
            )
        } else {
            applyInsertion(result, targets: targets)
        }
    }

    private func applyInsertion(
        _ result: SculptureInsertionResult,
        targets: [SculptureCompositionInsertionTarget]
    ) {
        guard case .composition(let candidate) = result.scene else { return }
        let cell = selectedCell
        load(candidate)
        selectedCell = cell
        if let last = result.placedRootIDs.last, let binding = bindings.first(where: { $0.modelID == last }) {
            selectedGlyph = binding.glyph
        }
        portableSnapshot = result.snapshot
        // The core returns a snapshot only when the parent or an input carried portable data.
        holdsPortableData = result.snapshot != nil
        changed()
        insertionNotice = Self.insertionSummary(for: targets.map(\.cell))
        if result.usedNativeFallback {
            editingNotice =
                "Inserted with native Sculpt values because this scene exceeds portable ThreeMD capacity."
        }
    }

    private func prepareInsertion(
        _ read: @escaping @Sendable (SculptureInsertionPlan) throws -> [SculptureInsertionInput]
    ) {
        guard !isViewOnly else { report(CompositionDraftError.viewOnly); return }
        cancelPreparation()
        do {
            let parent = try composition()
            let preserving = insertionSnapshot
            let cell = selectedCell
            let parentRevision = revision
            let plan = try SculptureInsertionPlan(composition: parent, at: cell)
            let identifier = UUID()
            preparationID = identifier
            isPreparing = true
            error = nil
            preparation = Task { [weak self] in
                let worker = Task.detached(priority: .userInitiated) {
                    let inputs = try read(plan)
                    let result = try SculptureSceneInsertion.intoComposition(
                        parent,
                        preserving: preserving,
                        inputs: inputs,
                        at: cell
                    )
                    return (result, inputs)
                }
                do {
                    let (result, inputs) = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    guard !Task.isCancelled, let self, self.preparationID == identifier else { return }
                    self.isPreparing = false
                    self.preparation = nil
                    self.receiveInsertion(
                        result,
                        inputs: inputs,
                        parent: parent,
                        preserving: preserving,
                        parentRevision: parentRevision,
                        start: cell
                    )
                } catch {
                    guard !Task.isCancelled, let self, self.preparationID == identifier else { return }
                    self.report(error)
                    self.isPreparing = false
                    self.preparation = nil
                }
            }
        } catch { report(error) }
    }

    func cancelPreparation() {
        cancelPendingInsertion()
        preparationID = UUID()
        preparation?.cancel()
        preparation = nil
        isPreparing = false
    }

    private func load(_ composition: SculptureComposition) {
        guard case .tiles(let map) = composition.models[composition.rootID] else {
            error = "This composition needs a tile map at its root. Import a sculpture into a new map instead."
            return
        }
        title = composition.title
        rootID = composition.rootID
        models = composition.models
        models.removeValue(forKey: rootID)
        width = map.width
        height = map.height
        layers = map.layers
        tileWidth = map.tileSize.width
        tileHeight = map.tileSize.height
        tileDepth = map.tileSize.depth
        bindings = map.bindings
        selectedGlyph = bindings.first?.glyph ?? 65
        selectedCell = SculptureCell(x: 0, y: 0, z: 0)
    }

    private func addModel(_ model: SculptureCompositionModel, id: String) throws {
        let glyph = try nextLetter()
        let binding = try SculptureModelBinding(glyph: glyph, modelID: id)
        var graph = models
        graph[id] = model
        var addedBindings = bindings
        addedBindings.append(binding)
        let map = try SculptureTileMap(
            width: width,
            height: height,
            layers: layers,
            tileSize: SculptureTileSize(width: tileWidth, height: tileHeight, depth: tileDepth),
            bindings: addedBindings
        )
        graph[rootID] = .tiles(map)
        _ = try validateGraph(graph)
        graph.removeValue(forKey: rootID)
        models = graph
        bindings = addedBindings
        selectedGlyph = glyph
    }

    private func nextLetter() throws -> UInt8 {
        let preferred = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!$".utf8)
        guard let glyph = preferred.first(where: { candidate in !bindings.contains { $0.glyph == candidate } }) else {
            throw CompositionDraftError.noAvailableLetter
        }
        return glyph
    }

    private func validateGraph(_ graph: [String: SculptureCompositionModel]) throws -> SculptureComposition {
        do {
            return try SculptureComposition(title: title, rootID: rootID, models: graph)
        } catch SculptureCompositionError.childDoesNotFit(let id) {
            guard let model = graph[id] else { throw SculptureCompositionError.unknownModel(id) }
            let title: String
            var width: Int
            var height: Int
            let depth: Int
            switch model {
            case .sculpture(let sculpture):
                title = sculpture.title
                width = sculpture.width; height = sculpture.height; depth = sculpture.depth
            case .tiles(let map):
                title = "The nested map"
                width = map.width * map.tileSize.width
                height = map.height * map.tileSize.height
                depth = map.depth * map.tileSize.depth
            }
            if case .tiles(let map) = graph[rootID],
                let binding = map.bindings.first(where: { $0.modelID == id }),
                !binding.quarterTurns.isMultiple(of: 2)
            {
                swap(&width, &height)
            }
            throw CompositionDraftError.modelDoesNotFit(title, width, height, depth)
        }
    }

    private func changed() {
        let current = snapshot
        if let lastSnapshot, !current.hasSameDocument(as: lastSnapshot) {
            undoHistory.append(lastSnapshot)
            if undoHistory.count > 32 { undoHistory.removeFirst() }
            redoHistory.removeAll()
            historyVersion += 1
        }
        lastSnapshot = current
        cancelPreparation()
        revision = UUID()
        preview = nil
        error = nil
        insertionNotice = nil
    }

    private var snapshot: CompositionDraftSnapshot {
        CompositionDraftSnapshot(
            title: title,
            rootID: rootID,
            width: width,
            height: height,
            layers: layers,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            tileDepth: tileDepth,
            models: models,
            bindings: bindings,
            selectedGlyph: selectedGlyph,
            selectedCell: selectedCell,
            portableSnapshot: portableSnapshot,
            holdsPortableData: holdsPortableData
        )
    }

    private func restore(_ saved: CompositionDraftSnapshot) {
        cancelPreparation()
        title = saved.title
        rootID = saved.rootID
        width = saved.width
        height = saved.height
        layers = saved.layers
        tileWidth = saved.tileWidth
        tileHeight = saved.tileHeight
        tileDepth = saved.tileDepth
        models = saved.models
        bindings = saved.bindings
        selectedGlyph = saved.selectedGlyph
        selectedCell = saved.selectedCell
        portableSnapshot = saved.portableSnapshot
        holdsPortableData = saved.holdsPortableData
        editingNotice = nil
        insertionNotice = nil
        lastSnapshot = snapshot
        revision = UUID()
        preview = nil
        error = nil
    }

    nonisolated private static func newModelID() -> String { "model-" + UUID().uuidString.lowercased() }

}

@MainActor
internal struct SculptureCompositionEditor: View {
    let onOpen: @MainActor (SculptureComposition, Sculpture) -> Void
    let onSave: @MainActor (SculptureComposition) -> Void
    let onWorld: (@MainActor (SculptureWorldHandoff) -> Void)?
    let initiallyUnsaved: Bool
    let onDirtyChange: @MainActor (Bool) -> Void
    /// The linked session this view-only composition belongs to, which offers Reload Linked Files.
    let linked: SculptureLinkedSession?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SculptureCompositionDraft
    @State private var confirmingClose = false
    @State private var pendingExample: SculptureComposition?
    @State private var confirmingExample = false

    init(
        composition: SculptureComposition? = nil,
        draft: SculptureCompositionDraft? = nil,
        initiallyUnsaved: Bool = false,
        linked: SculptureLinkedSession? = nil,
        onDirtyChange: @escaping @MainActor (Bool) -> Void = { _ in },
        onOpen: @escaping @MainActor (SculptureComposition, Sculpture) -> Void,
        onSave: @escaping @MainActor (SculptureComposition) -> Void,
        onWorld: (@MainActor (SculptureWorldHandoff) -> Void)? = nil
    ) {
        _draft = State(initialValue: draft ?? SculptureCompositionDraft(composition: composition))
        self.onOpen = onOpen
        self.onSave = onSave
        self.onWorld = onWorld
        self.initiallyUnsaved = initiallyUnsaved
        self.linked = linked
        self.onDirtyChange = onDirtyChange
    }

    /// A linked composition is shown view-only. Its edit controls stay visible but unavailable.
    private var viewOnly: Bool { draft.isViewOnly }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    mapWorkspace.frame(maxWidth: .infinity)
                    library.frame(width: 250)
                }
                .padding(.bottom, 4)
            }
            .disabled(draft.isBusy)
            Divider()
            footer
        }
        .padding(24)
        .frame(minWidth: 840, idealWidth: 940, minHeight: 640, idealHeight: 720)
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
        .tint(Brand.accent)
        // The File and Edit menus reach this sheet's importer and history. The editor window publishes the same
        // values, so the commands resolve whichever scope owns focus.
        .focusedSceneValue(\.sculptureInsertionActions, SculptureInsertionActions.actions(for: draft))
        .focusedSceneValue(\.sculptureSheetHistory, SculptureHistoryActions.actions(for: draft))
        .onAppear {
            if initiallyUnsaved { draft.markUnsaved() }
            onDirtyChange(draft.hasChanges)
        }
        .onChange(of: draft.hasChanges) { _, value in onDirtyChange(value) }
        .onDisappear { onDirtyChange(false) }
        .insertionImporter(
            request: draft.insertionRequest,
            current: { draft.insertionRequest },
            canPresent: { draft.canInsert },
            finish: { draft.finishInsertionRequest() },
            importFiles: { draft.importModels(from: $0) },
            importFolder: { draft.importFolder(from: $0) },
            report: { draft.report($0) }
        )
        .onChange(of: draft.insertionNotice) { _, notice in
            if let notice { AccessibilityNotification.Announcement(notice).post() }
        }
        .confirmationDialog("Discard this composition draft?", isPresented: $confirmingClose) {
            Button("Discard draft", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Save composition preserves the map and all of its model references.")
        }
        .confirmationDialog("Replace this composition draft?", isPresented: $confirmingExample) {
            Button("Replace draft", role: .destructive) {
                if let pendingExample { draft.replace(with: pendingExample) }
                pendingExample = nil
            }
            Button("Keep editing", role: .cancel) { pendingExample = nil }
        } message: {
            Text("The nested courtyard replaces the map and its model library. Save your draft first to keep it.")
        }
        .interactiveDismissDisabled(draft.hasChanges || draft.isBusy)
        .onDisappear { draft.cancelPreparation() }
        .sheet(item: Binding(get: { draft.sharedEdit }, set: { if $0 == nil { draft.cancelSharedEdit() } })) {
            session in
            SculptureSharedModelEditor(
                session: session,
                cancel: { draft.cancelSharedEdit() },
                apply: { await draft.applySharedEdit() }
            )
        }
        .sheet(item: Binding(get: { draft.pendingInsertion }, set: { if $0 == nil { draft.cancelPendingInsertion() } }))
        {
            pending in
            SculptureCompositionInsertionSheet(
                pending: pending,
                confirm: { draft.confirmInsertion(id: pending.id) },
                cancel: { draft.cancelPendingInsertion() }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let linked {
                Text("Linked composition").font(.system(size: 26, weight: .semibold))
                Text("\(linked.rootPath) in \(linked.folder.name). Each character places the model read from its file.")
                    .font(.callout).foregroundStyle(Brand.secondary)
                    .accessibilityIdentifier("composition.linked.source")
                if let notice = draft.viewOnlyNotice {
                    Label(notice, systemImage: "lock")
                        .font(.callout).foregroundStyle(Brand.ink)
                        .accessibilityIdentifier("composition.linked.notice")
                }
            } else {
                Text("Build with models").font(.system(size: 26, weight: .semibold))
                Text("Each letter places an entire model. Select a tile for insertion; Place and Erase change the map.")
                    .font(.callout).foregroundStyle(Brand.secondary)
            }
            HStack {
                TextField("Composition name", text: Binding(get: { draft.title }, set: { draft.setTitle($0) }))
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    .disabled(viewOnly)
                    .accessibilityIdentifier("composition.title")
                Spacer()
                Button("Nested courtyard") {
                    do {
                        let composition = try SculptureCompositionExamples.courtyard()
                        if draft.hasChanges {
                            pendingExample = composition
                            confirmingExample = true
                        } else {
                            draft.replace(with: composition)
                        }
                    } catch { draft.report(error) }
                }
                .disabled(viewOnly)
                .accessibilityIdentifier("composition.example.courtyard")
            }
        }
        .disabled(draft.isBusy)
    }

    private var mapWorkspace: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Tool", selection: $draft.brush) {
                    ForEach(SculptureCompositionBrush.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 300)
                .disabled(viewOnly)
                .accessibilityIdentifier("composition.tool")
                Spacer(minLength: 8)
                Picker("Map layer", selection: Binding(get: { draft.selectedCell.z }, set: { draft.selectLayer($0) })) {
                    ForEach(0..<draft.depth, id: \.self) { Text("Layer \($0 + 1)").tag($0) }
                }
                .frame(width: 185).accessibilityIdentifier("composition.layer")
            }
            GeometryReader { geometry in
                let horizontal = (geometry.size.width - 16 - Double(draft.width - 1) * 8) / Double(draft.width)
                let vertical = (geometry.size.height - 16 - Double(draft.height - 1) * 8) / Double(draft.height)
                let side = max(36, min(110, min(horizontal, vertical)))
                ScrollView([.horizontal, .vertical]) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(side), spacing: 8), count: draft.width),
                        spacing: 8
                    ) {
                        ForEach(0..<draft.width * draft.height, id: \.self) { index in
                            tileButton(
                                SculptureCell(x: index % draft.width, y: index / draft.width, z: draft.selectedCell.z)
                            )
                            .frame(width: side, height: side)
                        }
                    }
                    .padding(8)
                }
            }
            .frame(height: 270)
            .background(Brand.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(draft.placementCount) model tiles").font(.callout.weight(.medium))
                    Text("Expanded bounds: \(draft.expandedDimensions) cells")
                        .font(.caption).foregroundStyle(Brand.secondary)
                    Text(draft.insertionStartDescription)
                        .font(.caption).foregroundStyle(Brand.secondary)
                        .accessibilityIdentifier("composition.insertion.start")
                }
                Spacer()
                Text(draft.rawRows.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(8)
                    .foregroundStyle(Brand.secondary)
                    .accessibilityLabel("Map characters: " + draft.rawRows.joined(separator: ", "))
                    .accessibilityIdentifier("composition.map.characters")
            }
            dimensions
        }
    }

    private func tileButton(_ cell: SculptureCell) -> some View {
        let glyph = draft.glyph(at: cell) ?? Sculpture.empty
        let item = draft.library.first { $0.id == glyph }
        let selected = draft.selectedCell == cell
        return Button {
            draft.paint(cell)
        } label: {
            VStack(spacing: 6) {
                Text(glyph == Sculpture.empty ? "+" : String(UnicodeScalar(glyph)))
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
                    .foregroundStyle(glyph == Sculpture.empty ? Brand.secondary.opacity(0.55) : Brand.accent)
                if let item { Text(item.title).font(.caption).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(glyph == Sculpture.empty ? Brand.paper : Brand.accent.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    selected ? Brand.accent : Brand.ink.opacity(0.1),
                    lineWidth: selected ? 2 : 1
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Tile column \(cell.x + 1), row \(cell.y + 1), layer \(cell.z + 1): \(item.map { $0.character + " " + $0.title } ?? "empty")"
        )
        .accessibilityHint(tileHint)
        .accessibilityIdentifier("composition.cell.\(cell.z).\(cell.y).\(cell.x)")
    }

    private var tileHint: String {
        if viewOnly { return "Select this tile. Linked compositions are view only" }
        switch draft.brush {
        case .select: return "Choose where insertion starts without changing the map"
        case .erase: return "Erase this tile"
        case .place: return "Place the selected model"
        }
    }

    private var dimensions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Stepper(
                    "Columns \(draft.width)",
                    value: Binding(
                        get: { draft.width },
                        set: { draft.resize(width: $0, height: draft.height, depth: draft.depth) }
                    ),
                    in: 1...max(8, draft.width)
                )
                .accessibilityIdentifier("composition.map.width")
                Stepper(
                    "Rows \(draft.height)",
                    value: Binding(
                        get: { draft.height },
                        set: { draft.resize(width: draft.width, height: $0, depth: draft.depth) }
                    ),
                    in: 1...max(8, draft.height)
                )
                .accessibilityIdentifier("composition.map.height")
                Stepper(
                    "Layers \(draft.depth)",
                    value: Binding(
                        get: { draft.depth },
                        set: { draft.resize(width: draft.width, height: draft.height, depth: $0) }
                    ),
                    in: 1...max(8, draft.depth)
                )
                .accessibilityIdentifier("composition.map.depth")
            }
            Text("Voxel size of each tile").font(.caption.weight(.medium)).foregroundStyle(Brand.secondary)
            HStack(spacing: 16) {
                Stepper(
                    "Width \(draft.tileWidth)",
                    value: Binding(
                        get: { draft.tileWidth },
                        set: { draft.setTileSize(width: $0, height: draft.tileHeight, depth: draft.tileDepth) }
                    ),
                    in: 1...256
                )
                .accessibilityIdentifier("composition.tile.width")
                Stepper(
                    "Height \(draft.tileHeight)",
                    value: Binding(
                        get: { draft.tileHeight },
                        set: { draft.setTileSize(width: draft.tileWidth, height: $0, depth: draft.tileDepth) }
                    ),
                    in: 1...256
                )
                .accessibilityIdentifier("composition.tile.height")
                Stepper(
                    "Depth \(draft.tileDepth)",
                    value: Binding(
                        get: { draft.tileDepth },
                        set: { draft.setTileSize(width: draft.tileWidth, height: draft.tileHeight, depth: $0) }
                    ),
                    in: 1...256
                )
                .accessibilityIdentifier("composition.tile.depth")
            }
        }
        .font(.callout)
        .disabled(viewOnly)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Models").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(draft.library) { item in
                        Button {
                            draft.select(item.id)
                        } label: {
                            HStack(spacing: 12) {
                                Text(item.character).font(.system(size: 24, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Brand.accent).frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.callout.weight(.medium)).lineLimit(2)
                                    Text(item.dimensions + " cells").font(.caption).foregroundStyle(Brand.secondary)
                                    if let path = item.path {
                                        Text(path).font(.caption.monospaced()).foregroundStyle(Brand.secondary)
                                            .lineLimit(2).truncationMode(.middle)
                                            .accessibilityIdentifier("composition.model.path.\(item.id)")
                                    }
                                }
                                Spacer(minLength: 0)
                                if item.id == draft.selectedGlyph { Image(systemName: "checkmark").font(.caption) }
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                item.id == draft.selectedGlyph ? Brand.accent.opacity(0.1) : .clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Select \(item.character), \(item.title)" + (item.path.map { ", from \($0)" } ?? "")
                        )
                        .accessibilityIdentifier("composition.model.\(item.id)")
                    }
                }
            }
            .frame(minHeight: 130, maxHeight: 200)
            HStack {
                Menu("Add example") {
                    ForEach(SculptureExamples.compositionStarters) { example in
                        Button(example.title) { draft.addExample(example) }
                    }
                }
                .accessibilityIdentifier("composition.models.examples")
                Button("Insert 3md…") { draft.requestInsertion(.files) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .accessibilityIdentifier("composition.models.insert")
            }
            .disabled(viewOnly)
            Button("Insert model folder…") { draft.requestInsertion(.folder) }
                .disabled(viewOnly)
                .accessibilityIdentifier("composition.models.folder")
            Text(
                "Inserts at the selected start, filling consecutive tiles row by row. Replacing occupied tiles requires confirmation."
            )
            .font(.caption).foregroundStyle(Brand.secondary)
            Menu("Edit shared model…") {
                ForEach(draft.editableModels) { model in
                    Button(model.label) { draft.beginSharedEdit(modelID: model.id) }
                        .accessibilityLabel(model.accessibilityLabel)
                        .accessibilityIdentifier("composition.model.edit.\(model.id)")
                }
            }
            .disabled(draft.editableModels.isEmpty || viewOnly).accessibilityIdentifier("composition.model.edit")
            Text("Edit voxel models here to update every reference, including nested maps.")
                .font(.caption).foregroundStyle(Brand.secondary)
            if let binding = draft.selectedBinding {
                Picker(
                    "Rotation for \(String(UnicodeScalar(binding.glyph)))",
                    selection: Binding(
                        get: { draft.selectedBinding?.quarterTurns ?? 0 },
                        set: { draft.rotateSelected($0) }
                    )
                ) {
                    ForEach(0..<4, id: \.self) { Text("\($0 * 90)°").tag($0) }
                }
                .disabled(viewOnly)
                .accessibilityIdentifier("composition.model.rotation")
                Text("Rotates every \(String(UnicodeScalar(binding.glyph))) tile clockwise in its XY plane.")
                    .font(.caption).foregroundStyle(Brand.secondary)
            }
            if let preview = draft.preview {
                CompositionPreview(sculpture: preview, revision: draft.revision)
                    .frame(height: 150)
                Text("\(preview.occupiedCount) occupied voxels").font(.caption).foregroundStyle(Brand.secondary)
            } else {
                Text("Preview assembles the map without changing its references.")
                    .font(.caption).foregroundStyle(Brand.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if draft.isPreparing {
                ProgressView("Preparing composition…").controlSize(.small)
            } else if let error = draft.error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .accessibilityIdentifier("composition.error")
            }
            if let notice = draft.insertionNotice {
                Text(notice).font(.callout.weight(.medium)).foregroundStyle(Brand.ink)
                    .accessibilityLabel(notice)
                    .accessibilityIdentifier("composition.insertion.notice")
            }
            if let notice = draft.editingNotice {
                Text(notice).font(.caption).foregroundStyle(Brand.secondary)
            }
            if let linked {
                SculptureLinkedStatus(session: linked)
            } else {
                Text(
                    "Save composition keeps the model references. Open editable voxels makes a separate copy for painting."
                )
                .font(.callout).foregroundStyle(Brand.secondary)
            }
            HStack {
                Button("Undo") { draft.undo() }.disabled(!draft.canUndo || draft.isBusy || viewOnly)
                    .keyboardShortcut("z").accessibilityIdentifier("composition.undo")
                Button("Redo") { draft.redo() }.disabled(!draft.canRedo || draft.isBusy || viewOnly)
                    .keyboardShortcut("z", modifiers: [.command, .shift]).accessibilityIdentifier("composition.redo")
            }
            HStack {
                Button(
                    draft.isPreparing
                        ? "Cancel preparation" : draft.pendingInsertion != nil ? "Cancel insertion" : "Close"
                ) {
                    if draft.isPreparing {
                        draft.cancelPreparation()
                    } else if draft.pendingInsertion != nil {
                        draft.cancelPendingInsertion()
                    } else if draft.hasChanges {
                        confirmingClose = true
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction).accessibilityIdentifier("composition.close")
                Spacer()
                if let linked {
                    Button(linked.isResolving ? "Reloading…" : "Reload linked files") { linked.reload() }
                        .disabled(!linked.canReload)
                        .help("Read the linked files again from \(linked.folder.name).")
                        .accessibilityIdentifier("composition.linked.reload")
                }
                Button("Preview") { draft.prepare() }
                    .disabled(draft.isBusy).accessibilityIdentifier("composition.preview")
                Button("Save composition…") {
                    guard !viewOnly else { return }
                    do { onSave(try draft.composition()) } catch { draft.report(error) }
                }
                .disabled(draft.isBusy || viewOnly)
                .help(draft.viewOnlyNotice ?? "")
                .accessibilityIdentifier("composition.save")
                Button("Open editable voxels") { draft.prepare(open: onOpen) }
                    .buttonStyle(.borderedProminent).disabled(draft.isBusy || viewOnly)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(draft.viewOnlyNotice ?? "")
                    .accessibilityIdentifier("composition.open")
                if let onWorld {
                    Button("Use in a world") {
                        guard draft.canUseInWorld else { return }
                        draft.prepareWorldHandoff(then: onWorld)
                    }
                    .disabled(!draft.canUseInWorld)
                    .help(draft.viewOnlyNotice ?? "")
                    .accessibilityIdentifier("composition.open-world")
                }
            }
        }
    }
}

private struct SculptureCompositionInsertionSheet: View {
    let pending: SculptureCompositionInsertionConfirmation
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(pending.question).font(.title2.weight(.semibold))
            Text(pending.targetSummary).font(.callout)
                .accessibilityIdentifier("composition.insertion.targets")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(pending.targets) { target in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.location.capitalized).font(.caption).foregroundStyle(.secondary)
                            Text(target.incomingTitle).font(.body.weight(.medium))
                            if target.currentGlyph != Sculpture.empty {
                                Text(
                                    "Replaces \(String(UnicodeScalar(target.currentGlyph))) \(target.currentTitle ?? "model")"
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Empty tile").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(
                            "composition.insertion.target.\(target.cell.z).\(target.cell.y).\(target.cell.x)"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            Text("You can undo this insertion as one change.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("composition.insertion.cancel")
                Spacer()
                Button("Replace tiles and insert", role: .destructive, action: confirm)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("composition.insertion.confirm")
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 280)
    }
}

private struct CompositionPreviewImage: @unchecked Sendable {
    let image: CGImage?
}

private struct CompositionPreview: View {
    let sculpture: Sculpture
    let revision: UUID
    @State private var image: CGImage?
    @State private var finished = false

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else if finished {
                Text("Open editable voxels to view this detailed model.")
                    .font(.caption).foregroundStyle(.white.opacity(0.8)).padding()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.065, green: 0.085, blue: 0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Assembled composition preview")
        .task(id: revision) {
            finished = false
            image = nil
            let sculpture = sculpture
            let worker = Task.detached(priority: .utility) {
                CompositionPreviewImage(
                    image: SculptureImageRenderer.image(
                        sculpture: sculpture,
                        camera: SculptureCamera(yaw: -0.6, pitch: 0.7, zoom: 1),
                        style: .cubes,
                        width: 420,
                        height: 300
                    )
                )
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            image = result.image
            finished = true
        }
    }
}
