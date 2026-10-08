import Foundation
import RookSculpture
import Testing

struct SculptureMathExamplesTests {
    @Test func smallRungsHaveExactSizesAndRepeatTheSameBytes() async throws {
        let small: [SculptureMathExamples.Model] = [.ripple, .torus, .gyroid, .harmonicSphere]
        for model in small {
            let first = try await SculptureMathExamples.sculpture(model)
            let second = try await SculptureMathExamples.sculpture(model)
            let size = model.dimension
            #expect(first.width == size && first.height == size && first.depth == size)
            #expect(first.title == model.title)
            #expect(first.layers == second.layers)
            #expect(first == second)
        }
        let ripple = try await SculptureMathExamples.sculpture(.ripple)
        let repeated = try await SculptureMathExamples.sculpture(.ripple)
        #expect(SculptureCodec.encode(ripple) == SculptureCodec.encode(repeated))
        #expect(try SculptureCodec.decode(SculptureCodec.encode(ripple)) == ripple)
        #expect(SculptureMathExamples.Model.allCases.map(\.dimension) == [16, 32, 64, 128, 256])
    }

    @Test func everyRungHasSensibleOccupancyAndSeveralColors() async throws {
        let bounds: [SculptureMathExamples.Model: ClosedRange<Double>] = [
            .ripple: 0.3...0.6, .torus: 0.08...0.2, .gyroid: 0.04...0.15, .harmonicSphere: 0.15...0.3,
            .terrain: 0.3...0.55,
        ]
        for model in SculptureMathExamples.Model.allCases {
            let sculpture = try await MathLadderFixture.sculpture(model)
            let volume = Double(model.dimension * model.dimension * model.dimension)
            let fraction = Double(sculpture.occupiedCount) / volume
            #expect(bounds[model]?.contains(fraction) == true, "\(model.id) occupancy \(fraction)")
            let glyphs = glyphSet(of: sculpture)
            #expect(glyphs.count >= 3, "\(model.id) uses \(glyphs.count) colors")
            #expect(glyphs.isSubset(of: Set(Sculpture.palette)))
        }
    }

