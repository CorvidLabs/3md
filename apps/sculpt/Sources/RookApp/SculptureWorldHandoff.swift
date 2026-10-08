import Foundation
import RookSculpture

/// A one-instance world built from a composition, carrying the composition's portable identities and metadata.
internal struct SculptureWorldHandoff: Sendable {
    let world: SculptureWorld
    /// Nil when the composition had no portable data, or when the world exceeds portable ThreeMD capacity.
    let snapshot: SculptureThreeMDSnapshot?
    let notice: String?

    /// Captures the world away from the main actor so entry metadata, references and nested titles survive.
    static func prepare(composition: SculptureComposition, snapshot: SculptureThreeMDSnapshot?) async throws -> Self {
        let instance = try SculptureWorldInstance(
            id: "instance-1",
            modelID: composition.rootID,
            origin: SculptureWorldPoint(x: 0, y: 0, z: 0)
        )
        let world = try SculptureWorld(title: composition.title, library: composition, instances: [instance])
        guard let snapshot else { return Self(world: world, snapshot: nil, notice: nil) }
        let worker = Task.detached(priority: .userInitiated) { () throws -> SculptureThreeMDSnapshot? in
            do {
                return try SculptureThreeMDCodec.capture(.world(world), preserving: snapshot)
            } catch {
                guard SculptureThreeMDCodec.isCapacityError(error) else { throw error }
                return nil
            }
        }
        let captured = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        return Self(
            world: world,
            snapshot: captured,
            notice: captured == nil
                ? "Opened without portable ThreeMD data because this world exceeds portable capacity." : nil
        )
    }
}
