import Foundation
import ThreeMD

/// A selected, already decoded scene and its optional portable identities and metadata.
public struct SculptureInsertionInput: Equatable, Sendable {
    public let scene: SculptureScene
    public let snapshot: SculptureThreeMDSnapshot?
    /// The caller's label for this input, normally its filename. Refusals name it instead of a generated model ID.
    public let sourceName: String?

    public init(scene: SculptureScene, snapshot: SculptureThreeMDSnapshot? = nil, sourceName: String? = nil) {
        self.scene = scene
        self.snapshot = snapshot
        self.sourceName = sourceName
    }

    /// The name used in refusals: the source filename when known, otherwise the scene title.
    public var displayName: String { sourceName ?? scene.title }
}

/// The complete replacement is published once, allowing the host to register one Undo operation.
public struct SculptureInsertionResult: Equatable, Sendable {
    public let scene: SculptureScene
    /// The complete portable scene. It is present only when the parent or an input carried portable data, so a
    /// scene with none never acquires a snapshot that later insertions would have to preserve.
    public let snapshot: SculptureThreeMDSnapshot?
    /// Imported root model IDs in caller input order, including roots of nested compositions.
    public let placedRootIDs: [String]
    /// True when the portable limit refused and native values were used because no portable data would be lost.
    public let usedNativeFallback: Bool
}

/// One tile that an insertion batch would fill, with the model it would replace.
public struct SculptureInsertionTarget: Equatable, Sendable {
    public let cell: SculptureCell
    public let currentGlyph: UInt8
    public let currentModelID: String?
    public var isOccupied: Bool { currentGlyph != Sculpture.empty }
}

public enum SculptureInsertionError: Error, Equatable, LocalizedError, Sendable {
    case noInputs, unsupportedChild, mismatchedSnapshot, invalidSelection
    case insufficientCells(needed: Int, available: Int)
    case noAvailableGlyph(needed: Int, available: Int)
    case coordinateOverflow
    case tooManyModels(current: Int, incoming: Int, maximum: Int)
    case tooManyPlacements(current: Int, incoming: Int, maximum: Int)
    case tooManyFiles(count: Int, maximum: Int)
    case tooManyDiscoveredEntries(maximum: Int)
    case aggregateBytesExceeded(source: String, maximum: Int)
    case modelDoesNotFit(source: String, required: String, current: String)
    /// The combined resolved voxel volume of every model in the scene would exceed `maximum`.
    case resolvedVolumeExceeded(source: String, maximum: Int)
    /// The portable limit refused and portable data on the parent or these sources would be lost natively.
    case portableLimitExceeded(parent: Bool, sources: [String])
    case source(name: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .noInputs: "Choose at least one voxel or composition file to insert."
        case .unsupportedChild: "Insert a voxel model or composition. A sparse world cannot be used as a child model."
        case .mismatchedSnapshot: "The preserved document does not describe the selected scene."
        case .invalidSelection: "Choose a cell inside the parent composition."
        case .insufficientCells(let needed, let available):
            "Inserting \(Self.count(needed, "model")) needs \(Self.count(needed, "consecutive tile")) from the selected start, but \(available) remain. Select an earlier tile or enlarge the map."
        case .noAvailableGlyph(let needed, let available):
            "The composition has \(Self.count(available, "unused printable character")), and \(Self.count(needed, "model")) need one each."
        case .coordinateOverflow: "The inserted world models would exceed the signed 64-bit coordinate range."
        case .tooManyModels(let current, let incoming, let maximum):
            "Inserting \(Self.count(incoming, "model")) would exceed the \(maximum)-model limit; this scene has \(current) now. Insert fewer or smaller graphs."
        case .tooManyPlacements(let current, let incoming, let maximum):
            "A sparse world can hold at most \(maximum) placed models; it has \(current) and this insertion adds \(incoming)."
        case .tooManyFiles(let count, let maximum):
            "This insertion names \(count) files, and at most \(maximum) can be inserted at once. Select fewer files."
        case .tooManyDiscoveredEntries(let maximum):
            "This folder has more than \(maximum) entries. Choose a smaller folder or select the files directly."
        case .aggregateBytesExceeded(let source, let maximum):
            "\(source) would take this insertion past its \(maximum / 1_048_576) MiB total. Insert fewer or smaller files."
        case .modelDoesNotFit(let source, let required, let current):
            "\(source) needs \(required) cells. Current tiles are \(current) cells. Increase the tile size or choose a smaller model."
        case .resolvedVolumeExceeded(let source, let maximum):
            "\(source) would push the combined model volumes of this scene past \(maximum / 1_048_576) MiB of voxels. Insert fewer or smaller models."
        case .portableLimitExceeded(let parent, let sources):
            Self.portableLimitDescription(parent: parent, sources: sources)
        case .source(let name, let reason): "\(name): \(reason)"
        }
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    private static func portableLimitDescription(parent: Bool, sources: [String]) -> String {
        let names = (parent ? ["the open scene"] : []) + sources
        let joined: String
        switch names.count {
        case 0: joined = "this scene"
        case 1: joined = names[0]
        default: joined = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
        return
            "This insertion would exceed ThreeMD's portable limit of 16 MiB per definition and 20 MiB per file. A native copy would lose the portable data in \(joined), so nothing was inserted. Choose smaller models or reopen the scene from a native Sculpt file."
    }
}

/// Inserts complete local graphs without flattening, path resolution or partially mutating a parent.
public enum SculptureSceneInsertion {
    /// Describes the consecutive tiles a batch of `count` models would fill from `cell`, row by row and layer by layer.
    public static func targets(
        in parent: SculptureComposition,
        count: Int,
        at cell: SculptureCell
    ) throws -> [SculptureInsertionTarget] {
        guard count > 0 else { throw SculptureInsertionError.noInputs }
        guard case .tiles(let map)? = parent.models[parent.rootID], contains(cell, in: map) else {
            throw SculptureInsertionError.invalidSelection
        }
        let start = cell.z * map.width * map.height + cell.y * map.width + cell.x
        let remaining = map.width * map.height * map.depth - start
        guard count <= remaining else {
            throw SculptureInsertionError.insufficientCells(needed: count, available: remaining)
        }
        let models = Dictionary(map.bindings.map { ($0.glyph, $0.modelID) }) { first, _ in first }
        return (0..<count).map { index in
            let position = start + index
            let target = SculptureCell(
                x: position % map.width,
                y: (position / map.width) % map.height,
                z: position / (map.width * map.height)
            )
            let glyph = map.layers[target.z][target.y * map.width + target.x]
            return SculptureInsertionTarget(cell: target, currentGlyph: glyph, currentModelID: models[glyph])
        }
    }

