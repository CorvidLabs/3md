import Foundation
import RookRendering
import RookSculpture
import Testing

@testable import RookApp

/// Gallery listing, opening and cancellation at the model level, through the same destination the editor routes.
@Suite(.serialized)
struct SculptureGalleryBrowserTests {
    @MainActor
    @Test func listingGroupsEveryEntryWithItsSizeAndGeneratesNothingUntilAsked() async throws {
        let log = GenerationLog()
        let started = ContinuousClock.now
        let model = SculptureGalleryBrowserModel(generate: { entry, _ in
            await log.record(entry.id)
            return .voxels(try Sculpture(title: "Stand-in", width: 1, height: 1, layers: [[35]]))
        })
        let sections = model.sections
        let elapsed = ContinuousClock.now - started
        #expect(elapsed < .seconds(1))
        #expect(await log.ids.isEmpty)
        #expect(sections.flatMap(\.entries) == SculptureGalleryCatalog.entries)
        #expect(sections.flatMap(\.entries).count == 32)
        #expect(
            sections.map(\.id) == [
                "model.Sculptures", "model.Maps", "model.Characters", "model.Creatures", "model.Architecture",
                "model.Worlds", "model.Space", "model.Math ladder", "composition.Compositions",
                "composition.Landscapes", "world.Sparse worlds", "world.Landscapes", "world.Volume studies",
            ]
        )
        let ladder = sections.filter { $0.category == "Math ladder" }.flatMap(\.entries)
        #expect(ladder.map(\.id) == SculptureGalleryCatalog.mathLadder.map(\.id))
        #expect(
            ladder.map(SculptureGalleryBrowserModel.sizeLabel(for:)) == [
                "16 × 16 × 16 cells", "32 × 32 × 32 cells", "64 × 64 × 64 cells", "128 × 128 × 128 cells",
                "256 × 256 × 256 cells",
            ]
        )
        #expect(
            SculptureGalleryBrowserModel.spokenSize(for: try entry("gardens-wide-world"))
                == "1,000,000,000,048 by 24 by 1,000,000,000,304 cells, 4 placements"
        )
        #expect(
            SculptureGalleryBrowserModel.sizeLabel(for: try entry("gardens-wide-world"))
                == "1,000,000,000,048 × 24 × 1,000,000,000,304 cells · 4 placements"
        )

        // Every card appearing asks for its thumbnail; only small voxel models generate without being asked.
        for listed in model.entries { model.requestPreview(listed) }
        await model.settlePreviews()
        let small = Set(
            model.entries.filter { $0.kind == .model && max($0.extent.width, $0.extent.height, $0.extent.depth) <= 64 }
                .map(\.id)
        )
        #expect(small.isSuperset(of: ["character-orb", "math-ripple-16", "math-torus-32", "math-gyroid-64"]))
        #expect(small.isDisjoint(with: ["grand-solar-system", "math-harmonic-sphere-128", "math-terrain-256"]))
        #expect(Set(await log.ids) == small)
        #expect(await log.ids.count == small.count)
        for listed in model.entries where !small.contains(listed.id) {
            #expect(model.previews[listed.id] == nil, "\(listed.id) generated a preview without being asked")
            #expect(!model.loadsPreviewAutomatically(listed))
        }
        for id in small {
            guard case .ready? = model.previews[id] else {
                Issue.record("\(id) has no thumbnail")
                continue
            }
        }

        // Load preview is explicit and generates exactly that entry.
        model.requestPreview(try entry("math-terrain-256"), explicitly: true)
        await model.settlePreviews()
        #expect(await log.ids.last == "math-terrain-256")
        #expect(await log.ids.count == small.count + 1)
    }

    @MainActor
    @Test func filtersNarrowByKindCategoryAndSearch() throws {
        let model = SculptureGalleryBrowserModel()
        model.kind = .world
        #expect(model.sections.allSatisfy { $0.kind == .world })
        #expect(model.categories == ["All examples", "Landscapes", "Sparse worlds", "Volume studies"])
        model.category = "Sparse worlds"
        #expect(model.sections.flatMap(\.entries).map(\.id) == ["gardens-wide-world"])
        // Compositions have no ladder rung, so the category falls back to every category.
        model.kind = .composition
        #expect(model.category == SculptureGalleryBrowserModel.allCategories)
        #expect(
            model.sections.flatMap(\.entries).map(\.id) == ["courtyard-of-courtyards", "blockhaven-composition"]
        )
        model.kind = nil
        model.search = "Skyreach"
        #expect(model.sections.flatMap(\.entries).map(\.id) == ["skyreach-1024-world"])
        model.search = "gyroid"
        #expect(model.sections.flatMap(\.entries).map(\.id) == ["math-gyroid-64"])
        model.search = "no such example"
        #expect(model.sections.isEmpty)
    }

    @MainActor
    @Test func openingAModelHandsItsPreparedGeometryToTheMainDocument() async throws {
        let model = SculptureGalleryBrowserModel()
        let gyroid = try entry("math-gyroid-64")
        var delivered: [SculptureGalleryOpened] = []
        model.open(gyroid) { delivered.append($0) }
        #expect(model.loading?.stage == .generating)
        #expect(model.loading?.fraction == 0)
        await model.openTask?.value
        #expect(model.loading == nil && model.error == nil)
        #expect(delivered.count == 1)
        let opened = try #require(delivered.first)
        guard case .document(let routed, let sculpture, let geometry) = SculptureGalleryDestination(opened) else {
            Issue.record("A voxel model must replace the main document")
            return
        }
        #expect(routed == gyroid)
        #expect(sculpture == (try await SculptureMathExamples.sculpture(.gyroid)))
        let workspace = SculptureWorkspace()
        workspace.paint(SculptureCell(x: 2, y: 2, z: workspace.layer), start: true)
        workspace.endStroke()
        #expect(workspace.isDirty)
        workspace.replace(with: sculpture, preparedGeometry: geometry)
        #expect(workspace.sculpture == sculpture && workspace.titleDraft == "Gyroid shell")
        #expect(!workspace.canUndo && !workspace.canRedo)
        let handed = try #require(workspace.preparedGeometry(for: workspace.sculptureRevision))
        #expect(handed.scene == (try SculptureVoxelSurfaceExtractor.extract(sculpture)))
        // Any voxel change drops the handed-over geometry.
        let empty = try #require(
            (0..<64).lazy.compactMap { x in
                let cell = SculptureCell(x: x, y: 0, z: 0)
                return sculpture.glyph(at: cell) == Sculpture.empty ? cell : nil
            }.first
        )
        workspace.paint(empty, start: true)
        workspace.endStroke()
        #expect(workspace.canUndo)
        #expect(workspace.preparedGeometry(for: workspace.sculptureRevision) == nil)
    }

    @MainActor
    @Test func openingACompositionStartsAnUnmodifiedDraftWithItsAssembledPreview() async throws {
        let model = SculptureGalleryBrowserModel()
        let courtyard = try entry("courtyard-of-courtyards")
        var delivered: [SculptureGalleryOpened] = []
        model.open(courtyard) { delivered.append($0) }
        // Authored entries report no intermediate fractions, so their progress is indeterminate.
        #expect(model.loading?.stage == .generating)
        #expect(model.loading?.fraction == nil)
        await model.openTask?.value
        #expect(delivered.count == 1 && model.loading == nil && model.error == nil)
        let opened = try #require(delivered.first)
        guard case .composition(let draft) = SculptureGalleryDestination(opened) else {
            Issue.record("A composition must open in the composition editor")
            return
        }
        #expect(try draft.composition() == SculptureCompositionExamples.courtyard())
        #expect(!draft.hasChanges && !draft.canUndo && !draft.isViewOnly)
        let preview = try #require(draft.preview)
        #expect(preview.width == courtyard.extent.width)
        #expect(preview.height == courtyard.extent.height)
        #expect(preview.depth == courtyard.extent.depth)
        // A preview with other bounds is never adopted.
        let fresh = SculptureCompositionDraft(composition: try SculptureCompositionExamples.courtyard())
        fresh.adoptPreview(Sculpture.orb())
        #expect(fresh.preview == nil)
    }

    @MainActor
    @Test func openingAWorldStartsAnUnmodifiedDraftWithItsPreparedScene() async throws {
        let model = SculptureGalleryBrowserModel()
        let garden = try entry("gardens-wide-world")
        var delivered: [SculptureGalleryOpened] = []
        var stages: [SculptureGalleryBrowserModel.Stage] = []
        model.open(garden) { delivered.append($0) }
        while let stage = model.loading?.stage {
            if stages.last != stage { stages.append(stage) }
            try await Task.sleep(for: .milliseconds(2))
        }
        await model.openTask?.value
        #expect(stages.first == .generating)
        #expect(delivered.count == 1 && model.error == nil)
        let opened = try #require(delivered.first)
        guard case .world(let draft) = SculptureGalleryDestination(opened) else {
            Issue.record("A world must open in the world editor")
            return
        }
        #expect(draft.instances.count == 4)
        #expect(draft.instances.count == SculptureGalleryBrowserModel.placementCounts[garden.id])
        #expect(!draft.hasChanges && !draft.canUndo)
        let scene = try #require(draft.preparedScene)
        #expect(scene.world == (try draft.world()))
        #expect(scene.modelCount == Set(draft.instances.map(\.modelID)).count)
        // A scene for another world is refused, and a placement change retires the handed-over scene.
        let other = SculptureWorldDraft(world: try SculptureBlockWorldExamples.world())
        #expect(!other.adoptPreparedScene(scene))
        #expect(other.preparedScene == nil)
        draft.deleteSelected()
        #expect(draft.hasChanges)
        #expect(draft.preparedScene == nil)
    }

    @MainActor
    @Test func cancellingALargeEntryWhileGeneratingLeavesTheDocumentSelectionAndHistory() async throws {
        let workspace = try editedWorkspace()
        let before = WorkspaceState(workspace)
        let model = SculptureGalleryBrowserModel()
        var delivered = 0
        model.open(try entry("math-terrain-256")) { opened in
            delivered += 1
            route(opened, into: workspace)
        }
        try await waitUntil { (model.loading?.fraction ?? 0) > 0 }
        let running = try #require(model.openTask)
        model.cancelOpening()
        #expect(model.loading == nil)
        await running.value
        try await drainMainActor()
        #expect(delivered == 0)
        #expect(model.loading == nil && model.error == nil && model.openTask == nil)
        #expect(WorkspaceState(workspace) == before)
        workspace.undo()
        #expect(workspace.sculpture == Sculpture.orb())
    }

    @MainActor
    @Test func cancellingWhilePreparingGeometryPublishesNothing() async throws {
        let workspace = try editedWorkspace()
        let before = WorkspaceState(workspace)
        let model = SculptureGalleryBrowserModel(
            generate: { _, progress in
                await progress(0.5)
                return .voxels(try Sculpture(title: "Stand-in", width: 1, height: 1, layers: [[35]]))
            },
            prepare: { _, _ in
                // Holds the worker in the preparation stage until the opening is cancelled.
                while !Task.isCancelled { Thread.sleep(forTimeInterval: 0.002) }
                throw CancellationError()
            }
        )
        var delivered = 0
        model.open(try entry("math-terrain-256")) { opened in
            delivered += 1
            route(opened, into: workspace)
        }
        try await waitUntil { model.loading?.stage == .preparingGeometry }
        #expect(model.loading?.fraction == nil)
        let running = try #require(model.openTask)
        model.cancelOpening()
        await running.value
        try await drainMainActor()
        #expect(delivered == 0)
        #expect(model.loading == nil && model.error == nil)
        #expect(WorkspaceState(workspace) == before)
    }

    @MainActor
    @Test func doneStopsAnOpeningAndItsThumbnailsBeforeTheGalleryClosesSoALateResultIsNeverPublished() async throws {
        let workspace = try editedWorkspace()
        let before = WorkspaceState(workspace)
        let gate = GenerationGate()
        let model = SculptureGalleryBrowserModel(generate: { _, _ in
            // Ignores cancellation, as an authored factory does, and finishes only after Done.
            await gate.pass()
            return .voxels(try Sculpture(title: "Stand-in", width: 1, height: 1, layers: [[35]]))
        })
        var delivered = 0
        model.open(try entry("math-terrain-256")) { opened in
            delivered += 1
            route(opened, into: workspace)
        }
        let composition = try entry("blockhaven-composition")
        model.requestPreview(composition, explicitly: true)
        try await waitUntil { await gate.arrivals == 2 }
        let running = try #require(model.openTask)
        var stoppedBeforeDismissal = false
        var dismissals = 0
        model.close {
            dismissals += 1
            stoppedBeforeDismissal = model.loading == nil && model.openTask == nil && model.previews.isEmpty
        }
        #expect(dismissals == 1 && stoppedBeforeDismissal)
        await gate.open()
        await running.value
        await model.settlePreviews()
        try await drainMainActor()
        #expect(delivered == 0)
        #expect(model.loading == nil && model.error == nil && model.openTask == nil)
        #expect(model.previews[composition.id] == nil)
        #expect(WorkspaceState(workspace) == before)
    }

    @MainActor
    @Test func loadPreviewAgainAfterCancelPublishesTheNewThumbnailWhileTheFirstWorkerStillRuns() async throws {
        let gate = GenerationGate()
        let model = SculptureGalleryBrowserModel(generate: { _, _ in
            // The first worker ignores its cancellation until the gate opens, like a long authored factory.
            await gate.pass()
            return .voxels(try Sculpture(title: "Stand-in", width: 1, height: 1, layers: [[35]]))
        })
        let composition = try entry("blockhaven-composition")
        model.requestPreview(composition, explicitly: true)
        try await waitUntil { await gate.arrivals == 1 }
        model.cancelPreview(composition.id)
        #expect(model.previews[composition.id] == nil)
        model.requestPreview(composition, explicitly: true)
        guard case .loading? = model.previews[composition.id] else {
            Issue.record("Load preview again must start a new request")
            return
        }
        // The cancelled worker finishes first; it must neither clear nor publish the new request's thumbnail.
        await gate.open()
        await model.settlePreviews()
        #expect(await gate.arrivals == 2)
        guard case .ready(let preview)? = model.previews[composition.id] else {
            Issue.record("The second Load preview must publish its thumbnail")
            return
        }
        #expect(preview.image != nil)
    }

    @MainActor
    @Test func aFailedOpeningReportsItAndKeepsTheGalleryUsable() async throws {
        let model = SculptureGalleryBrowserModel(generate: { entry, _ in
            throw SculptureGalleryError.unknownEntry(entry.id)
        })
        var delivered = 0
        model.open(try entry("math-ripple-16")) { _ in delivered += 1 }
        await model.openTask?.value
        #expect(delivered == 0 && model.loading == nil)
        #expect(model.error?.hasPrefix("Sine ripple couldn’t open.") == true)
        model.dismissError()
        #expect(model.error == nil)
    }

    @Test func placementCountsMatchEveryGeneratedWorld() async throws {
        let worlds = SculptureGalleryCatalog.entries.filter { $0.kind == .world }
        #expect(Set(worlds.map(\.id)) == Set(SculptureGalleryBrowserModel.placementCounts.keys))
        for world in worlds {
            guard case .world(let generated) = try await SculptureGalleryCatalog.scene(for: world) else {
                Issue.record("\(world.id) is not a world")
                continue
            }
            #expect(generated.instances.count == SculptureGalleryBrowserModel.placementCounts[world.id], "\(world.id)")
        }
    }

    @Test func previewsReduceLargeVolumesAndDrawWorldsAsBoundedPlans() throws {
        var layers = Array(repeating: Array(repeating: Sculpture.empty, count: 130 * 10), count: 70)
        layers[2][2 * 130 + 1] = 42
        layers[1][1 * 130 + 2] = 64
        layers[0][9 * 130 + 0] = 35
        let wide = try Sculpture(title: "Wide", width: 130, height: 10, layers: layers)
        let reduced = try SculptureGalleryPreview.reduced(wide)
        #expect(reduced.width == 44 && reduced.height == 4 && reduced.depth == 24)
        // Each reduced cell keeps the topmost occupied glyph of its block.
        #expect(reduced.glyph(at: SculptureCell(x: 0, y: 0, z: 0)) == 64)
        #expect(reduced.glyph(at: SculptureCell(x: 0, y: 3, z: 0)) == 35)
        #expect(reduced.occupiedCount == 2)
        let orb = Sculpture.orb()
        #expect(try SculptureGalleryPreview.reduced(orb) == orb)
        let plan = try #require(try SculptureGalleryPreview.plan(of: SculptureWorldExamples.wideWorld()))
        #expect(plan.width == SculptureGalleryPreview.width && plan.height == SculptureGalleryPreview.height)
    }

    // MARK: - Helpers

    private func entry(_ id: String) throws -> SculptureGalleryEntry {
        try #require(SculptureGalleryCatalog.entry(id: id))
    }

    /// A workspace with one painted stroke in its history and a selected cell away from the origin.
    @MainActor
    private func editedWorkspace() throws -> SculptureWorkspace {
        let workspace = SculptureWorkspace()
        let cell = try #require(
            (0..<16).lazy.compactMap { x in
                let candidate = SculptureCell(x: x, y: 0, z: 0)
                return workspace.sculpture.glyph(at: candidate) == Sculpture.empty ? candidate : nil
            }.first
        )
        workspace.paint(cell, start: true)
        workspace.endStroke()
        workspace.select(SculptureCell(x: 3, y: 4, z: 5))
        #expect(workspace.canUndo && workspace.isDirty)
        return workspace
    }

    /// The editor's routing for a model: replace the document with its prepared geometry.
    @MainActor
    private func route(_ opened: SculptureGalleryOpened, into workspace: SculptureWorkspace) {
        guard case .document(_, let sculpture, let geometry) = SculptureGalleryDestination(opened) else { return }
        workspace.replace(with: sculpture, preparedGeometry: geometry)
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(60)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for the gallery")
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Lets progress reports that were already queued for the main actor run before the assertions.
    @MainActor
    private func drainMainActor() async throws {
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))
    }
}

/// Which entries a stand-in factory was asked to generate, in order.
private actor GenerationLog {
    private(set) var ids: [String] = []

    func record(_ id: String) { ids.append(id) }
}

/// Holds stand-in generators, whatever their cancellation, until the test opens it.
private actor GenerationGate {
    private(set) var arrivals = 0
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        arrivals += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

/// The document, selection and history a cancelled opening must leave alone.
private struct WorkspaceState: Equatable {
    let sculpture: Sculpture
    let titleDraft: String
    let layer: Int
    let column: Int
    let row: Int
    let canUndo: Bool
    let canRedo: Bool
    let isDirty: Bool
    let documentGeneration: UUID
    let sculptureRevision: UUID

    @MainActor
    init(_ workspace: SculptureWorkspace) {
        sculpture = workspace.sculpture
        titleDraft = workspace.titleDraft
        layer = workspace.layer
        column = workspace.column
        row = workspace.row
        canUndo = workspace.canUndo
        canRedo = workspace.canRedo
        isDirty = workspace.isDirty
        documentGeneration = workspace.documentGeneration
        sculptureRevision = workspace.sculptureRevision
    }
}
