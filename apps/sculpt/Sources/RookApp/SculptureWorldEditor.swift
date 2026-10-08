import Foundation
import Observation
import RookRendering
import RookSculpture
import SwiftUI
import UniformTypeIdentifiers

internal struct SculptureWorldModelChoice: Identifiable {
    let id: String
    let title: String
    /// Voxel dimensions such as "4 × 4 × 4". Labels show the title and these, never the generated model ID.
    var dimensions: String?
    /// Set only when another model has the same title and size: where this one is placed or bound.
    var qualifier: String?

    /// A menu label that tells same-titled models apart by size, and by place when size is not enough.
    var label: String {
        let base = dimensions.map { "\(title) (\($0) cells)" } ?? title
        return qualifier.map { "\(base), \($0)" } ?? base
    }

    var accessibilityLabel: String {
        let base = dimensions.map { "\(title), \($0) cells" } ?? title
        return qualifier.map { "\(base), \($0)" } ?? base
    }

    /// Adds `qualifier` to every choice whose title and dimensions another choice shares, and to no other.
    static func disambiguating(_ choices: [Self], qualifier: (Self) -> String) -> [Self] {
        var counts: [String: Int] = [:]
        for choice in choices { counts[choice.title + "\u{0}" + (choice.dimensions ?? ""), default: 0] += 1 }
        return choices.map { choice in
            guard counts[choice.title + "\u{0}" + (choice.dimensions ?? "")] ?? 0 > 1 else { return choice }
            var qualified = choice
            qualified.qualifier = qualifier(choice)
            return qualified
        }
    }
}

private struct WorldDraftSnapshot: Equatable {
    let title: String
    let library: SculptureComposition
    let instances: [SculptureWorldInstance]
    let selection: String?
    let portableSnapshot: SculptureThreeMDSnapshot?
    let holdsPortableData: Bool
}

private enum WorldDraftError: LocalizedError {
    case coordinates
    case overflow
    case noSelection
    var errorDescription: String? {
        switch self {
        case .coordinates: "Use whole-number coordinates within the Int64 range."
        case .overflow: "That move would exceed the Int64 coordinate range. Choose a smaller coordinate."
        case .noSelection: "Select a placed model first."
        }
    }
}

/// Sparse placements are document state. Focus, camera and rendering distance are session state.
@MainActor
@Observable
internal final class SculptureWorldDraft {
    private(set) var title: String
    private(set) var library: SculptureComposition
    private(set) var instances: [SculptureWorldInstance]
    private(set) var selectedInstanceID: String?
    private(set) var selectedModelID: String
    private(set) var quarterTurns = 0
    private(set) var focus = SculptureWorldPoint(x: 0, y: 0, z: 0)
    var focusX = "0"
    var focusY = "0"
    var focusZ = "0"
    private(set) var renderDistance = 256
    private(set) var detailDistance = 128
    private(set) var page = 0
    private(set) var sceneRevision = UUID()
    private(set) var portableSnapshot: SculptureThreeMDSnapshot?
    /// Whether the person has portable ThreeMD data to preserve: the draft was opened or handed off with a
    /// snapshot, exported one, or inserted an input that carried one. A snapshot minted by a shared edit is not
    /// data the person has, so it never forces a later insertion down the portable path. Undo and Redo restore it.
    private(set) var holdsPortableData: Bool
    private(set) var editingNotice: String?
    private(set) var documentRevision = UUID()
    private(set) var sharedEdit: SculptureSharedModelSession?
    private(set) var isMakingUnique = false
    private(set) var error: String?
    private(set) var isOpeningModel = false
    private(set) var camera = SculptureCamera(yaw: -0.6, pitch: 0.45, zoom: 1)
    private(set) var navigationMode = SculptureWorldNavigationMode.orbit
    private(set) var explorer = SculptureWorldExplorer(anchor: .init(x: 0, y: 0, z: 0))
    private(set) var overviewNotice: String?
    /// The importer the sheet should present, set by its buttons, the File menu and the command palette.
    private(set) var insertionRequest: SculptureInsertionKind?
    @ObservationIgnored private var baseline: WorldDraftSnapshot
    @ObservationIgnored private var undoHistory: [WorldDraftSnapshot] = []
    @ObservationIgnored private var redoHistory: [WorldDraftSnapshot] = []
    @ObservationIgnored private var modelPreparation: Task<Void, Never>?
    @ObservationIgnored private var preparationID = UUID()
    /// Shared model geometry a gallery opening prepared away from the main actor, for the scene revision it matched.
    @ObservationIgnored private var handedOverScene: (revision: UUID, scene: SculptureWorldScene)?
    /// Observed counter so menus and views that read `canUndo` or `canRedo` refresh when a history stack changes.
    private var historyVersion = 0
    private var initiallyUnsaved = false

    init(
        world: SculptureWorld? = nil,
        portableSnapshot: SculptureThreeMDSnapshot? = nil,
        notice: String? = nil
    ) {
        self.portableSnapshot = portableSnapshot
        holdsPortableData = portableSnapshot != nil
        editingNotice = notice
        let initial = world ?? Self.starterWorld()
        title = initial.title
        library = initial.library
        instances = initial.instances
        selectedInstanceID = initial.instances.first?.id
        selectedModelID = initial.instances.first?.modelID ?? initial.library.rootID
        quarterTurns = initial.instances.first?.quarterTurns ?? 0
        baseline = WorldDraftSnapshot(
            title: initial.title,
            library: initial.library,
            instances: initial.instances,
            selection: initial.instances.first?.id,
            portableSnapshot: portableSnapshot,
            holdsPortableData: portableSnapshot != nil
        )
        if let origin = initial.instances.first?.origin { setFocus(origin) }
    }

