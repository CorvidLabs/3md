import Foundation
import RookSculpture

/// Orbit frames the editing focus; Explore travels through the same sparse world.
public enum SculptureWorldNavigationMode: String, CaseIterable, Sendable, Equatable {
    case orbit
    case explore
}

public enum SculptureWorldNavigationError: Error, LocalizedError, Equatable, Sendable {
    case invalidMovement
    case coordinateOverflow

    public var errorDescription: String? {
        switch self {
        case .invalidMovement: "Use finite camera coordinates, movement speed and elapsed time."
        case .coordinateOverflow: "The exploration camera has reached the signed 64-bit world boundary."
        }
    }
}

/// An exact integer anchor plus a small local eye offset preserves adjacent cells beyond 2^53.
/// Document Y grows down. Positive pitch looks up; yaw zero looks toward negative Z.
public struct SculptureWorldExplorer: Sendable, Equatable {
    public static let rebaseDistance = 64.0
    public static let defaultSpeed = 48.0
    public private(set) var anchor: SculptureWorldPoint
    public private(set) var offset: SIMD3<Double>
    public private(set) var yaw: Double
    public private(set) var pitch: Double

    public init(anchor: SculptureWorldPoint, yaw: Double = 0, pitch: Double = 0) {
        self.anchor = anchor
        offset = .zero
        self.yaw = Self.normalizedYaw(yaw)
        self.pitch = Self.clampedPitch(pitch)
    }

    /// Large offsets are rebased with checked integer arithmetic, never by converting the anchor to Double.
    public init(
        anchor: SculptureWorldPoint,
        offset: SIMD3<Double>,
        yaw: Double = 0,
        pitch: Double = 0
    ) throws {
        guard offset.x.isFinite, offset.y.isFinite, offset.z.isFinite, yaw.isFinite, pitch.isFinite else {
            throw SculptureWorldNavigationError.invalidMovement
        }
        let x = try Self.component(anchor: anchor.x, offset: offset.x)
        let y = try Self.component(anchor: anchor.y, offset: offset.y)
        let z = try Self.component(anchor: anchor.z, offset: offset.z)
        self.anchor = .init(x: x.anchor, y: y.anchor, z: z.anchor)
        self.offset = SIMD3(x.offset, y.offset, z.offset)
        self.yaw = Self.normalizedYaw(yaw)
        self.pitch = Self.clampedPitch(pitch)
    }

    /// Movement is yaw-relative and horizontal; positive vertical travels up independently of pitch.
    /// Simultaneous axes are normalized so diagonals do not travel faster. Failed moves leave this value intact.
    public mutating func move(
        forward: Double,
        right: Double,
        vertical: Double,
        speed: Double = Self.defaultSpeed,
        duration: Double
    ) throws {
        guard forward.isFinite, right.isFinite, vertical.isFinite,
            speed.isFinite, speed >= 0, duration.isFinite, duration >= 0
        else { throw SculptureWorldNavigationError.invalidMovement }
        let axes = SIMD3(
            max(-1, min(1, right)),
            max(-1, min(1, vertical)),
            max(-1, min(1, forward))
        )
        let length = sqrt(axes.x * axes.x + axes.y * axes.y + axes.z * axes.z)
        guard length > 0, speed > 0, duration > 0 else { return }
        let distance = speed * duration / length
        guard distance.isFinite else { throw SculptureWorldNavigationError.invalidMovement }
        let displacement = SIMD3(
            (axes.x * cos(yaw) - axes.z * sin(yaw)) * distance,
            -axes.y * distance,
            (-axes.x * sin(yaw) - axes.z * cos(yaw)) * distance
        )
        self = try Self(anchor: anchor, offset: offset + displacement, yaw: yaw, pitch: pitch)
    }

    /// Radian deltas are bounded to a stable yaw and an upright, non-inverting pitch.
    public mutating func look(horizontal: Double, vertical: Double) {
        guard horizontal.isFinite, vertical.isFinite else { return }
        yaw = Self.normalizedYaw(yaw + horizontal)
        pitch = Self.clampedPitch(pitch + vertical)
    }

    private static func component(anchor: Int64, offset: Double) throws -> (anchor: Int64, offset: Double) {
        guard let whole = Int64(exactly: offset.rounded(.towardZero)) else {
            throw SculptureWorldNavigationError.coordinateOverflow
        }
        let addition = anchor.addingReportingOverflow(whole)
        let fraction = offset - Double(whole)
        guard !addition.overflow,
            !(addition.partialValue == Int64.max && fraction > 0),
            !(addition.partialValue == Int64.min && fraction < 0)
        else { throw SculptureWorldNavigationError.coordinateOverflow }
        return abs(offset) >= rebaseDistance
            ? (addition.partialValue, fraction) : (anchor, offset)
    }

    private static func normalizedYaw(_ value: Double) -> Double {
        value.isFinite ? value.truncatingRemainder(dividingBy: 2 * .pi) : 0
    }

    private static func clampedPitch(_ value: Double) -> Double {
        value.isFinite ? max(-1.48, min(1.48, value)) : 0
    }
}
