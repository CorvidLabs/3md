import Foundation

/// Development-only wire values, independent of the library's Codable models.
enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    static func == (left: JSONValue, right: JSONValue) -> Bool {
        switch (left, right) {
        case (.string(let first), .string(let second)): return first.utf8.elementsEqual(second.utf8)
        case (.number(let first), .number(let second)): return first == second
        case (.bool(let first), .bool(let second)): return first == second
        case (.null, .null): return true
        case (.array(let first), .array(let second)): return first == second
        case (.object(let first), .object(let second)):
            let orderedFirst = first.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            let orderedSecond = second.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            return orderedFirst.count == orderedSecond.count
                && zip(orderedFirst, orderedSecond).allSatisfy {
                    $0.0.key.utf8.elementsEqual($0.1.key.utf8) && $0.0.value == $0.1.value
                }
        default: return false
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct InterchangeRequest: Codable, Sendable {
    var schema = "3md-interchange-1"
    let kind: String
    let bytesHex: String
}

struct InterchangeResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var error: String?
    var canonicalHex: String?
    var binaryHex: String?
    var legacyHex: String?
    var rawCanonicalHex: String?
    var revisionHex: String?
    var adoptedHex: String?
    var editedHex: String?
    var staleRejected: Bool?
    var semantic: JSONValue?
}

enum InterchangeFailure: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let message): return message
        }
    }
}

extension Data {
    init(hex: String) throws {
        guard hex.utf8.count.isMultiple(of: 2), hex.utf8.count <= 32 * 1024 * 1024 else {
            throw InterchangeFailure.invalid("Invalid or oversized protocol hex")
        }
        let source = Array(hex.utf8)
        var output = Data()
        output.reserveCapacity(source.count / 2)
        func nibble(_ byte: UInt8) throws -> UInt8 {
            switch byte {
            case 48...57: return byte - 48
            case 97...102: return byte - 87
            default: throw InterchangeFailure.invalid("Hex must be lowercase ASCII")
            }
        }
        for index in stride(from: 0, to: source.count, by: 2) {
            output.append(try nibble(source[index]) * 16 + nibble(source[index + 1]))
        }
        self = output
    }

    var hex: String {
        let digits = Array("0123456789abcdef".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(count * 2)
        for byte in self { output.append(digits[Int(byte >> 4)]); output.append(digits[Int(byte & 15)]) }
        return String(decoding: output, as: UTF8.self)
    }
}

/// Rejects equivalent JSON keys before Swift dictionaries can discard their spelling.
func validateInterchangeJSON(_ data: Data) throws {
    guard data.count <= 32 * 1024 * 1024 else { throw InterchangeFailure.invalid("Protocol line too large") }
    var scanner = ProtocolJSONScanner(bytes: Array(data))
    try scanner.validate()
}

private struct ProtocolJSONScanner {
    let bytes: [UInt8]
    var index = 0

    mutating func validate() throws {
        guard bytes.count <= 32 * 1024 * 1024 else { throw InterchangeFailure.invalid("Protocol line too large") }
        try value(depth: 0)
        whitespace()
        guard index == bytes.count else { throw InterchangeFailure.invalid("Trailing JSON") }
    }

    private mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    private mutating func take(_ byte: UInt8) throws {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else {
            throw InterchangeFailure.invalid("Malformed protocol JSON")
        }
        index += 1
    }

    private mutating func string() throws -> Range<Int> {
        whitespace()
        let start = index
        try take(34)
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 { return start..<index }
            if byte == 92 {
                guard index < bytes.count else { break }
                index += 1
            }
        }
        throw InterchangeFailure.invalid("Unterminated JSON string")
    }

    private mutating func value(depth: Int) throws {
        whitespace()
        guard depth <= 64, index < bytes.count else { throw InterchangeFailure.invalid("Invalid JSON depth/value") }
        switch bytes[index] {
        case 123:
            index += 1; whitespace()
            if index < bytes.count, bytes[index] == 125 { index += 1; return }
            var keys: Set<String> = []
            while true {
                let range = try string()
                let key = try JSONDecoder().decode(String.self, from: Data(bytes[range]))
                guard keys.insert(key).inserted else {
                    throw InterchangeFailure.invalid("Duplicate/equivalent JSON key")
                }
                try take(58); try value(depth: depth + 1); whitespace()
                if index < bytes.count, bytes[index] == 125 { index += 1; return }
                try take(44)
            }
        case 91:
            index += 1; whitespace()
            if index < bytes.count, bytes[index] == 93 { index += 1; return }
            while true {
                try value(depth: depth + 1); whitespace()
                if index < bytes.count, bytes[index] == 93 { index += 1; return }
                try take(44)
            }
        case 34: _ = try string()
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            guard index > start else { throw InterchangeFailure.invalid("Invalid JSON token") }
        }
    }
}
