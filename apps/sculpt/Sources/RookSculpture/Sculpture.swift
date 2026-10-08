import Foundation

/// A bounded volume. Period is an empty cell; every other allowed character is occupied.
public struct Sculpture: Equatable, Sendable {
    public static let maximumDimension = 256
    public static let palette: [UInt8] = Array("#@*+ox:=-".utf8)
    public static let empty: UInt8 = 46

    public let width: Int
    public let height: Int
    public private(set) var title: String
    public private(set) var layers: [[UInt8]]
    private var occupiedCells: Int
    private var occupiedCellsByLayer: [Int]
    private var occupiedCellsByRow: [[Int]]
    public var depth: Int { layers.count }
    public var occupiedCount: Int { occupiedCells }

    public init(title: String, width: Int, height: Int, layers: [[UInt8]]) throws {
        guard (1...Self.maximumDimension).contains(width), (1...Self.maximumDimension).contains(height),
            (1...Self.maximumDimension).contains(layers.count)
        else { throw SculptureError.invalidDimensions }
        guard Self.isValidTitle(title) else { throw SculptureError.invalidTitle }
        guard layers.allSatisfy({ $0.count == width * height }) else { throw SculptureError.invalidGrid }
        var count = 0
        var layerCounts: [Int] = []
        var rowCounts: [[Int]] = []
        layerCounts.reserveCapacity(layers.count)
        rowCounts.reserveCapacity(layers.count)
        for layer in layers {
            var layerCount = 0
            var counts = [Int](repeating: 0, count: height)
            for y in 0..<height {
                let offset = y * width
                var rowCount = 0
                for x in 0..<width {
                    let glyph = layer[offset + x]
                    guard glyph == Self.empty || Self.palette.contains(glyph) else { throw SculptureError.invalidGlyph }
                    if glyph != Self.empty { rowCount += 1 }
                }
                counts[y] = rowCount
                layerCount += rowCount
            }
            count += layerCount
            layerCounts.append(layerCount)
            rowCounts.append(counts)
        }
        self.title = title
        self.width = width
        self.height = height
        self.layers = layers
        occupiedCells = count
        occupiedCellsByLayer = layerCounts
        occupiedCellsByRow = rowCounts
    }

    public func glyph(at cell: SculptureCell) -> UInt8? {
        guard contains(cell) else { return nil }
        return layers[cell.z][cell.y * width + cell.x]
    }

    @discardableResult
    public mutating func paint(_ cell: SculptureCell, glyph: UInt8) -> Bool {
        guard contains(cell), glyph == Self.empty || Self.palette.contains(glyph), self.glyph(at: cell) != glyph
        else { return false }
        if layers[cell.z][cell.y * width + cell.x] == Self.empty {
            occupiedCells += 1
            occupiedCellsByLayer[cell.z] += 1
            occupiedCellsByRow[cell.z][cell.y] += 1
        } else if glyph == Self.empty {
            occupiedCells -= 1
            occupiedCellsByLayer[cell.z] -= 1
            occupiedCellsByRow[cell.z][cell.y] -= 1
        }
        layers[cell.z][cell.y * width + cell.x] = glyph
        return true
    }

    public mutating func rename(_ title: String) throws {
        guard Self.isValidTitle(title) else { throw SculptureError.invalidTitle }
        self.title = title
    }

    public mutating func addLayer(after index: Int, duplicate: Bool = false) throws {
        guard layers.indices.contains(index) else { throw SculptureError.invalidGrid }
        guard depth < Self.maximumDimension else { throw SculptureError.tooManyLayers }
        let layer = duplicate ? layers[index] : Array(repeating: Self.empty, count: width * height)
        let count = duplicate ? occupiedCellsByLayer[index] : 0
        let rowCounts = duplicate ? occupiedCellsByRow[index] : Array(repeating: 0, count: height)
        layers.insert(layer, at: index + 1)
        occupiedCellsByLayer.insert(count, at: index + 1)
        occupiedCellsByRow.insert(rowCounts, at: index + 1)
        occupiedCells += count
    }

