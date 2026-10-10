import Foundation
import RookSculpture
import Testing
import simd

@testable import RookRendering

@MainActor
struct CameraParityTests {
    @Test func nativeCameraMatchesSharedBrowserProjectionCases() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let fixture = try JSONDecoder().decode(
            CameraFixture.self,
            from: Data(contentsOf: root.appendingPathComponent("docs/evidence/viewer-camera/camera-parity.json"))
        )
        let dimensions = SIMD3(fixture.dimensions[0], fixture.dimensions[1], fixture.dimensions[2])
        let size = CGSize(width: fixture.viewport[0], height: fixture.viewport[1])
        for pose in fixture.cases {
            let camera = SculptureCamera(
                yaw: pose.yaw,
                pitch: pose.pitch,
                zoom: pose.zoom,
                panX: pose.panX,
                panY: pose.panY,
                fitsVolume: true
            )
            let transform = LiveVoxelCamera(dimensions: dimensions, camera: camera, size: size)
            for (column, expected) in [pose.right, pose.up, pose.back].enumerated() {
                for axis in 0..<3 {
                    #expect(abs(Double(transform.cameraToWorld[column][axis]) - expected[axis]) < 0.000_01)
                }
            }
            for (index, cell) in fixture.cells.enumerated() {
                let point = SIMD4<Float>(
                    Float(cell.x) - Float(dimensions.x - 1) / 2,
                    Float(dimensions.y - 1) / 2 - Float(cell.y),
                    Float(cell.z) - Float(dimensions.z - 1) / 2,
                    1
                )
                let clip = transform.projection * simd_inverse(transform.cameraToWorld) * point
                let x = (Double(clip.x / clip.w) + 1) * Double(fixture.viewport[0]) / 2
                let y = (1 - Double(clip.y / clip.w)) * Double(fixture.viewport[1]) / 2
                #expect(abs(x - pose.projected[index][0]) < 0.001)
                #expect(abs(y - pose.projected[index][1]) < 0.001)
            }
        }
    }

    @Test func interactiveFramingPreservesDefaultExportCameraScale() {
        let dimensions = SIMD3(16, 16, 16)
        let legacy = SculptureCamera()
        let fitted = SculptureCamera(fitsVolume: true)
        let scale = 576.0 * 0.68 / 16
        #expect(abs(legacy.projectionScale(dimensions: dimensions, width: 576, height: 648) - scale) < 0.000_001)
        #expect(fitted.projectionScale(dimensions: dimensions, width: 576, height: 648) < scale)
        #expect(fitted.normalized.fitsVolume)
    }

    @Test func cameraInputsRemainFiniteAndPanHasTheNativeScreenScale() {
        let invalid = SculptureCamera(yaw: .nan, pitch: .infinity, zoom: -.infinity, panX: .nan, panY: .infinity)
        #expect(invalid.normalized == SculptureCamera(yaw: 0, pitch: 0))
        var camera = SculptureCamera(yaw: 0, pitch: 0)
        camera.orbit(horizontal: 2 * .pi / 0.008, vertical: 2 * .pi / 0.008)
        #expect(abs(camera.yaw) < 0.000_001 && abs(camera.pitch) < 0.000_001)
        camera.pan(horizontal: 34, vertical: 68, extent: 9, width: 400, height: 320)
        #expect(abs(camera.panX + 34 / (320 * 0.68 / 9)) < 0.000_001)
        #expect(abs(camera.panY - 68 / (320 * 0.68 / 9)) < 0.000_001)
        camera.magnify(100)
        #expect(camera.zoom == 2)
        camera.magnify(0.001)
        #expect(camera.zoom == 0.5)
        let previous = camera
        camera.orbit(horizontal: .infinity, vertical: 0)
        camera.pan(horizontal: 1, vertical: 1, extent: 9, width: 0, height: 320)
        camera.magnify(.nan)
        #expect(camera == previous)
    }
}

private struct CameraFixture: Decodable {
    let dimensions: [Int]
    let viewport: [Int]
    let cells: [FixtureCell]
    let cases: [FixturePose]
}

private struct FixtureCell: Decodable {
    let x: Int
    let y: Int
    let z: Int
}

private struct FixturePose: Decodable {
    let yaw: Double
    let pitch: Double
    let zoom: Double
    let panX: Double
    let panY: Double
    let right: [Double]
    let up: [Double]
    let back: [Double]
    let projected: [[Double]]
}
