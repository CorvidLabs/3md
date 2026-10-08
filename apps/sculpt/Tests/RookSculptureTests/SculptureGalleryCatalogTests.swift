import Foundation
import Testing

@testable import RookSculpture

struct SculptureGalleryCatalogTests {
    @Test func listingIsPlainMetadataThatGeneratesNothing() throws {
        let entries = SculptureGalleryCatalog.entries
        #expect(entries.count == 32)
        #expect(Set(entries.map(\.id)).count == entries.count)
        // Entries are Codable values of strings, integers and a kind: a round trip reproduces each one exactly,
        // and the whole listing is a few kilobytes, so no entry can hold a generated scene or a factory.
        let data = try JSONEncoder().encode(entries)
        #expect(try JSONDecoder().decode([SculptureGalleryEntry].self, from: data) == entries)
        #expect(data.count < 16_384)
        for entry in entries { #expect(SculptureGalleryCatalog.entry(id: entry.id) == entry) }
        #expect(SculptureGalleryCatalog.entry(id: "missing-example") == nil)
        let kinds = entries.map(\.kind)
        #expect(kinds.filter { $0 == .model }.count == 26)
        #expect(kinds.filter { $0 == .composition }.count == 2)
        #expect(kinds.filter { $0 == .world }.count == 4)
        #expect(kinds == kinds.sorted { order($0) < order($1) })
    }

    @Test func listingRunsNoBuilderOrGenerator() {
        // The listing is rebuilt uncached inside the probe, so the check holds whichever test ran first.
        let recorder = SculptureGenerationRecorder()
        SculptureGenerationProbe.$recorder.withValue(recorder) {
            let listings = SculptureGalleryCatalog.makeTable()
            #expect(listings.map(\.entry) == SculptureGalleryCatalog.entries)
            #expect(SculptureGalleryCatalog.makeMathLadder() == SculptureGalleryCatalog.mathLadder)
            for entry in SculptureGalleryCatalog.entries {
                #expect(SculptureGalleryCatalog.entry(id: entry.id) == entry)
            }
            #expect(SculptureExamples.recipes.count == 21)
        }
        #expect(recorder.names.isEmpty, "listing ran \(recorder.names)")
    }

    @Test func openingTheSmallestAuthoredModelBuildsOnlyThatModel() async throws {
        let orb = try #require(SculptureGalleryCatalog.entry(id: "character-orb"))
        let recorder = SculptureGenerationRecorder()
        let scene = try await SculptureGenerationProbe.$recorder.withValue(recorder) {
            try await SculptureGalleryCatalog.scene(for: orb)
        }
        #expect(scene == .voxels(.orb()))
        #expect(recorder.names == ["character-orb"])
        #expect(!recorder.names.contains("grand-solar-system"))
        #expect(!recorder.names.contains("SculptureExamples.all"))
    }

    @Test func cancellingAtTheStartReachesNoOtherEntrysBuilder() async throws {
        for entry in SculptureGalleryCatalog.entries {
            let recorder = SculptureGenerationRecorder()
            let task = SculptureGenerationProbe.$recorder.withValue(recorder) {
                Task {
                    try await SculptureGalleryCatalog.scene(for: entry) { fraction in
                        guard fraction == 0 else { return }
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            }
            await #expect(throws: CancellationError.self, "\(entry.id)") { _ = try await task.value }
            let names = recorder.names
            if entry.formula == nil, entry.kind == .model {
                // An authored voxel entry checks cancellation before building its volume.
                #expect(names.isEmpty, "\(entry.id) built \(names)")
            } else {
                // Other entries enter their own generator, which proves the probe sees it, and no voxel catalog.
                #expect(names.contains(entry.id), "\(entry.id) recorded \(names)")
                #expect(!names.contains("SculptureExamples.all"), "\(entry.id)")
                #expect(!names.contains("grand-solar-system"), "\(entry.id)")
            }
        }
    }

    @Test func voxelMetadataMatchesTheGeneratedCatalogExactly() {
        let listed = SculptureGalleryCatalog.entries.prefix(SculptureExamples.all.count)
        #expect(listed.count == 21)
        for (entry, example) in zip(listed, SculptureExamples.all) {
            #expect(entry.id == example.id)
            #expect(entry.title == example.title)
            #expect(entry.summary == example.summary)
            #expect(entry.category == example.category)
            #expect(entry.kind == .model)
            #expect(entry.formula == nil)
            let sculpture = example.sculpture
            #expect(
                entry.extent
                    == SculptureGalleryExtent(width: sculpture.width, height: sculpture.height, depth: sculpture.depth)
            )
        }
    }

    @Test func mathLadderRunsFromSixteenCellsToTwoHundredFiftySix() {
        let ladder = SculptureGalleryCatalog.mathLadder
        #expect(ladder.map(\.extent.width) == [16, 32, 64, 128, 256])
        #expect(ladder.allSatisfy { $0.kind == .model })
        #expect(ladder.allSatisfy { $0.category == "Math ladder" && $0.formula?.isEmpty == false })
        #expect(ladder.allSatisfy { SculptureGalleryCatalog.entries.contains($0) })
        #expect(SculptureGalleryCatalog.entries.filter { $0.formula != nil }.count == 5)
        for entry in ladder {
            #expect(entry.extent.height == entry.extent.width && entry.extent.depth == entry.extent.width)
        }
    }

    @Test func everyFactoryCreatesItsDeclaredKindExtentAndTitle() async throws {
        for entry in SculptureGalleryCatalog.entries {
            let scene: SculptureScene
            if let shared = try await MathLadderFixture.scene(forEntry: entry.id) {
                scene = shared
            } else {
                scene = try await SculptureGalleryCatalog.scene(for: entry)
            }
            #expect(kind(of: scene) == entry.kind, "\(entry.id)")
            #expect(SculptureGalleryExtent(of: scene) == entry.extent, "\(entry.id)")
            #expect(scene.title == entry.title, "\(entry.id)")
        }
    }

    @Test func factoriesReportProgressFromZeroToOne() async throws {
        let ripple = try #require(SculptureGalleryCatalog.entry(id: "math-ripple-16"))
        let recorder = CatalogProgressRecorder()
        let scene = try await SculptureGalleryCatalog.scene(for: ripple) { await recorder.record($0) }
        #expect(scene == .voxels(try await SculptureMathExamples.sculpture(.ripple)))
        let values = await recorder.values
        #expect(values.first == 0)
        #expect(values.last == 1)
        #expect(values.count == 19)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })

        let courtyard = try #require(SculptureGalleryCatalog.entry(id: "courtyard-of-courtyards"))
        let authored = CatalogProgressRecorder()
        _ = try await SculptureGalleryCatalog.scene(for: courtyard) { await authored.record($0) }
        #expect(await authored.values == [0, 1])
    }

    @Test func unlistedOrAlteredEntriesAreRefused() async throws {
        let listed = try #require(SculptureGalleryCatalog.entry(id: "math-torus-32"))
        let altered = SculptureGalleryEntry(
            id: listed.id,
            title: listed.title,
            summary: listed.summary,
            category: listed.category,
            kind: listed.kind,
            extent: SculptureGalleryExtent(width: 999, height: 999, depth: 999),
            formula: listed.formula
        )
        await #expect(throws: SculptureGalleryError.unknownEntry("math-torus-32")) {
            _ = try await SculptureGalleryCatalog.scene(for: altered)
        }
        let unknown = SculptureGalleryEntry(
            id: "missing-example",
            title: "Missing",
            summary: "Not listed.",
            category: "Sculptures",
            kind: .model,
            extent: SculptureGalleryExtent(width: 1, height: 1, depth: 1)
        )
        await #expect(throws: SculptureGalleryError.unknownEntry("missing-example")) {
            _ = try await SculptureGalleryCatalog.scene(for: unknown)
        }
        #expect(SculptureGalleryError.unknownEntry("x").errorDescription?.contains("'x'") == true)
    }