    /// Places selected roots in row-major cells, replacing those cells while retaining the tile size.
    ///
    /// Portable identities and annotations are preserved. When neither the parent nor any input carries a
    /// portable snapshot and the portable limit refuses, the same placement is made with native values only.
    public static func intoComposition(
        _ parent: SculptureComposition,
        preserving snapshot: SculptureThreeMDSnapshot? = nil,
        inputs: [SculptureInsertionInput],
        at cell: SculptureCell
    ) throws -> SculptureInsertionResult {
        let plan = try compositionPlan(parent, preserving: snapshot, inputs: inputs, at: cell)
        return try publish(
            scene: .composition(plan.candidate),
            rootIDs: plan.rootIDs,
            parentSnapshot: snapshot,
            inputs: inputs
        ) {
            let previous = try SculptureThreeMDCodec.capture(.composition(parent), preserving: snapshot)
            return try portableSnapshot(of: .composition(plan.candidate), after: previous, plan: plan, inputs: inputs)
        }
    }

    /// The same placement with native values only. Input portable data is not retained and the result has no snapshot.
    public static func intoCompositionNatively(
        _ parent: SculptureComposition,
        inputs: [SculptureInsertionInput],
        at cell: SculptureCell
    ) throws -> SculptureInsertionResult {
        let plan = try compositionPlan(parent, preserving: nil, inputs: inputs, at: cell)
        try SculptureCompositionCodec.validateNativeCapacity(plan.candidate)
        return .init(
            scene: .composition(plan.candidate),
            snapshot: nil,
            placedRootIDs: plan.rootIDs,
            usedNativeFallback: false
        )
    }

    /// Places the first root at the exact focus, then spaces later roots along positive X with a one-cell gap.
    public static func intoWorld(
        _ parent: SculptureWorld,
        preserving snapshot: SculptureThreeMDSnapshot? = nil,
        inputs: [SculptureInsertionInput],
        at focus: SculptureWorldPoint
    ) throws -> SculptureInsertionResult {
        let plan = try worldPlan(parent, preserving: snapshot, inputs: inputs, at: focus)
        return try publish(
            scene: .world(plan.candidate),
            rootIDs: plan.rootIDs,
            parentSnapshot: snapshot,
            inputs: inputs
        ) {
            let previous = try SculptureThreeMDCodec.capture(.world(parent), preserving: snapshot)
            return try portableSnapshot(of: .world(plan.candidate), after: previous, plan: plan, inputs: inputs)
        }
    }