    /// An empty sparse world, so a command that starts by inserting files never places among starter models.
    static func insertionCanvas() -> SculptureWorldDraft {
        guard
            let tileSize = try? SculptureTileSize(width: 1, height: 1, depth: 1),
            let map = try? SculptureTileMap(
                width: 1,
                height: 1,
                layers: [[Sculpture.empty]],
                tileSize: tileSize,
                bindings: []
            ),
            let library = try? SculptureComposition(
                title: "Inserted models",
                rootID: "root",
                models: ["root": .tiles(map)]
            ),
            let world = try? SculptureWorld(title: "Inserted world", library: library, instances: [])
        else { return SculptureWorldDraft() }
        return SculptureWorldDraft(world: world)
    }

    var hasChanges: Bool {
        initiallyUnsaved || title != baseline.title || library != baseline.library || instances != baseline.instances
    }
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
    /// Insertion needs a settled parent: no preparation, unique-copy work or shared edit in progress.
    var canInsert: Bool { !isOpeningModel && !isMakingUnique && sharedEdit == nil }
    var selectedInstance: SculptureWorldInstance? { instances.first { $0.id == selectedInstanceID } }
    var selectedModelIsVoxel: Bool {
        if case .sculpture = library.models[selectedModelID] { true } else { false }
    }
    /// Voxel models that can be edited in place. Models that share a title and size are told apart by where the
    /// first placement sits, or "unplaced", so the menu never makes one look like another.
    var editableModels: [SculptureWorldModelChoice] {
        let voxels = modelChoices.filter { if case .sculpture = library.models[$0.id] { true } else { false } }
        return SculptureWorldModelChoice.disambiguating(voxels) { choice in
            guard let placement = instances.first(where: { $0.modelID == choice.id }) else { return "unplaced" }
            return "at \(placement.origin.x), \(placement.origin.y), \(placement.origin.z)"
        }
    }
    var pageCount: Int { max(1, (instances.count + 99) / 100) }
    var pageInstances: [SculptureWorldInstance] {
        let start = min(page * 100, instances.count)
        return Array(instances[start..<min(start + 100, instances.count)])
    }
    var modelChoices: [SculptureWorldModelChoice] {
        library.models.keys.sorted().map { id in
            let title: String
            let dimensions: String?
            switch library.models[id] {
            case .sculpture(let sculpture):
                title = sculpture.title
                dimensions = "\(sculpture.width) × \(sculpture.height) × \(sculpture.depth)"
            case .tiles(let map):
                title =
                    id == library.rootID
                    ? library.title
                    : portableSnapshot.flatMap {
                        SculptureThreeMDCodec.modelTitle(for: id, in: $0)
                    } ?? "Nested map"
                dimensions =
                    "\(map.width * map.tileSize.width) × \(map.height * map.tileSize.height) × \(map.depth * map.tileSize.depth)"
            case nil:
                title = id
                dimensions = nil
            }
            return SculptureWorldModelChoice(id: id, title: title, dimensions: dimensions)
        }
    }

    /// The title of a placed model, falling back to its ID only when the library no longer holds it.
    func modelTitle(for modelID: String) -> String {
        modelChoices.first { $0.id == modelID }?.title ?? modelID
    }

    /// The title and dimensions of a placed model for spoken labels. The generated ID is never spoken.
    func modelAccessibilityLabel(for modelID: String) -> String {
        modelChoices.first { $0.id == modelID }?.accessibilityLabel ?? modelID
    }

    func world() throws -> SculptureWorld { try SculptureWorld(title: title, library: library, instances: instances) }
    /// A portable export or save gives the person portable data, so later insertions preserve its identities.
    func retainPortableSnapshot(_ captured: SculptureThreeMDSnapshot) {
        guard case .world(let scene) = captured.scene, (try? world()) == scene else { return }
        portableSnapshot = captured
        holdsPortableData = true
    }

    func markUnsaved() { initiallyUnsaved = true }

    /// The handed-over scene while the draft still shows exactly the world it was prepared for.
    var preparedScene: SculptureWorldScene? {
        handedOverScene?.revision == sceneRevision ? handedOverScene?.scene : nil
    }

    /// Keeps geometry prepared for this exact world, so the editor shows it without preparing it again.
    /// - Parameter scene: Geometry prepared from the world this draft was created with.
    /// - Returns: False, keeping nothing, when the scene describes a different world.
    @discardableResult
    func adoptPreparedScene(_ scene: SculptureWorldScene) -> Bool {
        guard let current = try? world(), scene.world == current else { return false }
        handedOverScene = (sceneRevision, scene)
        return true
    }

    /// Drops handed-over geometry once the editor has prepared a newer scene.
    func releasePreparedScene() { handedOverScene = nil }

    func markSaved(_ saved: SculptureWorld) {
        baseline = WorldDraftSnapshot(
            title: saved.title,
            library: saved.library,
            instances: saved.instances,
            selection: selectedInstanceID,
            portableSnapshot: portableSnapshot,
            holdsPortableData: holdsPortableData
        )
        initiallyUnsaved = false
    }

    /// Rendering stays available while the title is being edited; file publication still validates the real title.
    func renderInput() -> (String, SculptureComposition, [SculptureWorldInstance]) {
        let valid = !title.isEmpty && title.utf8.count <= 80 && title.utf8.allSatisfy { (32...126).contains($0) }
        return (valid ? title : "World draft", library, instances)
    }

    func setTitle(_ value: String) {
        guard value != title else { return }
        recordUndo()
        title = value
        documentRevision = UUID()
        error = nil
    }

    func selectModel(_ id: String) {
        guard library.models[id] != nil else { return }
        selectedModelID = id
        selectedInstanceID = nil
        quarterTurns = 0
    }

