import Foundation
import RookSculpture
import Testing

#if canImport(ModelIO)
import ModelIO
#endif

@Test func singleVoxelOBJHasClosedOutwardSurfaceAndCenteredBounds() throws {
    let sculpture = try Sculpture(title: "Cube", width: 1, height: 1, layers: [[35]])
    let mesh = try ParsedOBJ(SculptureOBJExporter.data(for: sculpture))
    #expect(mesh.vertices.count == 8)
    #expect(mesh.faces.count == 6)
    #expect(mesh.vertices.allSatisfy { abs($0.x) == 0.5 && abs($0.y) == 0.5 && abs($0.z) == 0.5 })
    #expect(abs(mesh.signedVolume - 1) < 0.000_001)
    try mesh.verifyWindingAndIndices()
}

@Test func neighboringGlyphsShareVerticesAndOmitTheirInternalFaces() throws {
    let sculpture = try Sculpture(title: "Neighbors", width: 2, height: 1, layers: [[35, 64]])
    let data = try SculptureOBJExporter.data(for: sculpture)
    let mesh = try ParsedOBJ(data)
    #expect(mesh.vertices.count == 12)
    #expect(mesh.faces.count == 10)
    #expect(abs(mesh.signedVolume - 2) < 0.000_001)
    #expect(!mesh.faces.contains { face in face.indices.allSatisfy { mesh.vertices[$0].x == 0 } })
    #expect(String(decoding: data, as: UTF8.self).contains("g glyph_35\n"))
    #expect(String(decoding: data, as: UTF8.self).contains("g glyph_64\n"))
    try mesh.verifyWindingAndIndices()
}

@Test func hollowVoxelMeshPreservesTheInteriorSurface() throws {
    var layers = Array(repeating: Array(repeating: UInt8(35), count: 9), count: 3)
    layers[1][4] = Sculpture.empty
    let sculpture = try Sculpture(title: "Hollow cube", width: 3, height: 3, layers: layers)
    let mesh = try ParsedOBJ(SculptureOBJExporter.data(for: sculpture))
    #expect(mesh.faces.count == 60)
    #expect(abs(mesh.signedVolume - 26) < 0.000_001)
    try mesh.verifyWindingAndIndices()
}

@Test func emptyOBJContainsNoInventedGeometry() throws {
    let mesh = try ParsedOBJ(SculptureOBJExporter.data(for: .blank()))
    #expect(mesh.vertices.isEmpty)
    #expect(mesh.faces.isEmpty)
}

@Test func orbOBJIsClosedAndCanBeRetainedAsExportEvidence() throws {
    let sculpture = Sculpture.orb()
    let data = try SculptureOBJExporter.data(for: sculpture)
    let mesh = try ParsedOBJ(data)
    #expect(abs(mesh.signedVolume - Double(sculpture.occupiedCount)) < 0.000_001)
    try mesh.verifyWindingAndIndices()
    let evidence = ProcessInfo.processInfo.environment["ROOK_EXPORT_EVIDENCE_DIR"]
    let root = evidence.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
    let folder = root.appendingPathComponent("obj-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        if evidence == nil { try? FileManager.default.removeItem(at: folder) }
    }
    let file = folder.appendingPathComponent("character-orb.obj")
    try data.write(to: file, options: .atomic)
    #if canImport(ModelIO)
    #expect(MDLAsset.canImportFileExtension("obj"))
    let asset = MDLAsset(url: file)
    let meshes = asset.childObjects(of: MDLMesh.self).compactMap { $0 as? MDLMesh }
    #expect(!meshes.isEmpty)
    #expect(meshes.allSatisfy { $0.vertexCount > 0 })
    let submeshes = meshes.flatMap { $0.submeshes as? [MDLSubmesh] ?? [] }
    #expect(submeshes.allSatisfy { $0.geometryType == .triangles })
    #expect(submeshes.reduce(0) { $0 + $1.indexCount } == mesh.faces.count * 6)
    #expect(asset.boundingBox.minBounds == SIMD3<Float>(repeating: -7))
    #expect(asset.boundingBox.maxBounds == SIMD3<Float>(repeating: 7))
    #endif
}

@Test func sixtyFourSolidVolumeExportsItsSurfaceRatherThanEveryCube() throws {
    let sculpture = try Sculpture(
        title: "64 solid cube",
        width: 64,
        height: 64,
        layers: Array(repeating: Array(repeating: UInt8(35), count: 4096), count: 64)
    )
    let mesh = try ParsedOBJ(SculptureOBJExporter.data(for: sculpture))
    #expect(mesh.faces.count == 6 * 64 * 64)
    #expect(mesh.vertices.count == 6 * 64 * 64 + 2)
    #expect(abs(mesh.signedVolume - 262_144) < 0.000_001)
    try mesh.verifyWindingAndIndices()
}

