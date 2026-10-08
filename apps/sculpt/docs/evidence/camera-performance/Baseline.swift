import Foundation
import RookRendering
import RookSculpture

struct Sample: Codable {
    let yaw: Double
    let faces: Int
    let projectionMilliseconds: Double
    let rasterMilliseconds: Double
}
func milliseconds(_ start: ContinuousClock.Instant) -> Double {
    let elapsed = start.duration(to: .now).components
    return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
}
let input = URL(fileURLWithPath: "/Users/leif/Development/_CorvidLabs/rook/Examples/grand-solar-system.3mdb")
let solar = try SculptureDocumentCodec.decode(Data(contentsOf: input))
var samples: [Sample] = []
for yaw in [0.65, 0.85, 1.05] {
    let start = ContinuousClock.now
    let frame = SculptureVoxelProjection.frame(
        solar,
        camera: SculptureCamera(yaw: yaw, pitch: 0.7, zoom: 0.9),
        width: 1100,
        height: 700,
        selectedLayer: 128,
        showsEmptyCells: false
    )
    let projection = milliseconds(start)
    let rasterStart = ContinuousClock.now
    guard SculptureVoxelRasterizer.image(frame, opacity: 0.35, selectedLayer: 128) != nil else {
        fatalError("Raster failed")
    }
    samples.append(
        Sample(
            yaw: yaw,
            faces: frame.quads.count,
            projectionMilliseconds: projection,
            rasterMilliseconds: milliseconds(rasterStart)
        )
    )
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(samples))