    /// The same placement with native values only. Input portable data is not retained and the result has no snapshot.
    public static func intoWorldNatively(
        _ parent: SculptureWorld,
        inputs: [SculptureInsertionInput],
        at focus: SculptureWorldPoint
    ) throws -> SculptureInsertionResult {
        let plan = try worldPlan(parent, preserving: nil, inputs: inputs, at: focus)
        try SculptureWorldCodec.validateNativeCapacity(plan.candidate)
        return .init(
            scene: .world(plan.candidate),
            snapshot: nil,
            placedRootIDs: plan.rootIDs,
            usedNativeFallback: false
        )
    }

    // MARK: - Planning

    private static func compositionPlan(
        _ parent: SculptureComposition,
        preserving snapshot: SculptureThreeMDSnapshot?,
        inputs: [SculptureInsertionInput],
        at cell: SculptureCell
    ) throws -> NativePlan<SculptureComposition> {
        try Task.checkCancellation()
        guard !inputs.isEmpty else { throw SculptureInsertionError.noInputs }
        guard case .tiles(let map)? = parent.models[parent.rootID], contains(cell, in: map) else {
            throw SculptureInsertionError.invalidSelection
        }
        if let snapshot {
            guard case .composition = snapshot.scene else { throw SculptureInsertionError.mismatchedSnapshot }
        }
        let start = cell.z * map.width * map.height + cell.y * map.width + cell.x
        let remaining = map.width * map.height * map.depth - start
        guard inputs.count <= remaining else {
            throw SculptureInsertionError.insufficientCells(needed: inputs.count, available: remaining)
        }
        let glyphs = availableGlyphs(for: map)
        guard inputs.count <= glyphs.count else {
            throw SculptureInsertionError.noAvailableGlyph(needed: inputs.count, available: glyphs.count)
        }
        try validate(inputs, tileSize: map.tileSize, parentModelCount: parent.models.count)
        let imported = try importing(inputs, into: parent.models, reserved: reservedIDs(snapshot))
        var layers = map.layers
        var bindings = map.bindings
        for (index, rootID) in imported.rootIDs.enumerated() {
            try Task.checkCancellation()
            let position = start + index
            layers[position / (map.width * map.height)][position % (map.width * map.height)] = glyphs[index]
            bindings.append(try .init(glyph: glyphs[index], modelID: rootID))
        }
        let root = try SculptureTileMap(
            width: map.width,
            height: map.height,
            layers: layers,
            tileSize: map.tileSize,
            bindings: bindings
        )
        var models = imported.models
        models[parent.rootID] = .tiles(root)
        let candidate = try SculptureComposition(title: parent.title, rootID: parent.rootID, models: models)
        return .init(candidate: candidate, rootIDs: imported.rootIDs, sources: imported.sources)
    }

    private static func worldPlan(
        _ parent: SculptureWorld,
        preserving snapshot: SculptureThreeMDSnapshot?,
        inputs: [SculptureInsertionInput],
        at focus: SculptureWorldPoint
    ) throws -> NativePlan<SculptureWorld> {
        try Task.checkCancellation()
        guard !inputs.isEmpty else { throw SculptureInsertionError.noInputs }
        guard inputs.count <= SculptureWorld.maximumInstances - parent.instances.count else {
            throw SculptureInsertionError.tooManyPlacements(
                current: parent.instances.count,
                incoming: inputs.count,
                maximum: SculptureWorld.maximumInstances
            )
        }
        if let snapshot {
            guard case .world = snapshot.scene else { throw SculptureInsertionError.mismatchedSnapshot }
        }
        try validate(inputs, tileSize: nil, parentModelCount: parent.library.models.count)
        let imported = try importing(inputs, into: parent.library.models, reserved: reservedIDs(snapshot))
        let library = try SculptureComposition(
            title: parent.library.title,
            rootID: parent.library.rootID,
            models: imported.models
        )
        var instances = parent.instances
        var names = InsertionNames(prefix: "insert-instance", used: Set(instances.map(\.id)))
        var x = focus.x
        for (index, rootID) in imported.rootIDs.enumerated() {
            try Task.checkCancellation()
            instances.append(
                try .init(id: names.next(), modelID: rootID, origin: .init(x: x, y: focus.y, z: focus.z))
            )
            if index + 1 < imported.rootIDs.count {
                guard let model = library.models[rootID] else { throw SculptureCompositionError.unknownModel(rootID) }
                let width: Int
                switch model {
                case .sculpture(let sculpture): width = sculpture.width
                case .tiles(let map): width = map.width * map.tileSize.width
                }
                let addition = x.addingReportingOverflow(Int64(width + 1))
                guard !addition.overflow else { throw SculptureInsertionError.coordinateOverflow }
                x = addition.partialValue
            }
        }
        let candidate = try SculptureWorld(title: parent.title, library: library, instances: instances)
        return .init(candidate: candidate, rootIDs: imported.rootIDs, sources: imported.sources)
    }

