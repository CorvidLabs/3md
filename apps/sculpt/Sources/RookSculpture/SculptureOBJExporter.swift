import Foundation

public enum SculptureOBJExportError: Error, LocalizedError, Equatable, Sendable {
    case tooManyFaces
    public var errorDescription: String? {
        "This model exceeds the OBJ limit of 250,000 exterior faces. Reduce isolated cubes or export a PNG, GIF, or video instead."
    }
}

/// Exports occupied cells as a centered, right-handed voxel surface mesh.
/// Glyphs become OBJ groups; this format contains geometry rather than typographic glyph outlines.
public enum SculptureOBJExporter {
    public static let maximumFaces = 250_000

    public static func data(for sculpture: Sculpture) throws -> Data {
        // Count surfaces before allocating mesh arrays. Sparse checkerboards can have
        // far more geometry than a solid volume with the same dimensions.
        var faceCount = 0
        for z in 0..<sculpture.depth {
            try Task.checkCancellation()
            for y in 0..<sculpture.height {
                for x in 0..<sculpture.width where sculpture.layers[z][y * sculpture.width + x] != Sculpture.empty {
                    for surface in Surface.all {
                        let neighbor = SculptureCell(
                            x: x + surface.neighbor.x,
                            y: y + surface.neighbor.y,
                            z: z + surface.neighbor.z
                        )
                        if let glyph = sculpture.glyph(at: neighbor), glyph != Sculpture.empty { continue }
                        faceCount += 1
                        guard faceCount <= maximumFaces else { throw SculptureOBJExportError.tooManyFaces }
                    }
                }
            }
        }
        var vertices: [Vertex] = []
        var indices: [Vertex: Int] = [:]
        var groups: [UInt8: [Face]] = [:]

        for z in 0..<sculpture.depth {
            try Task.checkCancellation()
            for y in 0..<sculpture.height {
                for x in 0..<sculpture.width {
                    let cell = SculptureCell(x: x, y: y, z: z)
                    guard let glyph = sculpture.glyph(at: cell), glyph != Sculpture.empty else { continue }
                    for (direction, surface) in Surface.all.enumerated() {
                        let neighbor = SculptureCell(
                            x: x + surface.neighbor.x,
                            y: y + surface.neighbor.y,
                            z: z + surface.neighbor.z
                        )
                        if let neighborGlyph = sculpture.glyph(at: neighbor), neighborGlyph != Sculpture.empty {
                            continue
                        }
                        let faceIndices = surface.corners.map { offset in
                            let vertex = Vertex(x: x + offset.x, y: y + offset.y, z: z + offset.z)
                            if let index = indices[vertex] { return index }
                            vertices.append(vertex)
                            let index = vertices.count
                            indices[vertex] = index
                            return index
                        }
                        groups[glyph, default: []].append(Face(vertices: faceIndices, normal: direction + 1))
                    }
                }
            }
        }

        var lines = [
            "# Rook occupied-cell surface mesh",
            "# \(sculpture.title)",
            "# One cell is one unit. Y points up; Z follows the 3md slice index.",
            "o sculpture",
        ]
        lines.reserveCapacity(vertices.count + groups.values.reduce(0) { $0 + $1.count } + 20)
        for vertex in vertices {
            lines.append(
                "v \(half(vertex.x * 2 - sculpture.width)) \(half(sculpture.height - vertex.y * 2)) \(half(vertex.z * 2 - sculpture.depth))"
            )
        }
        lines.append(contentsOf: ["vn -1 0 0", "vn 1 0 0", "vn 0 -1 0", "vn 0 1 0", "vn 0 0 -1", "vn 0 0 1"])
        lines.append("s off")
        for glyph in groups.keys.sorted() {
            try Task.checkCancellation()
            lines.append("g glyph_\(glyph)")
            for face in groups[glyph, default: []] {
                lines.append("f " + face.vertices.map { "\($0)//\(face.normal)" }.joined(separator: " "))
            }
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func half(_ doubled: Int) -> String {
        guard !doubled.isMultiple(of: 2) else { return String(doubled / 2) }
        return (doubled < 0 ? "-" : "") + "\(abs(doubled) / 2).5"
    }
}

private struct Vertex: Hashable, Sendable {
    let x: Int
    let y: Int
    let z: Int
}

private struct Face {
    let vertices: [Int]
    let normal: Int
}

private struct Surface: Sendable {
    let neighbor: Vertex
    let corners: [Vertex]

    // Counterclockwise when viewed from outside after the document's downward Y axis is inverted.
    static let all: [Self] = [
        Self(
            neighbor: Vertex(x: -1, y: 0, z: 0),
            corners: [
                Vertex(x: 0, y: 1, z: 0), Vertex(x: 0, y: 1, z: 1), Vertex(x: 0, y: 0, z: 1), Vertex(x: 0, y: 0, z: 0),
            ]
        ),
        Self(
            neighbor: Vertex(x: 1, y: 0, z: 0),
            corners: [
                Vertex(x: 1, y: 1, z: 0), Vertex(x: 1, y: 0, z: 0), Vertex(x: 1, y: 0, z: 1), Vertex(x: 1, y: 1, z: 1),
            ]
        ),
        Self(
            neighbor: Vertex(x: 0, y: 1, z: 0),
            corners: [
                Vertex(x: 0, y: 1, z: 0), Vertex(x: 1, y: 1, z: 0), Vertex(x: 1, y: 1, z: 1), Vertex(x: 0, y: 1, z: 1),
            ]
        ),
        Self(
            neighbor: Vertex(x: 0, y: -1, z: 0),
            corners: [
                Vertex(x: 0, y: 0, z: 0), Vertex(x: 0, y: 0, z: 1), Vertex(x: 1, y: 0, z: 1), Vertex(x: 1, y: 0, z: 0),
            ]
        ),
        Self(
            neighbor: Vertex(x: 0, y: 0, z: -1),
            corners: [
                Vertex(x: 0, y: 1, z: 0), Vertex(x: 0, y: 0, z: 0), Vertex(x: 1, y: 0, z: 0), Vertex(x: 1, y: 1, z: 0),
            ]
        ),
        Self(
            neighbor: Vertex(x: 0, y: 0, z: 1),
            corners: [
                Vertex(x: 0, y: 1, z: 1), Vertex(x: 1, y: 1, z: 1), Vertex(x: 1, y: 0, z: 1), Vertex(x: 0, y: 0, z: 1),
            ]
        ),
    ]
}