    func selectInstance(_ id: String) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        selectedInstanceID = id
        selectedModelID = instances[index].modelID
        quarterTurns = instances[index].quarterTurns
        page = index / 100
    }

    /// Commits typed coordinates. An unchanged focus keeps the Explore eye exactly where it is.
    @discardableResult
    func applyFocus() -> Bool {
        guard let x = Int64(focusX.trimmingCharacters(in: .whitespaces)),
            let y = Int64(focusY.trimmingCharacters(in: .whitespaces)),
            let z = Int64(focusZ.trimmingCharacters(in: .whitespaces))
        else {
            error = WorldDraftError.coordinates.localizedDescription
            return false
        }
        move(toFocus: SculptureWorldPoint(x: x, y: y, z: z))
        error = nil
        return true
    }

    func moveFocus(axis: Int, delta: Int64) {
        guard applyFocus() else { return }
        let source: Int64
        switch axis {
        case 0: source = focus.x
        case 1: source = focus.y
        case 2: source = focus.z
        default: return
        }
        let (result, overflow) = source.addingReportingOverflow(delta)
        guard !overflow else {
            error = WorldDraftError.overflow.localizedDescription
            return
        }
        setFocus(
            SculptureWorldPoint(
                x: axis == 0 ? result : focus.x,
                y: axis == 1 ? result : focus.y,
                z: axis == 2 ? result : focus.z
            )
        )
        error = nil
    }

    func jumpToSelected() {
        guard let selectedInstance else { error = WorldDraftError.noSelection.localizedDescription; return }
        // Jumping always rebuilds the explorer at the instance, even when the focus already matches.
        setFocus(selectedInstance.origin)
        error = nil
    }

    // MARK: - Insertion

    /// Asks the sheet to present its importer. Ignored while a preparation, shared edit or unique copy is pending.
    func requestInsertion(_ kind: SculptureInsertionKind) {
        guard canInsert, insertionRequest == nil else { return }
        insertionRequest = kind
    }

    func finishInsertionRequest() { insertionRequest = nil }

    func importModels(from urls: [URL]) {
        prepareInsertion { plan in try SculptureInsertionFiles.read(urls, plan: plan) }
    }

    func importFolder(from url: URL) {
        prepareInsertion { plan in try SculptureInsertionFiles.readFolder(url, plan: plan) }
    }

    func insert(_ inputs: [SculptureInsertionInput]) throws {
        guard applyFocus() else { throw WorldDraftError.coordinates }
        let result = try SculptureSceneInsertion.intoWorld(
            world(),
            preserving: insertionSnapshot,
            inputs: inputs,
            at: focus
        )
        applyInsertion(result)
    }

    private func applyInsertion(_ result: SculptureInsertionResult) {
        guard case .world(let candidate) = result.scene else { return }
        publish(candidate)
        // The core returns a snapshot only when the parent or an input carried portable data.
        portableSnapshot = result.snapshot
        holdsPortableData = result.snapshot != nil
        if result.usedNativeFallback {
            editingNotice =
                "Inserted with native Sculpt values because this scene exceeds portable ThreeMD capacity."
        }
        if let last = candidate.instances.last {
            selectedInstanceID = last.id
            selectedModelID = last.modelID
            quarterTurns = last.quarterTurns
            page = max(0, pageCount - 1)
        }
    }

    private func prepareInsertion(
        _ read: @escaping @Sendable (SculptureInsertionPlan) throws -> [SculptureInsertionInput]
    ) {
        cancelModelPreparation()
        guard applyFocus() else { return }
        do {
            let parent = try world()
            let preserving = insertionSnapshot
            let origin = focus
            let capturedRevision = documentRevision
            let plan = SculptureInsertionPlan(world: parent)
            let identifier = UUID()
            preparationID = identifier
            isOpeningModel = true
            error = nil
            modelPreparation = Task { [weak self] in
                let worker = Task.detached(priority: .userInitiated) {
                    try SculptureSceneInsertion.intoWorld(
                        parent,
                        preserving: preserving,
                        inputs: read(plan),
                        at: origin
                    )
                }
                do {
                    let result = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    guard !Task.isCancelled, let self, self.preparationID == identifier else { return }
                    guard self.documentRevision == capturedRevision, self.insertionSnapshot == preserving,
                        (try? self.world()) == parent, self.focus == origin,
                        self.focusX == String(origin.x), self.focusY == String(origin.y),
                        self.focusZ == String(origin.z)
                    else {
                        self.cancelModelPreparation()
                        self.report(SculptureInsertionFiles.Failure.parentChanged)
                        return
                    }
                    self.isOpeningModel = false
                    self.modelPreparation = nil
                    self.applyInsertion(result)
                    self.resumeNavigationFocus()
                } catch {
                    guard !Task.isCancelled, let self, self.preparationID == identifier else { return }
                    self.isOpeningModel = false
                    self.modelPreparation = nil
                    self.report(error)
                    self.resumeNavigationFocus()
                }
            }
        } catch { report(error) }
    }

    func placeAtFocus() {
        guard applyFocus() else { return }
        do {
            let instance = try SculptureWorldInstance(
                id: "instance-" + UUID().uuidString.lowercased(),
                modelID: selectedModelID,
                origin: focus,
                quarterTurns: quarterTurns
            )
            var proposed = instances
            proposed.append(instance)
            try changeInstances(proposed, selection: instance.id)
        } catch { report(error) }
    }

    func moveSelectedToFocus() {
        guard let selectedInstance else { error = WorldDraftError.noSelection.localizedDescription; return }
        guard applyFocus() else { return }
        do {
            let replacement = try SculptureWorldInstance(
                id: selectedInstance.id,
                modelID: selectedInstance.modelID,
                origin: focus,
                quarterTurns: selectedInstance.quarterTurns
            )
            try changeInstances(instances.map { $0.id == replacement.id ? replacement : $0 }, selection: replacement.id)
        } catch { report(error) }
    }

    func rotate(_ turns: Int) {
        guard (0..<4).contains(turns) else { return }
        guard let selectedInstance else { quarterTurns = turns; return }
        do {
            let replacement = try SculptureWorldInstance(
                id: selectedInstance.id,
                modelID: selectedInstance.modelID,
                origin: selectedInstance.origin,
                quarterTurns: turns
            )
            try changeInstances(instances.map { $0.id == replacement.id ? replacement : $0 }, selection: replacement.id)
            quarterTurns = turns
        } catch { report(error) }
    }

    func deleteSelected() {
        guard let selectedInstanceID else { error = WorldDraftError.noSelection.localizedDescription; return }
        do { try changeInstances(instances.filter { $0.id != selectedInstanceID }, selection: nil) } catch {
            report(error)
        }
    }

    func undo() {
        guard let previous = undoHistory.popLast() else { return }
        redoHistory.append(snapshot)
        historyVersion += 1
        restore(previous)
    }

    func redo() {
        guard let next = redoHistory.popLast() else { return }
        undoHistory.append(snapshot)
        historyVersion += 1
        restore(next)
    }

    func setPage(_ value: Int) { page = max(0, min(pageCount - 1, value)) }

    func setRenderDistance(_ value: Int) {
        renderDistance = max(64, min(2048, value))
        detailDistance = min(detailDistance, renderDistance)
    }

    func setDetailDistance(_ value: Int) { detailDistance = max(16, min(renderDistance, value)) }
    func setCamera(_ value: SculptureCamera) { camera = value }
    func resetCamera() { camera = SculptureCamera(yaw: -0.6, pitch: 0.45, zoom: 1) }
    func report(_ error: any Error) { self.error = SculpturePortableDiagnostic.message(error) }

    func setNavigationMode(_ value: SculptureWorldNavigationMode) {
        guard value != navigationMode else { return }
        if value == .explore {
            do {
                let startingPose = try SculptureWorldExplorer(
                    anchor: focus,
                    offset: SIMD3(32, 20, 96),
                    yaw: 0,
                    pitch: -0.08
                )
                setExplorer(startingPose)
            } catch { report(error); return }
        }
        navigationMode = value
        error = nil
    }

    func setExplorer(_ value: SculptureWorldExplorer) {
        explorer = value
        guard value.anchor != focus else { return }
        // While an insertion prepares, walking never moves the target the result is checked against.
        // `resumeNavigationFocus` catches the focus up afterwards.
        guard !isOpeningModel else { return }
        focus = value.anchor
        focusX = String(focus.x)
        focusY = String(focus.y)
        focusZ = String(focus.z)
    }

    func stepExplore(forward: Double = 0, right: Double = 0, vertical: Double = 0) {
        guard navigationMode == .explore else { return }
        do {
            var moved = explorer
            try moved.move(forward: forward, right: right, vertical: vertical, speed: 48, duration: 0.2)
            setExplorer(moved)
            error = nil
        } catch { report(error) }
    }

    /// Frames validated placement bounds without expanding any shared model or losing large integer precision.
    @discardableResult
    func showOverview() -> Bool {
        guard let first = instances.first else { return false }
        var low = [first.origin.x, first.origin.y, first.origin.z]
        var high = low
        for instance in instances {
            let dimensions: [Int]
            switch library.models[instance.modelID] {
            case .sculpture(let model): dimensions = [model.width, model.height, model.depth]
            case .tiles(let map):
                dimensions = [
                    map.width * map.tileSize.width, map.height * map.tileSize.height, map.depth * map.tileSize.depth,
                ]
            case nil: continue
            }
            let rotated =
                instance.quarterTurns.isMultiple(of: 2)
                ? dimensions : [dimensions[1], dimensions[0], dimensions[2]]
            let origin = [instance.origin.x, instance.origin.y, instance.origin.z]
            for axis in 0..<3 {
                low[axis] = min(low[axis], origin[axis])
                high[axis] = max(high[axis], origin[axis] + Int64(rotated[axis] - 1))
            }
        }
        // This signed midpoint remains exact even for a span crossing Int64's complete range.
        let middle = zip(low, high).map { ($0 & $1) + (($0 ^ $1) >> 1) }
        var squaredRadius = 0.0
        for axis in 0..<3 {
            let delta = high[axis].subtractingReportingOverflow(middle[axis])
            guard !delta.overflow, delta.partialValue <= 2048 else {
                overviewNotice = "This world extends beyond the overview range. Use Visit or Jump to explore a region."
                navigationMode = .orbit
                return false
            }
            squaredRadius += pow(Double(delta.partialValue + 1), 2)
        }
        let radius = Int(ceil(sqrt(squaredRadius) / 64)) * 64
        guard radius <= 2048 else {
            overviewNotice = "This world extends beyond the overview range. Use Visit or Jump to explore a region."
            navigationMode = .orbit
            return false
        }
        setFocus(.init(x: middle[0], y: middle[1], z: middle[2]))
        setRenderDistance(max(64, radius))
        navigationMode = .orbit
        resetCamera()
        overviewNotice =
            "Whole world overview. Colored distant models use simplified detail; view capacity stays bounded."
        error = nil
        return true
    }

    func visitModel(_ modelID: String) {
        guard let instance = instances.first(where: { $0.modelID == modelID }) else { return }
        selectInstance(instance.id)
        setFocus(instance.origin)
        navigationMode = .orbit
        setRenderDistance(384)
        setDetailDistance(192)
        setNavigationMode(.explore)
        overviewNotice = nil
    }

    func beginSharedEdit(modelID: String) {
        guard sharedEdit == nil, !isMakingUnique else { return }
        do {
            _ = try world()
            guard case .sculpture(let sculpture) = library.models[modelID] else {
                throw SculptureModelEditingError.voxelModelRequired(modelID)
            }
            cancelModelPreparation()
            sharedEdit = SculptureSharedModelSession(
                modelID: modelID,
                source: sculpture,
                parentRevision: documentRevision
            )
            error = nil
        } catch { report(error) }
    }

    func cancelSharedEdit() { sharedEdit = nil }

    func applySharedEdit() async -> Bool {
        guard let session = sharedEdit, !session.isApplying, session.workspace.commitTitle() else { return false }
        session.isApplying = true
        defer { session.isApplying = false }
        do {
            let parent = try world()
            let replacement = session.workspace.sculpture
            let modelID = session.modelID
            let expected = session.source
            let preserving = portableSnapshot
            let worker = Task.detached(priority: .userInitiated) {
                try SculpturePortableModelEditing.replace(
                    scene: .world(parent),
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
            guard sharedEdit?.id == session.id, documentRevision == session.parentRevision,
                session.workspace.sculpture == replacement
            else {
                // The model changed while it was validated, so the validated result is stale. The session stays open.
                throw SculptureModelEditingError.expectedModelChanged(session.modelID)
            }
            guard case .world(let edited) = candidate.scene else { return false }
            publish(edited, portableSnapshot: candidate.snapshot)
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

    func makeSelectedUnique() async {
        guard let instance = selectedInstance, !isMakingUnique else { return }
        isMakingUnique = true
        defer { isMakingUnique = false }
        do {
            let parent = try world()
            let revision = documentRevision
            let newModelID = "model-" + UUID().uuidString.lowercased()
            let worker = Task.detached(priority: .userInitiated) {
                try SculptureModelEditing.makingUnique(in: parent, instanceID: instance.id, newModelID: newModelID)
            }
            let candidate = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            try Task.checkCancellation()
            guard documentRevision == revision else {
                throw SculptureModelEditingError.expectedModelChanged(instance.modelID)
            }
            publish(candidate)
        } catch is CancellationError {} catch { report(error) }
    }

    private func publish(_ candidate: SculptureWorld, portableSnapshot captured: SculptureThreeMDSnapshot? = nil) {
        guard candidate.title != title || candidate.library != library || candidate.instances != instances else {
            return
        }
        recordUndo()
        portableSnapshot = captured ?? portableSnapshot
        title = candidate.title
        library = candidate.library
        instances = candidate.instances
        if let selectedInstance { selectedModelID = selectedInstance.modelID }
        sceneRevision = UUID()
        documentRevision = UUID()
        error = nil
    }

    func openModel(_ opened: @escaping @MainActor (Sculpture) -> Void) {
        cancelModelPreparation()
        let library = library
        let modelID = selectedModelID
        let identifier = UUID()
        preparationID = identifier
        isOpeningModel = true
        error = nil
        modelPreparation = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { try library.expanded(modelID: modelID) }
            do {
                let sculpture = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self, self.preparationID == identifier else { return }
                self.isOpeningModel = false
                self.modelPreparation = nil
                self.resumeNavigationFocus()
                opened(sculpture)
            } catch {
                guard !Task.isCancelled, let self, self.preparationID == identifier else { return }
                self.isOpeningModel = false
                self.modelPreparation = nil
                self.report(error)
                self.resumeNavigationFocus()
            }
        }
    }

    func cancelModelPreparation() {
        preparationID = UUID()
        modelPreparation?.cancel()
        modelPreparation = nil
        isOpeningModel = false
        resumeNavigationFocus()
    }

    private var snapshot: WorldDraftSnapshot {
        WorldDraftSnapshot(
            title: title,
            library: library,
            instances: instances,
            selection: selectedInstanceID,
            portableSnapshot: portableSnapshot,
            holdsPortableData: holdsPortableData
        )
    }

    private func recordUndo() {
        undoHistory.append(snapshot)
        if undoHistory.count > 32 { undoHistory.removeFirst() }
        redoHistory.removeAll()
        historyVersion += 1
    }

    private func changeInstances(_ proposed: [SculptureWorldInstance], selection: String?) throws {
        guard proposed != instances else { return }
        let (renderTitle, _, _) = renderInput()
        _ = try SculptureWorld(title: renderTitle, library: library, instances: proposed)
        recordUndo()
        instances = proposed
        selectedInstanceID = selection
        if let selectedInstance {
            selectedModelID = selectedInstance.modelID
            quarterTurns = selectedInstance.quarterTurns
        }
        page = min(page, pageCount - 1)
        sceneRevision = UUID()
        documentRevision = UUID()
        error = nil
    }

    private func restore(_ saved: WorldDraftSnapshot) {
        let geometryChanged = instances != saved.instances || library != saved.library
        title = saved.title
        library = saved.library
        instances = saved.instances
        selectedInstanceID = saved.selection
        portableSnapshot = saved.portableSnapshot
        holdsPortableData = saved.holdsPortableData
        editingNotice = nil
        if let selectedInstance {
            selectedModelID = selectedInstance.modelID
            quarterTurns = selectedInstance.quarterTurns
        }
        page = min(page, pageCount - 1)
        if geometryChanged { sceneRevision = UUID() }
        documentRevision = UUID()
        error = nil
    }

    private func setFocus(_ point: SculptureWorldPoint) {
        focus = point
        focusX = String(point.x)
        focusY = String(point.y)
        focusZ = String(point.z)
        explorer = SculptureWorldExplorer(anchor: point, yaw: explorer.yaw, pitch: explorer.pitch)
    }

    /// Focuses on `point` only when it differs from the current focus. Rebuilding the explorer would snap the
    /// Explore eye to the anchor, so an unchanged focus just restores the canonical coordinate text.
    private func move(toFocus point: SculptureWorldPoint) {
        guard point != focus else {
            focusX = String(point.x)
            focusY = String(point.y)
            focusZ = String(point.z)
            return
        }
        setFocus(point)
    }

    /// Catches the focus up with the Explore anchor after navigation was paused for an insertion.
    private func resumeNavigationFocus() {
        guard navigationMode == .explore, explorer.anchor != focus else { return }
        focus = explorer.anchor
        focusX = String(focus.x)
        focusY = String(focus.y)
        focusZ = String(focus.z)
    }

    private static func starterWorld() -> SculptureWorld {
        let library = try! SculptureCompositionExamples.courtyard()
        // Fixed valid IDs and coordinates form a small sparse world; no space between these origins is allocated.
        let instances = [Int64(0), 96, 512, 1_000_000_000_000].enumerated().map { index, x in
            try! SculptureWorldInstance(
                id: "garden-\(index + 1)",
                modelID: "garden",
                origin: SculptureWorldPoint(x: x, y: 0, z: 0)
            )
        }
        return try! SculptureWorld(title: "Growing garden", library: library, instances: instances)
    }
}

@MainActor
internal struct SculptureWorldEditor: View {
    let initiallyUnsaved: Bool
    let onDirtyChange: @MainActor (Bool) -> Void
    let onSave: @MainActor (SculptureWorld) -> Void
    let onOpen: @MainActor (Sculpture) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SculptureWorldDraft
    @State private var controller = SculptureLiveWorldController()
    @State private var scene: SculptureWorldScene?
    @State private var preparedID: UUID?
    @State private var sceneError: String?
    @State private var isPreparingScene = true
    @State private var confirmingClose = false
    @State private var uniquePreparation: Task<Void, Never>?
    @State private var didFrameInitialWorld = false

    init(
        world: SculptureWorld? = nil,
        draft: SculptureWorldDraft? = nil,
        initiallyUnsaved: Bool = false,
        onDirtyChange: @escaping @MainActor (Bool) -> Void = { _ in },
        onSave: @escaping @MainActor (SculptureWorld) -> Void,
        onOpen: @escaping @MainActor (Sculpture) -> Void
    ) {
        let resolved = draft ?? SculptureWorldDraft(world: world)
        _draft = State(initialValue: resolved)
        if let prepared = resolved.preparedScene {
            // A gallery opening prepared this revision already; show it without a second preparation.
            _scene = State(initialValue: prepared)
            _preparedID = State(initialValue: resolved.sceneRevision)
            _isPreparingScene = State(initialValue: false)
        }
        self.initiallyUnsaved = initiallyUnsaved
        self.onDirtyChange = onDirtyChange
        self.onSave = onSave
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    canvas.frame(maxHeight: .infinity)
                    statistics
                }
                controls.frame(width: 300)
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .padding(24)
        .frame(minWidth: 940, idealWidth: 1120, minHeight: 620, idealHeight: 780)
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
        .tint(Brand.accent)
        // The File and Edit menus reach this sheet's importer and history. The editor window publishes the same
        // values, so the commands resolve whichever scope owns focus.
        .focusedSceneValue(\.sculptureInsertionActions, SculptureInsertionActions.actions(for: draft))
        .focusedSceneValue(\.sculptureSheetHistory, SculptureHistoryActions.actions(for: draft))
        .task(id: draft.sceneRevision) {
            let identifier = draft.sceneRevision
            if preparedID == identifier, scene != nil {
                isPreparingScene = false
                return
            }
            let (title, library, instances) = draft.renderInput()
            let cachedModels = scene
            isPreparingScene = true
            sceneError = nil
            let worker = Task.detached(priority: .userInitiated) {
                try SculptureWorldScene.prepare(
                    SculptureWorld(title: title, library: library, instances: instances),
                    cachedModels: cachedModels
                )
            }
            do {
                let prepared = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, identifier == draft.sceneRevision else { return }
                scene = prepared
                preparedID = identifier
                isPreparingScene = false
                draft.releasePreparedScene()
            } catch {
                guard !Task.isCancelled, identifier == draft.sceneRevision else { return }
                sceneError = error.localizedDescription
                isPreparingScene = false
            }
        }
        .insertionImporter(
            request: draft.insertionRequest,
            current: { draft.insertionRequest },
            canPresent: { draft.canInsert },
            finish: { draft.finishInsertionRequest() },
            importFiles: { draft.importModels(from: $0) },
            importFolder: { draft.importFolder(from: $0) },
            report: { draft.report($0) }
        )
        .confirmationDialog("Discard this world draft?", isPresented: $confirmingClose) {
            Button("Discard draft", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Save world keeps its exact positions and model references.")
        }
        .interactiveDismissDisabled(draft.hasChanges || draft.isOpeningModel || draft.isMakingUnique)
        .sheet(item: Binding(get: { draft.sharedEdit }, set: { if $0 == nil { draft.cancelSharedEdit() } })) {
            session in
            SculptureSharedModelEditor(
                session: session,
                cancel: { draft.cancelSharedEdit() },
                apply: { await draft.applySharedEdit() }
            )
        }
        .onAppear {
            if !didFrameInitialWorld {
                didFrameInitialWorld = true
                draft.showOverview()
            }
            if initiallyUnsaved { draft.markUnsaved() }
            onDirtyChange(draft.hasChanges)
        }
        .onChange(of: draft.navigationMode) { _, mode in
            controller.stopNavigation()
            if mode == .explore {
                Task { @MainActor in
                    await Task.yield()
                    _ = controller.focusCanvas()
                }
            }
        }
        .onChange(of: draft.hasChanges) { _, value in onDirtyChange(value) }
        .onDisappear {
            controller.stopNavigation()
            draft.cancelModelPreparation()
            uniquePreparation?.cancel()
            onDirtyChange(false)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Explore your world").font(.system(size: 26, weight: .semibold))
                Text("Orbit for the overview. Explore to move through the scene.")
                    .font(.callout).foregroundStyle(Brand.secondary)
            }
            Spacer()
            TextField("World name", text: Binding(get: { draft.title }, set: { draft.setTitle($0) }))
                .textFieldStyle(.roundedBorder).frame(width: 240)
                .disabled(draft.isOpeningModel || draft.isMakingUnique).accessibilityIdentifier("world.title")
        }
    }

    private var canvas: some View {
        ZStack {
            if let scene, let preparedID {
                SculptureLiveWorldView(
                    scene: scene,
                    sceneID: preparedID,
                    focus: draft.focus,
                    renderDistance: draft.renderDistance,
                    detailDistance: draft.detailDistance,
                    camera: draft.camera,
                    controller: controller,
                    mode: draft.navigationMode,
                    explorer: draft.explorer,
                    onCameraChange: { draft.setCamera($0) },
                    onExplorerChange: { draft.setExplorer($0) },
                    onSelectInstance: { id in
                        guard preparedID == draft.sceneRevision, !draft.isOpeningModel else { return }
                        draft.selectInstance(id)
                    }
                )
                .accessibilityIdentifier("world.canvas")
            }
            if isPreparingScene {
                ProgressView("Preparing shared models…").tint(.white).foregroundStyle(.white)
                    .padding(18).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            } else if let sceneError {
                Text(sceneError).font(.callout).foregroundStyle(.white).padding(20)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.065, green: 0.085, blue: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(controller.visibleInstanceCount) visible of \(controller.totalInstanceCount) placed models")
                .font(.callout.weight(.medium)).monospacedDigit()
            Text(
                "\(controller.fullDetailInstanceCount) full detail, \(controller.coarseInstanceCount) simplified, \(controller.boundsProxyInstanceCount) bounds, \(controller.culledInstanceCount) outside range, \(controller.omittedInstanceCount) omitted by capacity"
            )
            .font(.caption).foregroundStyle(Brand.secondary).monospacedDigit()
            Text(
                draft.navigationMode == .explore
                    ? "Click the canvas. WASD moves, drag looks, Q/E moves down/up. Shift moves faster."
                    : "Drag to orbit. Scroll to zoom. Choose Explore to move through the world."
            )
            .font(.caption).foregroundStyle(Brand.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                navigationControls
                Divider()
                focusControls
                Divider()
                distanceControls
                Divider()
                placementControls
                Divider()
                instanceList
            }
            .padding(.trailing, 3)
        }
        .disabled(draft.isOpeningModel || draft.isMakingUnique)
    }

    private var navigationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("View", selection: Binding(get: { draft.navigationMode }, set: { draft.setNavigationMode($0) })) {
                Text("Orbit").tag(SculptureWorldNavigationMode.orbit)
                Text("Explore").tag(SculptureWorldNavigationMode.explore)
            }
            .pickerStyle(.segmented).accessibilityIdentifier("world.navigation.mode")
            HStack {
                Button("Whole World") {
                    controller.stopNavigation(); draft.showOverview()
                }
                .accessibilityIdentifier("world.navigation.overview")
                Menu("Visit…") {
                    ForEach(
                        draft.modelChoices.filter { choice in draft.instances.contains { $0.modelID == choice.id } }
                    ) { choice in
                        Button(choice.title) {
                            controller.stopNavigation()
                            draft.visitModel(choice.id)
                            Task { @MainActor in
                                await Task.yield()
                                _ = controller.focusCanvas()
                            }
                        }
                        .accessibilityIdentifier("world.navigation.visit.\(choice.id)")
                    }
                }
                .accessibilityIdentifier("world.navigation.visit")
            }
            if draft.navigationMode == .explore {
                Text("WASD to move · Drag to look · Q/E down/up · Shift faster")
                    .font(.caption).foregroundStyle(Brand.secondary)
                Text("Free exploration. No collision or gravity.")
                    .font(.caption).foregroundStyle(Brand.secondary)
                HStack {
                    explorationStep("Left", right: -1)
                    explorationStep("Forward", forward: 1)
                    explorationStep("Right", right: 1)
                }
                HStack {
                    explorationStep("Down", vertical: -1)
                    explorationStep("Back", forward: -1)
                    explorationStep("Up", vertical: 1)
                }
            }
            if let notice = draft.overviewNotice {
                Text(notice).font(.caption).foregroundStyle(Brand.secondary)
                    .accessibilityIdentifier("world.navigation.notice")
            }
        }
    }

    private func explorationStep(_ title: String, forward: Double = 0, right: Double = 0, vertical: Double = 0)
        -> some View
    {
        Button(title) { draft.stepExplore(forward: forward, right: right, vertical: vertical) }
            .frame(maxWidth: .infinity).accessibilityIdentifier("world.navigation.\(title.lowercased())")
    }

    private var focusControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus position").font(.headline)
            coordinateField("X", axis: 0, value: $draft.focusX)
            coordinateField("Y", axis: 1, value: $draft.focusY)
            coordinateField("Z", axis: 2, value: $draft.focusZ)
            HStack {
                Button("Go to coordinates") { draft.applyFocus() }
                    .accessibilityIdentifier("world.focus.go")
                Spacer()
                Button("Reset view") { draft.resetCamera() }
                    .accessibilityIdentifier("world.camera.reset")
            }
            Text("Exact whole numbers. Step buttons move 64 cells.")
                .font(.caption).foregroundStyle(Brand.secondary)
        }
    }

    private func coordinateField(_ label: String, axis: Int, value: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.callout.weight(.medium)).frame(width: 16)
            TextField(label + " coordinate", text: value)
                .textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced))
                .onSubmit { draft.applyFocus() }
                .accessibilityIdentifier("world.focus.\(label.lowercased())")
            Button {
                draft.moveFocus(axis: axis, delta: -64)
            } label: {
                Image(systemName: "minus")
            }
            .accessibilityLabel("Move focus \(label) minus 64").accessibilityIdentifier(
                "world.focus.\(label.lowercased()).minus"
            )
            Button {
                draft.moveFocus(axis: axis, delta: 64)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Move focus \(label) plus 64").accessibilityIdentifier(
                "world.focus.\(label.lowercased()).plus"
            )
        }
    }

    private var distanceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Render distance \(draft.renderDistance) cells").font(.callout.weight(.medium))
            Slider(
                value: Binding(get: { Double(draft.renderDistance) }, set: { draft.setRenderDistance(Int($0)) }),
                in: 64...2048,
                step: 64
            )
            .accessibilityLabel("Render distance").accessibilityIdentifier("world.render.distance")
            Text("Full detail within \(draft.detailDistance) cells").font(.callout)
            Slider(
                value: Binding(get: { Double(draft.detailDistance) }, set: { draft.setDetailDistance(Int($0)) }),
                in: 16...Double(draft.renderDistance),
                step: 16
            )
            .accessibilityLabel("Full detail distance").accessibilityIdentifier("world.detail.distance")
            Text(
                "Nearby models have full detail. Farther models use simplified colored terrain. The visible range and capacity remain bounded."
            )
            .font(.caption).foregroundStyle(Brand.secondary)
        }
    }

    private var placementControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Place a model").font(.headline)
            Text("Library: \(draft.library.title)").font(.caption).foregroundStyle(Brand.secondary)
            Picker("Model", selection: Binding(get: { draft.selectedModelID }, set: { draft.selectModel($0) })) {
                ForEach(draft.modelChoices) { choice in Text(choice.title).tag(choice.id) }
            }
            .accessibilityIdentifier("world.model")
            Menu("Edit shared model…") {
                ForEach(draft.editableModels) { model in
                    Button(model.label) { draft.beginSharedEdit(modelID: model.id) }
                        .accessibilityLabel(model.accessibilityLabel)
                        .accessibilityIdentifier("world.model.edit.\(model.id)")
                }
            }
            .disabled(draft.editableModels.isEmpty).accessibilityIdentifier("world.model.edit")
            Picker("Rotation", selection: Binding(get: { draft.quarterTurns }, set: { draft.rotate($0) })) {
                ForEach(0..<4, id: \.self) { Text("\($0 * 90)°").tag($0) }
            }
            .accessibilityIdentifier("world.rotation")
            Button("Place model at focus") { draft.placeAtFocus() }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("world.place")
            VStack(alignment: .leading, spacing: 6) {
                Button("Insert 3md…") { draft.requestInsertion(.files) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .accessibilityIdentifier("world.models.insert")
                Button("Insert model folder…") { draft.requestInsertion(.folder) }
                    .accessibilityIdentifier("world.models.folder")
            }
            Text("Insert places files at focus. A batch continues along X; the saved world includes its children.")
                .font(.caption).foregroundStyle(Brand.secondary)
            if let instance = draft.selectedInstance {
                Text("Selected: \(draft.modelTitle(for: instance.modelID)) at \(Self.location(of: instance))")
                    .font(.caption).lineLimit(1).foregroundStyle(Brand.secondary)
                    .accessibilityIdentifier("world.selection.summary")
                HStack {
                    Button("Jump to it") { draft.jumpToSelected() }.accessibilityIdentifier("world.selection.jump")
                    Button("Move to focus") { draft.moveSelectedToFocus() }.accessibilityIdentifier(
                        "world.selection.move"
                    )
                }
                Button("Delete selected model", role: .destructive) { draft.deleteSelected() }
                    .accessibilityIdentifier("world.selection.delete")
                Button("Make selected model unique") {
                    uniquePreparation = Task {
                        await draft.makeSelectedUnique(); uniquePreparation = nil
                    }
                }
                .disabled(!draft.selectedModelIsVoxel).accessibilityIdentifier("world.selection.unique")
                if !draft.selectedModelIsVoxel {
                    Text("Nested maps remain shared. Choose a voxel placement to make it unique.")
                        .font(.caption).foregroundStyle(Brand.secondary)
                }
                Text("Rotation edits this placement. Its shared model stays unchanged.")
                    .font(.caption).foregroundStyle(Brand.secondary)
            }
        }
    }

    private static func location(of instance: SculptureWorldInstance) -> String {
        "\(instance.origin.x), \(instance.origin.y), \(instance.origin.z)"
    }

    private var instanceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Placed models").font(.headline)
                Spacer()
                Text("\(draft.instances.count)").font(.caption).monospacedDigit().foregroundStyle(Brand.secondary)
            }
            ForEach(draft.pageInstances, id: \.id) { instance in
                Button {
                    draft.selectInstance(instance.id)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.modelTitle(for: instance.modelID))
                            .font(.callout.weight(.medium)).lineLimit(1)
                        Text(Self.location(of: instance))
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(Brand.secondary).lineLimit(1)
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        draft.selectedInstanceID == instance.id ? Brand.accent.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Select \(draft.modelAccessibilityLabel(for: instance.modelID)), at \(Self.location(of: instance))"
                )
                .accessibilityIdentifier("world.instance.\(instance.id)")
            }
            if draft.pageCount > 1 {
                HStack {
                    Button("Previous") { draft.setPage(draft.page - 1) }.disabled(draft.page == 0)
                        .accessibilityIdentifier("world.instances.previous")
                    Text("\(draft.page + 1) / \(draft.pageCount)").font(.caption).monospacedDigit()
                    Button("Next") { draft.setPage(draft.page + 1) }.disabled(draft.page + 1 == draft.pageCount)
                        .accessibilityIdentifier("world.instances.next")
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if draft.isOpeningModel {
                ProgressView("Preparing models…").controlSize(.small)
            } else if let error = draft.error {
                Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("world.error")
            }
            if draft.isMakingUnique { ProgressView("Preparing unique model…").controlSize(.small) }
            if let notice = draft.editingNotice {
                Text(notice).font(.caption).foregroundStyle(Brand.secondary)
            }
            Text(
                "Save world preserves exact positions and references. Open model voxels makes a separate bounded copy for painting."
            )
            .font(.callout).foregroundStyle(Brand.secondary)
            HStack {
                Button(draft.isOpeningModel ? "Cancel preparation" : "Close") {
                    if draft.isOpeningModel {
                        draft.cancelModelPreparation()
                    } else if draft.hasChanges {
                        confirmingClose = true
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction).disabled(draft.isMakingUnique).accessibilityIdentifier("world.close")
                Button("Undo") { draft.undo() }.disabled(!draft.canUndo || draft.isOpeningModel || draft.isMakingUnique)
                    .keyboardShortcut("z").accessibilityIdentifier("world.undo")
                Button("Redo") { draft.redo() }.disabled(!draft.canRedo || draft.isOpeningModel || draft.isMakingUnique)
                    .keyboardShortcut("z", modifiers: [.command, .shift]).accessibilityIdentifier("world.redo")
                Spacer()
                Button("Open model voxels") { draft.openModel(onOpen) }
                    .disabled(draft.isOpeningModel || draft.isMakingUnique).accessibilityIdentifier("world.open.model")
                Button("Save world…") {
                    do { onSave(try draft.world()) } catch { draft.report(error) }
                }
                .buttonStyle(.borderedProminent).disabled(draft.isOpeningModel || draft.isMakingUnique)
                .accessibilityIdentifier("world.save")
            }
        }
    }
}