    public mutating func removeLayer(at index: Int) throws {
        guard depth > 1 else { throw SculptureError.lastLayer }
        guard layers.indices.contains(index) else { throw SculptureError.invalidGrid }
        occupiedCells -= occupiedCellsByLayer[index]
        layers.remove(at: index)
        occupiedCellsByLayer.remove(at: index)
        occupiedCellsByRow.remove(at: index)
    }

    public mutating func rotateLayer(at index: Int) throws {
        guard layers.indices.contains(index) else { throw SculptureError.invalidGrid }
        guard width == height else { throw SculptureError.squareLayerRequired }
        let source = layers[index]
        var rowCounts = [Int](repeating: 0, count: height)
        for y in 0..<height {
            for x in 0..<width {
                let glyph = source[y * width + x]
                layers[index][x * width + width - y - 1] = glyph
                if glyph != Self.empty { rowCounts[x] += 1 }
            }
        }
        occupiedCellsByRow[index] = rowCounts
    }

    public static func blank() -> Self {
        // This fixed, bounded construction always satisfies the initializer's contract.
        try! Self(title: "Untitled", width: 16, height: 16, layers: [Array(repeating: empty, count: 256)])
    }

    public static func orb() -> Self {
        let size = 16
        let layers = (0..<size).map { z in
            (0..<size * size).map { index -> UInt8 in
                let x = Double(index % size) - 7.5
                let y = Double(index / size) - 7.5
                let z = Double(z) - 7.5
                let radius = sqrt(x * x + y * y + z * z)
                return (5.6...6.7).contains(radius) ? 35 : empty
            }
        }
        return try! Self(title: "Character orb", width: size, height: size, layers: layers)
    }

    private func contains(_ cell: SculptureCell) -> Bool {
        (0..<width).contains(cell.x) && (0..<height).contains(cell.y) && layers.indices.contains(cell.z)
    }

    private static func isValidTitle(_ title: String) -> Bool {
        !title.isEmpty && title.utf8.count <= 80 && title.utf8.allSatisfy { (32...126).contains($0) }
    }

    /// Cached occupancy for sparse rendering. Out-of-bounds slices return false.
    public func containsOccupiedCells(inLayer index: Int) -> Bool {
        guard layers.indices.contains(index) else { return false }
        return occupiedCellsByLayer[index] > 0
    }

    /// Cached character count for slice summaries. Invalid slice indices return zero.
    public func occupiedCount(inLayer index: Int) -> Int {
        guard layers.indices.contains(index) else { return 0 }
        return occupiedCellsByLayer[index]
    }

    /// Cached occupancy for sparse rendering. Out-of-bounds slices or rows return false.
    public func containsOccupiedCells(inRow row: Int, ofLayer index: Int) -> Bool {
        guard layers.indices.contains(index), (0..<height).contains(row) else { return false }
        return occupiedCellsByRow[index][row] > 0
    }
}

public struct SculptureCell: Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let z: Int

    public init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public enum SculptureError: Error, LocalizedError, Sendable {
    case invalidDimensions, invalidGrid, invalidGlyph, invalidTitle, unsupportedSchema, unsupportedPlane
    case tooManyLayers, lastLayer, squareLayerRequired, oversizedFile

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions: "Use dimensions and a layer count between 1 and \(Sculpture.maximumDimension)."
        case .invalidGrid: "Every layer must have the same rectangular grid."
        case .invalidGlyph: "Use the character palette or a period for an empty cell."
        case .invalidTitle: "Use a title of 1–80 printable ASCII characters."
        case .unsupportedSchema: "Open a 3md sculpture saved by this editor. Other 3md documents remain unchanged."
        case .unsupportedPlane: "Sculpture layers must be consecutive integer Z slices with fenced ASCII grids."
        case .tooManyLayers: "This sculpture already has the maximum of \(Sculpture.maximumDimension) layers."
        case .lastLayer: "Keep at least one layer in the sculpture."
        case .squareLayerRequired: "Quarter-turn rotation needs a square layer."
        case .oversizedFile: "Choose a sculpture file at most 20 MiB."
        }
    }
}
