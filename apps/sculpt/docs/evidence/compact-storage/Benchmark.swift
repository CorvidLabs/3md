import Foundation
import RookSculpture

struct Measurement: Codable {
    let name: String
    let width: Int
    let height: Int
    let depth: Int
    let occupiedCells: Int
    let readableBytes: Int
    let compactBytes: Int
    let readableEncodeMedianMilliseconds: Double
    let compactEncodeMedianMilliseconds: Double
    let readableDecodeMedianMilliseconds: Double
    let compactDecodeMedianMilliseconds: Double
}

func medianMilliseconds(_ body: () throws -> Void) throws -> Double {
    var measurements: [Double] = []
    for _ in 0..<5 {
        let start = ContinuousClock.now
        try body()
        let elapsed = start.duration(to: .now).components
        measurements.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
    }
    return measurements.sorted()[2]
}

let root = URL(fileURLWithPath: "/Users/leif/Development/_CorvidLabs/rook")
let solar = try SculptureCodec.decode(Data(contentsOf: root.appendingPathComponent("Examples/grand-solar-system.3md")))
let emptyLayer = [UInt8](repeating: Sculpture.empty, count: 256 * 256)
let denseLayer = [UInt8](repeating: 35, count: 256 * 256)
let empty = try Sculpture(title: "Empty 256", width: 256, height: 256, layers: Array(repeating: emptyLayer, count: 256))
let dense = try Sculpture(title: "Dense 256", width: 256, height: 256, layers: Array(repeating: denseLayer, count: 256))
var state: UInt64 = 0x1234ABCD
let alphabet = Sculpture.palette + [Sculpture.empty]
let mixedLayers = (0..<256).map { _ in
    (0..<(256 * 256)).map { _ -> UInt8 in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return alphabet[Int((state >> 32) % UInt64(alphabet.count))]
    }
}
let mixed = try Sculpture(title: "Mixed 256", width: 256, height: 256, layers: mixedLayers)
var results: [Measurement] = []
for (name, sculpture) in [("Orb", Sculpture.orb()), ("Grand solar system", solar), ("Empty 256", empty), ("Dense 256", dense), ("Mixed 256", mixed)] {
    let readable = SculptureCodec.encode(sculpture)
    let compact = try SculptureBinaryCodec.encode(sculpture)
    guard try SculptureDocumentCodec.decode(readable) == sculpture,
        try SculptureDocumentCodec.decode(compact) == sculpture
    else { fatalError("Round-trip mismatch") }
    if name == "Grand solar system" {
        try compact.write(to: root.appendingPathComponent("Examples/grand-solar-system.3mdb"), options: .atomic)
    }
    results.append(try Measurement(
        name: name, width: sculpture.width, height: sculpture.height, depth: sculpture.depth,
        occupiedCells: sculpture.occupiedCount, readableBytes: readable.count, compactBytes: compact.count,
        readableEncodeMedianMilliseconds: medianMilliseconds { _ = SculptureCodec.encode(sculpture) },
        compactEncodeMedianMilliseconds: medianMilliseconds { _ = try SculptureBinaryCodec.encode(sculpture) },
        readableDecodeMedianMilliseconds: medianMilliseconds { _ = try SculptureCodec.decode(readable) },
        compactDecodeMedianMilliseconds: medianMilliseconds { _ = try SculptureBinaryCodec.decode(compact) }
    ))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(results)
let folder = root.appendingPathComponent("docs/evidence/compact-storage")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try data.write(to: folder.appendingPathComponent("benchmark.json"), options: .atomic)
FileHandle.standardOutput.write(data)