    /// Characters available for new bindings, in preference order, excluding the empty character and bound ones.
    internal static func availableGlyphs(for map: SculptureTileMap) -> [UInt8] {
        let used = Set(map.bindings.map(\.glyph))
        let preferred = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)
        return (preferred + (33...126).map(UInt8.init).filter { !preferred.contains($0) })
            .filter { $0 != Sculpture.empty && !used.contains($0) }
    }

    /// Checks every input before any graph is copied: supported kind, snapshot agreement, tile fit and model count.
    private static func validate(
        _ inputs: [SculptureInsertionInput],
        tileSize: SculptureTileSize?,
        parentModelCount: Int
    ) throws {
        var incoming = 0
        for input in inputs {
            try Task.checkCancellation()
            try SculptureInsertionPlan.validate(input, tileSize: tileSize)
            incoming += SculptureInsertionPlan.modelCount(of: input)
        }
        guard incoming <= SculptureComposition.maximumModels - parentModelCount else {
            throw SculptureInsertionError.tooManyModels(
                current: parentModelCount,
                incoming: incoming,
                maximum: SculptureComposition.maximumModels
            )
        }
    }

    private static func contains(_ cell: SculptureCell, in map: SculptureTileMap) -> Bool {
        (0..<map.width).contains(cell.x) && (0..<map.height).contains(cell.y) && (0..<map.depth).contains(cell.z)
    }

    /// Portable entry IDs that generated model IDs must avoid, so portable and native names agree.
    private static func reservedIDs(_ snapshot: SculptureThreeMDSnapshot?) -> Set<String> {
        guard case .composition(let stored)? = snapshot?.storage else { return [] }
        return Set(stored.composition.entries.map(\.id))
    }

    // MARK: - Native graph import

    private static func importing(
        _ inputs: [SculptureInsertionInput],
        into parentModels: [String: SculptureCompositionModel],
        reserved: Set<String>
    ) throws -> ImportedGraphs {
        var names = InsertionNames(prefix: "insert-model", used: Set(parentModels.keys).union(reserved))
        var models = parentModels
        var rootIDs: [String] = []
        var sources: [ImportedSource] = []
        for input in inputs {
            try Task.checkCancellation()
            switch input.scene {
            case .voxels(let sculpture):
                let id = names.next()
                models[id] = .sculpture(sculpture)
                rootIDs.append(id)
                sources.append(.voxel(id))
            case .composition(let composition):
                var mapped: [String: String] = [:]
                for id in composition.models.keys.sorted() { mapped[id] = names.next() }
                for id in composition.models.keys.sorted() {
                    try Task.checkCancellation()
                    guard let model = composition.models[id] else { throw SculptureCompositionError.unknownModel(id) }
                    models[try mappedID(id, in: mapped)] = try remapping(model, with: mapped)
                }
                rootIDs.append(try mappedID(composition.rootID, in: mapped))
                sources.append(.composition(mapped))
            case .world: throw SculptureInsertionError.unsupportedChild
            }
        }
        return .init(models: models, rootIDs: rootIDs, sources: sources)
    }

    private static func mappedID(_ id: String, in mapping: [String: String]) throws -> String {
        guard let result = mapping[id] else { throw SculptureCompositionError.unknownModel(id) }
        return result
    }

    private static func remapping(
        _ model: SculptureCompositionModel,
        with mapping: [String: String]
    ) throws -> SculptureCompositionModel {
        switch model {
        case .sculpture: return model
        case .tiles(let map):
            let bindings = try map.bindings.map {
                try SculptureModelBinding(
                    glyph: $0.glyph,
                    modelID: mappedID($0.modelID, in: mapping),
                    quarterTurns: $0.quarterTurns
                )
            }
            return .tiles(
                try .init(
                    width: map.width,
                    height: map.height,
                    layers: map.layers,
                    tileSize: map.tileSize,
                    bindings: bindings
                )
            )
        }
    }

    // MARK: - Publication