    @Test func formulasProduceTheirRecognizableShapes() async throws {
        let ripple = try await MathLadderFixture.sculpture(.ripple)
        #expect((0..<16).allSatisfy { ripple.containsOccupiedCells(inRow: 15, ofLayer: $0) })
        #expect((0..<16).allSatisfy { !ripple.containsOccupiedCells(inRow: 0, ofLayer: $0) })
        #expect(ripple.layers.allSatisfy { $0[(15 * 16)...].allSatisfy { $0 != Sculpture.empty } })
        let center = try #require(topOccupiedRow(in: ripple, x: 7, z: 7))
        let trough = try #require(topOccupiedRow(in: ripple, x: 10, z: 7))
        #expect(center + 3 < trough)

        let torus = try await MathLadderFixture.sculpture(.torus)
        #expect(torus.glyph(at: SculptureCell(x: 16, y: 16, z: 16)) == Sculpture.empty)
        #expect(glyphSet(of: torus) == Set("x*@".utf8))

        let gyroid = try await MathLadderFixture.sculpture(.gyroid)
        #expect(gyroid.glyph(at: SculptureCell(x: 0, y: 0, z: 0)) == Sculpture.empty)
        #expect(gyroid.glyph(at: SculptureCell(x: 63, y: 63, z: 63)) == Sculpture.empty)
        #expect(glyphSet(of: gyroid).count == 6)

        let planet = try await MathLadderFixture.sculpture(.harmonicSphere)
        #expect(planet.glyph(at: SculptureCell(x: 64, y: 64, z: 64)) == UInt8(ascii: "*"))
        #expect(planet.glyph(at: SculptureCell(x: 64, y: 64, z: 40)) == UInt8(ascii: "x"))
        #expect(planet.glyph(at: SculptureCell(x: 0, y: 0, z: 0)) == Sculpture.empty)
        let surface = glyphSet(of: planet)
        for glyph in "+=o:@#".utf8 { #expect(surface.contains(glyph), "planet lacks \(glyph)") }
    }

    @Test func terrainSpotChecksMatchItsPublishedHeightfield() async throws {
        let terrain = try await MathLadderFixture.sculpture(.terrain)
        #expect(terrain.width == 256 && terrain.height == 256 && terrain.depth == 256)
        #expect(terrain.title == "Layered sine terrain")
        #expect((0..<256).allSatisfy { !terrain.containsOccupiedCells(inRow: 0, ofLayer: $0) })
        #expect(terrain.layers.allSatisfy { $0[(255 * 256)...].allSatisfy { $0 != Sculpture.empty } })
        var checked = 0
        for z in stride(from: 3, to: 256, by: 23) {
            for x in stride(from: 5, to: 256, by: 19) {
                let cx = Double(x) + 0.5
                let cz = Double(z) + 0.5
                let height =
                    100 + 40 * sin(cx / 41 + 0.3) * cos(cz / 53) + 22 * sin((cx + 2 * cz) / 67)
                    + 9 * sin(cx / 13) * sin(cz / 17)
                let boundary = 255.5 - height
                guard height > 84, abs(boundary - boundary.rounded()) > 1e-6 else { continue }
                let top = Int(boundary.rounded(.up))
                let expected = height >= 150 ? UInt8(ascii: "#") : UInt8(ascii: "o")
                #expect(terrain.glyph(at: SculptureCell(x: x, y: top, z: z)) == expected)
                #expect(terrain.glyph(at: SculptureCell(x: x, y: top - 1, z: z)) == Sculpture.empty)
                #expect(terrain.glyph(at: SculptureCell(x: x, y: top + 1, z: z)) == UInt8(ascii: ":"))
                checked += 1
            }
        }
        #expect(checked > 40)
        let glyphs = glyphSet(of: terrain)
        for glyph in "+#o:=@x*".utf8 { #expect(glyphs.contains(glyph), "terrain lacks \(glyph)") }
    }

    @Test func terrainRepeatsTheSameCellsAndItsPublishedOccupancy() async throws {
        // The shared fixture is generated through the gallery catalog; this second generation is direct.
        let shared = try await MathLadderFixture.sculpture(.terrain)
        let fresh = try await SculptureMathExamples.sculpture(.terrain)
        #expect(fresh.layers == shared.layers)
        #expect(fresh == shared)
        // Examples/Math/manifest.json records 6,909,374 occupied cells for math-terrain-256.
        #expect(fresh.occupiedCount == 6_909_374)
        #expect(shared.occupiedCount == 6_909_374)
    }

    @Test func publishedFormulasStateTheirCentersAndReproduceTheOccupiedCells() async throws {
        let torusFormula = SculptureMathExamples.Model.torus.formula
        #expect(torusFormula.contains("hypot(x - 16, z')") && torusFormula.contains("(y - 16, z - 16)"))
        let tilt = -0.45
        try await expectOccupancy(of: .torus) { x, y, z in
            let rotatedY = (y - 16) * cos(tilt) - (z - 16) * sin(tilt)
            let rotatedZ = (y - 16) * sin(tilt) + (z - 16) * cos(tilt)
            let ring = hypot(x - 16, rotatedZ) - 10
            return 4.6 * 4.6 - (ring * ring + rotatedY * rotatedY)
        }

        #expect(SculptureMathExamples.Model.gyroid.formula.contains("inside radius 31.5 of (32, 32, 32)"))
        try await expectOccupancy(of: .gyroid) { x, y, z in
            let (u, v, w) = (2 * Double.pi * x / 32, 2 * Double.pi * y / 32, 2 * Double.pi * z / 32)
            let field = sin(u) * cos(v) + sin(v) * cos(w) + sin(w) * cos(u)
            let radius = ((x - 32) * (x - 32) + (y - 32) * (y - 32) + (z - 32) * (z - 32)).squareRoot()
            return min(0.25 - abs(field), 31.5 - radius)
        }

        #expect(SculptureMathExamples.Model.harmonicSphere.formula.contains("p = (x - 64, y - 64, z - 64)"))
        try await expectOccupancy(of: .harmonicSphere) { x, y, z in
            let (px, py, pz) = (x - 64, y - 64, z - 64)
            let r = (px * px + py * py + pz * pz).squareRoot()
            let (nx, ny, nz) = (px / r, py / r, pz / r)
            let sectoral = nx * nx * nx * nx - 6 * nx * nx * nz * nz + nz * nz * nz * nz
            let surface = 46 + 16 * (0.5 * sectoral + 0.15 * (5 * ny * ny * ny - 3 * ny) + 1.82 * nx * ny * nz)
            return max(surface, 47) - r
        }

        let strata = Array("@x*=".utf8)
        let terrainFormula = SculptureMathExamples.Model.terrain.formula
        #expect(terrainFormula.contains("floor((y + 5 sin(x / 29) + 4 cos(z / 23)) / 8)"))
        let terrain = try await MathLadderFixture.sculpture(.terrain)
        var deepCells = 0
        for z in stride(from: 3, to: 256, by: 23) {
            for x in stride(from: 5, to: 256, by: 19) {
                let (cx, cz) = (Double(x) + 0.5, Double(z) + 0.5)
                let surface =
                    100 + 40 * sin(cx / 41 + 0.3) * cos(cz / 53) + 22 * sin((cx + 2 * cz) / 67)
                    + 9 * sin(cx / 13) * sin(cz / 17)
                for row in 0..<256 {
                    let height = 255.5 - Double(row)
                    let band = (height + 5 * sin(cx / 29) + 4 * cos(cz / 23)) / 8
                    guard surface - height >= 4.001, abs(band - band.rounded()) > 1e-6 else { continue }
                    let expected = strata[((Int(band.rounded(.down)) % 4) + 4) % 4]
                    #expect(terrain.glyph(at: SculptureCell(x: x, y: row, z: z)) == expected, "\(x), \(row), \(z)")
                    deepCells += 1
                }
            }
        }
        #expect(deepCells > 5_000)
    }

    @Test func generationReportsIncreasingProgressEndingAtOne() async throws {
        let recorder = ProgressRecorder()
        _ = try await SculptureMathExamples.sculpture(.torus) { await recorder.record($0) }
        let values = await recorder.values
        #expect(values.count == 33)
        #expect(values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
        #expect(values.allSatisfy { $0 > 0 && $0 <= 1 })
    }

    @Test func cancelledTasksThrowBeforeGenerating() async throws {
        let recorder = ProgressRecorder()
        let modelGate = GenerationGate()
        let model = Task {
            await modelGate.pass()
            return try await SculptureMathExamples.sculpture(.terrain) { await recorder.record($0) }
        }
        await modelGate.waitForArrival()
        model.cancel()
        await modelGate.release()
        await #expect(throws: CancellationError.self) { _ = try await model.value }
        #expect(await recorder.values.isEmpty)
    }

    @Test func cancellingDuringGenerationStopsAtTheNextLayer() async throws {
        let modelGate = GenerationGate()
        let model = Task {
            try await SculptureMathExamples.sculpture(.terrain) { _ in await modelGate.pass() }
        }
        await modelGate.waitForArrival()
        model.cancel()
        await modelGate.release()
        await #expect(throws: CancellationError.self) { _ = try await model.value }
        #expect(await modelGate.passes == 1)
    }

    /// Compares every cell of a model with an independent reading of its published formula, where a positive
    /// margin means occupied. Cells within rounding distance of the boundary are skipped.
    private func expectOccupancy(
        of model: SculptureMathExamples.Model,
        margin: (Double, Double, Double) -> Double
    ) async throws {
        let sculpture = try await MathLadderFixture.sculpture(model)
        let size = model.dimension
        var checked = 0
        var mismatches = 0
        for z in 0..<size {
            let layer = sculpture.layers[z]
            for row in 0..<size {
                for x in 0..<size {
                    let value = margin(Double(x) + 0.5, Double(size - row) - 0.5, Double(z) + 0.5)
                    guard abs(value) > 1e-9 else { continue }
                    if (value >= 0) != (layer[row * size + x] != Sculpture.empty) { mismatches += 1 }
                    checked += 1
                }
            }
        }
        #expect(mismatches == 0, "\(model.id) differs from its published formula in \(mismatches) cells")
        #expect(checked > size * size * size - size * size, "\(model.id) skipped too many boundary cells")
    }

    private func topOccupiedRow(in sculpture: Sculpture, x: Int, z: Int) -> Int? {
        (0..<sculpture.height).first { sculpture.glyph(at: SculptureCell(x: x, y: $0, z: z)) != Sculpture.empty }
    }
}

/// Distinct occupied bytes, read with a fixed table instead of hashing every cell of a large volume.
private func glyphSet(of sculpture: Sculpture) -> Set<UInt8> {
    var seen = [Bool](repeating: false, count: 256)
    for layer in sculpture.layers {
        for glyph in layer { seen[Int(glyph)] = true }
    }
    seen[Int(Sculpture.empty)] = false
    return Set((0..<256).filter { seen[$0] }.map { UInt8($0) })
}

/// Generates each large ladder entry once per test run through the gallery catalog, shared across suites.
enum MathLadderFixture {
    private static let terrain = Task { try await scene(SculptureMathExamples.Model.terrain.id) }

    static func scene(forEntry id: String) async throws -> SculptureScene? {
        switch id {
        case SculptureMathExamples.Model.terrain.id: try await terrain.value
        default: nil
        }
    }

    static func sculpture(_ model: SculptureMathExamples.Model) async throws -> Sculpture {
        guard model == .terrain else { return try await SculptureMathExamples.sculpture(model) }
        guard case .voxels(let sculpture) = try await terrain.value else { throw MathFixtureError.unexpectedKind }
        return sculpture
    }

    private static func scene(_ id: String) async throws -> SculptureScene {
        guard let entry = SculptureGalleryCatalog.entry(id: id) else { throw MathFixtureError.missingEntry }
        return try await SculptureGalleryCatalog.scene(for: entry)
    }
}

enum MathFixtureError: Error { case missingEntry, unexpectedKind }

private actor ProgressRecorder {
    private(set) var values: [Double] = []

    func record(_ value: Double) { values.append(value) }
}

/// Holds generation at its first progress report until the test has cancelled the task.
actor GenerationGate {
    private(set) var passes = 0
    private var arrived = false
    private var released = false
    private var arrivalWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        passes += 1
        if !arrived {
            arrived = true
            arrivalWaiter?.resume()
            arrivalWaiter = nil
        }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitForArrival() async {
        guard !arrived else { return }
        await withCheckedContinuation { arrivalWaiter = $0 }
    }

    func release() {
        released = true
        for waiter in releaseWaiters { waiter.resume() }
        releaseWaiters = []
    }
}
