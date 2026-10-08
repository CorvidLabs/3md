import Foundation
import ThreeMD

/// Our application schema maps fenced ASCII grids onto ThreeMD's spatial planes.
public enum SculptureCodec {
    public static let maximumBytes = 20 * 1_048_576
    // Canonical 256³ files have fewer than 67,000 lines. Bound ThreeMD's per-line allocations too.
    private static let maximumLines = 100_000

    public static func decode(_ data: Data) throws -> Sculpture {
        guard data.count <= maximumBytes else { throw SculptureError.oversizedFile }
        try Task.checkCancellation()
        guard let source = String(data: data, encoding: .utf8) else { throw SculptureError.invalidGrid }
        // Accepted grids cannot contain directive-looking rows. Bound line and plane allocations before ThreeMD.
        var directiveCount = 0
        var lineCount = 0
        source.enumerateLines { line, stop in
            if Task.isCancelled {
                stop = true
                return
            }
            lineCount += 1
            if lineCount > maximumLines {
                stop = true
                return
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("@plane") {
                directiveCount += 1
                if directiveCount > Sculpture.maximumDimension { stop = true }
            }
        }
        try Task.checkCancellation()
        guard lineCount <= maximumLines else { throw SculptureError.invalidGrid }
        guard directiveCount <= Sculpture.maximumDimension else { throw SculptureError.unsupportedSchema }
        let document = try Parser().parse(source)
        try Task.checkCancellation()
        return try sculpture(from: document)
    }

    /// Shared schema validation after the bounded portable codec has decoded a document.
    internal static func sculpture(from document: Document) throws -> Sculpture {
        guard document.axis == .space, document.metadata["scene-schema"] == "ascii-sculpture-1",
            let width = document.metadata["width"].flatMap(Int.init),
            let height = document.metadata["height"].flatMap(Int.init),
            (1...Sculpture.maximumDimension).contains(width), (1...Sculpture.maximumDimension).contains(height),
            (1...Sculpture.maximumDimension).contains(document.planes.count),
            document.preamble == nil, Set(document.metadata.keys) == ["scene-schema", "width", "height"]
        else { throw SculptureError.unsupportedSchema }
        let layers = try document.planesByZ.enumerated().map { index, plane in
            try Task.checkCancellation()
            guard plane.z == Double(index), plane.x == nil, plane.y == nil, plane.attributes.isEmpty else {
                throw SculptureError.unsupportedPlane
            }
            let lines = plane.body.components(separatedBy: "\n")
            guard lines.first == "```ascii", lines.last == "```", lines.count == height + 2 else {
                throw SculptureError.invalidGrid
            }
            let rows = lines.dropFirst().dropLast()
            var grid: [UInt8] = []
            grid.reserveCapacity(width * height)
            for row in rows {
                guard row.utf8.count == width else { throw SculptureError.invalidGrid }
                grid.append(contentsOf: row.utf8)
            }
            return grid
        }
        try Task.checkCancellation()
        let sculpture = try Sculpture(title: document.title ?? "Untitled", width: width, height: height, layers: layers)
        try Task.checkCancellation()
        return sculpture
    }

    public static func encode(_ sculpture: Sculpture) -> Data {
        Data(Serializer().render(document(for: sculpture)).utf8)
    }

    internal static func document(for sculpture: Sculpture) -> Document {
        let planes = sculpture.layers.enumerated().map { index, grid in
            let rows = (0..<sculpture.height).map { y in
                String(decoding: grid[(y * sculpture.width)..<((y + 1) * sculpture.width)], as: UTF8.self)
            }
            return Plane(
                z: Double(index),
                label: "Slice \(index + 1)",
                body: (["```ascii"] + rows + ["```"])
                    .joined(separator: "\n")
            )
        }
        return Document(
            version: "1.0",
            axis: .space,
            title: sculpture.title,
            metadata: [
                "scene-schema": "ascii-sculpture-1", "width": "\(sculpture.width)", "height": "\(sculpture.height)",
            ],
            planes: planes
        )
    }
}
