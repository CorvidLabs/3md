import Foundation

public enum SculptureStorageFormat: String, Codable, CaseIterable, Sendable {
    case readable, compact

    public var fileExtension: String {
        switch self {
        case .readable: "3md"
        case .compact: "3mdb"
        }
    }
}

/// Shared opening/saving boundary. Readable output remains the existing ThreeMD schema.
public enum SculptureDocumentCodec {
    public static let maximumBytes = SculptureCodec.maximumBytes

    public static func format(of data: Data) -> SculptureStorageFormat {
        SculptureBinaryCodec.hasMagic(data) ? .compact : .readable
    }

    public static func decode(_ data: Data) throws -> Sculpture {
        switch format(of: data) {
        case .readable: try SculptureCodec.decode(data)
        case .compact: try SculptureBinaryCodec.decode(data)
        }
    }

    public static func encode(_ sculpture: Sculpture, format: SculptureStorageFormat) throws -> Data {
        try Task.checkCancellation()
        switch format {
        case .readable:
            let data = SculptureCodec.encode(sculpture)
            try Task.checkCancellation()
            return data
        case .compact:
            return try SculptureBinaryCodec.encode(sculpture)
        }
    }
}
