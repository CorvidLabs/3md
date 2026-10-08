import Foundation
import RookSculpture
import Testing

@testable import RookRendering

struct SculptureWorldNavigationTests {
    @Test func smallMovesRetainExactAnchorsBeyondDoubleIntegerPrecision() throws {
        let large: Int64 = 9_007_199_254_741_999
        var explorer = SculptureWorldExplorer(anchor: .init(x: large, y: -large, z: large))
        try explorer.move(forward: 0, right: 1, vertical: 0, speed: 1, duration: 1)
        #expect(explorer.anchor == .init(x: large, y: -large, z: large))
        #expect(explorer.offset == SIMD3(1, 0, 0))
        try explorer.move(forward: 0, right: 1, vertical: 0, speed: 1, duration: 1)
        #expect(explorer.offset.x == 2)
    }

    @Test func positiveAndNegativeRebasesPreserveFractionalEyeOffsetsExactly() throws {
        let large: Int64 = 9_007_199_254_741_999
        let positive = try SculptureWorldExplorer(
            anchor: .init(x: large, y: 0, z: -large),
            offset: SIMD3(64.25, -65.5, 63.75)
        )
        #expect(positive.anchor == .init(x: large + 64, y: -65, z: -large))
        #expect(positive.offset == SIMD3(0.25, -0.5, 63.75))
        let negative = try SculptureWorldExplorer(anchor: .init(x: large, y: 0, z: 0), offset: SIMD3(-64.25, 0, 0))
        #expect(negative.anchor.x == large - 64)
        #expect(negative.offset.x == -0.25)
    }

    @Test func diagonalsAndVerticalTravelUseTheSameCellsPerSecondSpeed() throws {
        let origin = SculptureWorldPoint(x: 0, y: 0, z: 0)
        var straight = SculptureWorldExplorer(anchor: origin)
        var diagonal = SculptureWorldExplorer(anchor: origin)
        try straight.move(forward: 1, right: 0, vertical: 0, speed: 12, duration: 0.5)
        try diagonal.move(forward: 1, right: 1, vertical: 1, speed: 12, duration: 0.5)
        #expect(straight.offset == SIMD3(0, 0, -6))
        let squared =
            diagonal.offset.x * diagonal.offset.x + diagonal.offset.y * diagonal.offset.y
            + diagonal.offset.z * diagonal.offset.z
        #expect(abs(squared - 36) < 1e-10)
        #expect(diagonal.offset.x > 0 && diagonal.offset.y < 0 && diagonal.offset.z < 0)
    }

    @Test func yawRotatesFlatMovementWhilePitchOnlyChangesLook() throws {
        let origin = SculptureWorldPoint(x: 0, y: 0, z: 0)
        var explorer = SculptureWorldExplorer(anchor: origin, yaw: .pi / 2, pitch: 1)
        try explorer.move(forward: 1, right: 0, vertical: 0, speed: 10, duration: 1)
        #expect(abs(explorer.offset.x + 10) < 1e-10)
        #expect(explorer.offset.y == 0 && abs(explorer.offset.z) < 1e-10)
        try explorer.move(forward: 0, right: 1, vertical: 0, speed: 10, duration: 1)
        #expect(abs(explorer.offset.x + 10) < 1e-10 && abs(explorer.offset.z + 10) < 1e-10)
        try explorer.move(forward: 0, right: 0, vertical: -1, speed: 10, duration: 1)
        #expect(explorer.offset.y == 10)
    }

    @Test func elapsedTimeAndFastSpeedAreIndependentOfEventRepeatFrequency() throws {
        let origin = SculptureWorldPoint(x: 0, y: 0, z: 0)
        var oneStep = SculptureWorldExplorer(anchor: origin)
        var manySteps = SculptureWorldExplorer(anchor: origin)
        try oneStep.move(forward: 0, right: 1, vertical: 0, speed: 48, duration: 0.5)
        for _ in 0..<10 {
            try manySteps.move(forward: 0, right: 1, vertical: 0, speed: 48, duration: 0.05)
        }
        #expect(abs(oneStep.offset.x - manySteps.offset.x) < 1e-10)
        var fast = SculptureWorldExplorer(anchor: origin)
        try fast.move(forward: 0, right: 1, vertical: 0, speed: 192, duration: 0.25)
        #expect(fast.offset.x == 48)
    }

    @Test func checkedBoundariesRejectOverflowBeforeRebaseAndLeaveMovementAtomic() throws {
        var explorer = SculptureWorldExplorer(anchor: .init(x: Int64.max - 1, y: 0, z: 0))
        let original = explorer
        #expect(throws: SculptureWorldNavigationError.coordinateOverflow) {
            try explorer.move(forward: 0, right: 1, vertical: 0, speed: 2, duration: 1)
        }
        #expect(explorer == original)
        #expect(throws: SculptureWorldNavigationError.coordinateOverflow) {
            try SculptureWorldExplorer(anchor: .init(x: Int64.min, y: 0, z: 0), offset: SIMD3(-0.5, 0, 0))
        }
        #expect(throws: SculptureWorldNavigationError.coordinateOverflow) {
            try SculptureWorldExplorer(anchor: .init(x: 0, y: 0, z: 0), offset: SIMD3(Double(Int64.max), 0, 0))
        }
    }

    @Test func invalidMovementFailsWithoutMutatingAndLookNeverInverts() throws {
        var explorer = SculptureWorldExplorer(anchor: .init(x: 1, y: 2, z: 3))
        let original = explorer
        #expect(throws: SculptureWorldNavigationError.invalidMovement) {
            try explorer.move(forward: .nan, right: 0, vertical: 0, duration: 1)
        }
        #expect(explorer == original)
        #expect(throws: SculptureWorldNavigationError.invalidMovement) {
            try explorer.move(forward: 1, right: 0, vertical: 0, speed: 1, duration: -1)
        }
        explorer.look(horizontal: 20 * .pi, vertical: 100)
        #expect(abs(explorer.yaw) < 1e-10 && explorer.pitch == 1.48)
        explorer.look(horizontal: .infinity, vertical: .nan)
        #expect(explorer.pitch == 1.48 && explorer.anchor == original.anchor)
    }
}