    /// The portable path is attempted first so a refusal can be explained. Its snapshot is returned only when the
    /// parent or an input carried portable data. A portable capacity refusal with no such data falls back to native
    /// values, and one with such data is refused naming the portable limit. Native capacity is checked first in
    /// both cases, so a scene that could not be reopened is never blamed on the portable limit.
    private static func publish(
        scene: SculptureScene,
        rootIDs: [String],
        parentSnapshot: SculptureThreeMDSnapshot?,
        inputs: [SculptureInsertionInput],
        portable: () throws -> SculptureThreeMDSnapshot
    ) throws -> SculptureInsertionResult {
        try Task.checkCancellation()
        let carriers = inputs.filter { $0.snapshot != nil }.map(\.displayName)
        let carriesPortableData = parentSnapshot != nil || !carriers.isEmpty
        do {
            let snapshot = try portable()
            // Every accepted native save must reopen, whatever the portable representation allows.
            try validateNativeCapacity(scene)
            try Task.checkCancellation()
            return .init(
                scene: scene,
                snapshot: carriesPortableData ? snapshot : nil,
                placedRootIDs: rootIDs,
                usedNativeFallback: false
            )
        } catch {
            guard SculptureThreeMDCodec.isCapacityError(error) else { throw error }
            try validateNativeCapacity(scene)
            guard !carriesPortableData else {
                throw SculptureInsertionError.portableLimitExceeded(parent: parentSnapshot != nil, sources: carriers)
            }
            try Task.checkCancellation()
            return .init(scene: scene, snapshot: nil, placedRootIDs: rootIDs, usedNativeFallback: true)
        }
    }

    private static func validateNativeCapacity(_ scene: SculptureScene) throws {
        switch scene {
        case .composition(let composition): try SculptureCompositionCodec.validateNativeCapacity(composition)
        case .world(let world): try SculptureWorldCodec.validateNativeCapacity(world)
        case .voxels: break
        }
    }

    /// Adopts incoming definitions, references and identities under the generated IDs, then captures the candidate.
    private static func portableSnapshot<Candidate>(
        of candidate: SculptureScene,
        after previous: SculptureThreeMDSnapshot,
        plan: NativePlan<Candidate>,
        inputs: [SculptureInsertionInput]
    ) throws -> SculptureThreeMDSnapshot {
        guard case .composition(let stored) = previous.storage else {
            throw SculptureInsertionError.mismatchedSnapshot
        }
        var entries = stored.composition.entries
        for (input, source) in zip(inputs, plan.sources) {
            try Task.checkCancellation()
            let portable = try SculptureThreeMDCodec.capture(input.scene, preserving: input.snapshot)
            switch (source, portable.storage) {
            case (.voxel(let id), .document(let document)):
                entries.append(.init(id: id, document: document.document))
            case (.composition(let mapped), .composition(let imported)):
                for entry in imported.composition.entries {
                    try Task.checkCancellation()
                    let references = try entry.references.map {
                        try DocumentReference(targetID: mappedID($0.targetID, in: mapped), attributes: $0.attributes)
                    }
                    entries.append(
                        .init(id: try mappedID(entry.id, in: mapped), document: entry.document, references: references)
                    )
                }
            default: throw SculptureInsertionError.mismatchedSnapshot
            }
        }
        let graph = try DocumentComposition(
            rootID: stored.composition.rootID,
            entries: entries,
            limits: SculptureThreeMDPolicy.composition(),
            documentLimits: SculptureThreeMDPolicy.document()
        )
        let preservation = try SculptureThreeMDCodec.makeSnapshot(scene: previous.scene, graph: graph)
        try Task.checkCancellation()
        let snapshot = try SculptureThreeMDCodec.capture(candidate, preserving: preservation)
        // Insertion preserves a complete portable snapshot; its canonical encoding must fit the portable limits.
        _ = try SculptureThreeMDCodec.encode(snapshot)
        try Task.checkCancellation()
        return snapshot
    }
}

private struct NativePlan<Candidate> {
    let candidate: Candidate
    let rootIDs: [String]
    let sources: [ImportedSource]
}

private enum ImportedSource {
    case voxel(String)
    case composition([String: String])
}

private struct ImportedGraphs {
    let models: [String: SculptureCompositionModel]
    let rootIDs: [String]
    let sources: [ImportedSource]
}

private struct InsertionNames {
    let prefix: String
    var used: Set<String>
    private var suffix = 1

    init(prefix: String, used: Set<String>) { self.prefix = prefix; self.used = used }

    mutating func next() -> String {
        while true {
            let id = "\(prefix)-\(suffix)"
            suffix += 1
            if used.insert(id).inserted { return id }
        }
    }
}