@Test func highCoordinatesExportAClosedSurfaceWithCorrectCenteredBounds() throws {
    var sculpture = try Sculpture(
        title: "Far voxel",
        width: 256,
        height: 1,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: 256), count: 256)
    )
    sculpture.paint(SculptureCell(x: 255, y: 0, z: 255), glyph: 35)
    let mesh = try ParsedOBJ(SculptureOBJExporter.data(for: sculpture))
    #expect(mesh.vertices.count == 8)
    #expect(mesh.faces.count == 6)
    #expect(
        mesh.vertices.allSatisfy {
            (127.0...128.0).contains($0.x) && abs($0.y) == 0.5 && (127.0...128.0).contains($0.z)
        }
    )
    #expect(abs(mesh.signedVolume - 1) < 0.000_001)
    try mesh.verifyWindingAndIndices()
}

@Test func isolatedCubeVolumeFailsBeforeAllocatingAnUnboundedMesh() throws {
    var layers = Array(repeating: Array(repeating: Sculpture.empty, count: 4096), count: 64)
    for z in 0..<64 {
        for y in 0..<64 {
            for x in 0..<64 where (x + y + z).isMultiple(of: 2) { layers[z][y * 64 + x] = 35 }
        }
    }
    let volume = try Sculpture(title: "Checkerboard", width: 64, height: 64, layers: layers)
    #expect(throws: SculptureOBJExportError.tooManyFaces) { try SculptureOBJExporter.data(for: volume) }
    #expect(volume.occupiedCount == 131_072)
}

@Test func cancelledOBJExportDoesNotReturnAPartialMesh() async throws {
    let barrier = OBJCancellationBarrier()
    let operation = Task {
        await barrier.wait()
        return try SculptureOBJExporter.data(for: .orb())
    }
    operation.cancel()
    await barrier.release()
    await #expect(throws: CancellationError.self) { try await operation.value }
}

private actor OBJCancellationBarrier {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}

private struct ParsedOBJ {
    struct Face {
        let indices: [Int]
        let normal: Int
    }

    let vertices: [SIMD3<Double>]
    let normals: [SIMD3<Double>]
    let faces: [Face]

    init(_ data: Data) throws {
        var vertices: [SIMD3<Double>] = []
        var normals: [SIMD3<Double>] = []
        var faces: [Face] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: " ")
            switch fields.first {
            case "v", "vn":
                let coordinates = try fields.dropFirst().map { try #require(Double($0)) }
                #expect(coordinates.count == 3)
                let point = SIMD3(coordinates[0], coordinates[1], coordinates[2])
                if fields.first == "v" { vertices.append(point) } else { normals.append(point) }
            case "f":
                let values = try fields.dropFirst().map { field in
                    let parts = field.split(separator: "/", omittingEmptySubsequences: false)
                    #expect(parts.count == 3)
                    return (try #require(Int(parts[0])) - 1, try #require(Int(parts[2])) - 1)
                }
                #expect(values.count == 4)
                let normal = try #require(values.first?.1)
                #expect(values.allSatisfy { $0.1 == normal })
                faces.append(Face(indices: values.map(\.0), normal: normal))
            default: break
            }
        }
        self.vertices = vertices
        self.normals = normals
        self.faces = faces
    }

    var signedVolume: Double {
        faces.reduce(0) { total, face in
            let points = face.indices.map { vertices[$0] }
            return total + dot(points[0], cross(points[1], points[2])) / 6
                + dot(points[0], cross(points[2], points[3])) / 6
        }
    }

    func verifyWindingAndIndices() throws {
        for face in faces {
            let indicesValid = face.indices.allSatisfy { vertices.indices.contains($0) }
            #expect(indicesValid)
            #expect(normals.indices.contains(face.normal))
            guard indicesValid, normals.indices.contains(face.normal) else { continue }
            let points = face.indices.map { vertices[$0] }
            let normal = cross(points[1] - points[0], points[2] - points[0])
            #expect(dot(normal, normals[face.normal]) > 0)
            #expect(abs(dot(points[3] - points[0], normal)) < 0.000_001)
        }
    }
}

private func cross(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(lhs.y * rhs.z - lhs.z * rhs.y, lhs.z * rhs.x - lhs.x * rhs.z, lhs.x * rhs.y - lhs.y * rhs.x)
}

private func dot(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
    lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
}