    @Test func cancellingAnOpeningEntryPublishesNothing() async throws {
        let terrain = try #require(SculptureGalleryCatalog.entry(id: "math-terrain-256"))
        let gate = GenerationGate()
        let task = Task {
            try await SculptureGalleryCatalog.scene(for: terrain) { _ in await gate.pass() }
        }
        await gate.waitForArrival()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await gate.passes == 1)

        let blockhaven = try #require(SculptureGalleryCatalog.entry(id: "blockhaven-world"))
        let authoredGate = GenerationGate()
        let authored = Task {
            try await SculptureGalleryCatalog.scene(for: blockhaven) { _ in await authoredGate.pass() }
        }
        await authoredGate.waitForArrival()
        authored.cancel()
        await authoredGate.release()
        await #expect(throws: CancellationError.self) { _ = try await authored.value }
    }

    @Test func extentsMeasureRotatedPlacementsAndSaturateAtIntMaximum() throws {
        let tall = try Sculpture(
            title: "Tall",
            width: 2,
            height: 5,
            layers: [[UInt8](repeating: UInt8(ascii: "#"), count: 10)]
        )
        let root = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [Array("T".utf8)],
            tileSize: SculptureTileSize(width: 5, height: 5, depth: 1),
            bindings: [SculptureModelBinding(glyph: UInt8(ascii: "T"), modelID: "tall")]
        )
        let library = try SculptureComposition(
            title: "Library",
            rootID: "root",
            models: ["root": .tiles(root), "tall": .sculpture(tall)]
        )
        #expect(SculptureGalleryExtent(of: .composition(library)) == .init(width: 5, height: 5, depth: 1))
        let turned = try SculptureWorld(
            title: "Turned",
            library: library,
            instances: [
                SculptureWorldInstance(id: "a", modelID: "tall", origin: .init(x: 10, y: 0, z: 0), quarterTurns: 1),
                SculptureWorldInstance(id: "b", modelID: "tall", origin: .init(x: 0, y: 0, z: 3)),
            ]
        )
        #expect(SculptureGalleryExtent(of: .world(turned)) == .init(width: 15, height: 5, depth: 4))
        let distant = try SculptureWorld(
            title: "Distant",
            library: library,
            instances: [
                SculptureWorldInstance(id: "low", modelID: "tall", origin: .init(x: .min, y: 0, z: 0)),
                SculptureWorldInstance(id: "high", modelID: "tall", origin: .init(x: .max - 256, y: 0, z: 0)),
            ]
        )
        #expect(SculptureGalleryExtent(of: .world(distant)).width == .max)
        let empty = try SculptureWorld(title: "Empty", library: library, instances: [])
        #expect(SculptureGalleryExtent(of: .world(empty)) == .init(width: 0, height: 0, depth: 0))
        #expect(SculptureGalleryExtent(of: .voxels(tall)) == .init(width: 2, height: 5, depth: 1))
    }

    private func kind(of scene: SculptureScene) -> SculptureGalleryKind {
        switch scene {
        case .voxels: .model
        case .composition: .composition
        case .world: .world
        }
    }

    private func order(_ kind: SculptureGalleryKind) -> Int {
        SculptureGalleryKind.allCases.firstIndex(of: kind) ?? 0
    }
}

private actor CatalogProgressRecorder {
    private(set) var values: [Double] = []

    func record(_ value: Double) { values.append(value) }
}
