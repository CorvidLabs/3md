import Foundation
import RookRendering
import RookSculpture

/// Camera-independent cube geometry for one sculpture, prepared away from the main actor.
internal struct SculpturePreparedGeometry: Sendable {
    internal let scene: SculptureVoxelScene
    internal let mesh: SculptureVoxelMeshBuffers

    /// Extracts the exterior faces and native mesh bytes. Cancellation and the face budget both throw.
    /// - Parameter sculpture: The volume the canvas will show.
    /// - Returns: Geometry that matches `sculpture` exactly.
    internal static func prepare(_ sculpture: Sculpture) throws -> Self {
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        return Self(scene: scene, mesh: try SculptureVoxelMeshBuffers.prepare(scene))
    }

    /// Whether this geometry was extracted from a volume of these dimensions.
    internal func matches(_ sculpture: Sculpture) -> Bool {
        scene.width == sculpture.width && scene.height == sculpture.height && scene.depth == sculpture.depth
            && scene.occupiedCount == sculpture.occupiedCount
    }
}

/// A gallery entry generated and prepared for the editor that opens it. Nothing here is published until the whole
/// load finishes, so a cancelled load leaves no trace.
internal enum SculptureGalleryOpened: Sendable {
    /// A voxel model with its cube geometry, or nil when the canvas should report its own geometry limit.
    case model(SculptureGalleryEntry, Sculpture, SculpturePreparedGeometry?)
    /// A composition with its assembled preview, or nil when expansion failed for a reason the editor reports.
    case composition(SculptureGalleryEntry, SculptureComposition, preview: Sculpture?)
    /// A sparse world with its shared model geometry, or nil when the world editor should report the failure.
    case world(SculptureGalleryEntry, SculptureWorld, SculptureWorldScene?)

    /// The entry this value was generated from.
    internal var entry: SculptureGalleryEntry {
        switch self {
        case .model(let entry, _, _), .composition(let entry, _, _), .world(let entry, _, _): entry
        }
    }

    /// Prepares what the opening editor shows first. Call on a worker. Cancellation throws; any other preparation
    /// failure opens the scene without prepared geometry, so the editor reports it exactly as it does today.
    /// - Parameters:
    ///   - entry: The listed entry.
    ///   - scene: The scene its factory created.
    /// - Returns: The scene with the geometry its editor needs.
    internal static func prepare(_ entry: SculptureGalleryEntry, scene: SculptureScene) throws -> Self {
        try Task.checkCancellation()
        let opened: Self
        switch scene {
        case .voxels(let sculpture):
            opened = .model(entry, sculpture, try optional { try SculpturePreparedGeometry.prepare(sculpture) })
        case .composition(let composition):
            opened = .composition(entry, composition, preview: try optional { try composition.expanded() })
        case .world(let world):
            opened = .world(entry, world, try optional { try SculptureWorldScene.prepare(world) })
        }
        try Task.checkCancellation()
        return opened
    }


    // MARK: - Private Methods

    private static func optional<Value>(_ work: () throws -> Value) throws -> Value? {
        do {
            return try work()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }
}

/// Where a finished gallery load goes. A model replaces the main document through the window's dirty-work
/// confirmation; a composition or a world opens as a new, unmodified draft in its own editor sheet.
@MainActor
internal enum SculptureGalleryDestination {
    case document(SculptureGalleryEntry, Sculpture, SculpturePreparedGeometry?)
    case composition(SculptureCompositionDraft)
    case world(SculptureWorldDraft)

    /// Builds the destination for a finished load, handing prepared geometry to the draft that shows it.
    internal init(_ opened: SculptureGalleryOpened) {
        switch opened {
        case .model(let entry, let sculpture, let geometry):
            self = .document(entry, sculpture, geometry)
        case .composition(_, let composition, let preview):
            let draft = SculptureCompositionDraft(composition: composition)
            if let preview { draft.adoptPreview(preview) }
            self = .composition(draft)
        case .world(_, let world, let scene):
            let draft = SculptureWorldDraft(world: world)
            if let scene { draft.adoptPreparedScene(scene) }
            self = .world(draft)
        }
    }
}
