import Foundation

internal struct DocumentCompositionManifest: Decodable {
    let schema: String
    let rootID: String
    let entries: [Entry]

    struct Entry: Decodable {
        let id: String
        let source: String
        let references: [Reference]

        init(from decoder: any Decoder) throws {
            let container = try strictContainer(decoder, keys: ["id", "source", "references"])
            id = try container.decode(String.self, forKey: .init("id"))
            source = try container.decode(String.self, forKey: .init("source"))
            references = try container.decode([Reference].self, forKey: .init("references"))
        }
    }

    struct Reference: Decodable {
        let targetID: String
        let attributes: [String: String]

        init(from decoder: any Decoder) throws {
            let container = try strictContainer(decoder, keys: ["targetID", "attributes"])
            targetID = try container.decode(String.self, forKey: .init("targetID"))
            attributes = try container.decode([String: String].self, forKey: .init("attributes"))
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try strictContainer(decoder, keys: ["schema", "rootID", "entries"])
        schema = try container.decode(String.self, forKey: .init("schema"))
        rootID = try container.decode(String.self, forKey: .init("rootID"))
        entries = try container.decode([Entry].self, forKey: .init("entries"))
    }
}

private struct CompositionCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func strictContainer(
    _ decoder: any Decoder,
    keys: Set<String>
) throws -> KeyedDecodingContainer<CompositionCodingKey> {
    let container = try decoder.container(keyedBy: CompositionCodingKey.self)
    guard Set(container.allKeys.map(\.stringValue)) == keys else {
        throw DocumentCompositionError.invalidProfile("missing or unknown JSON record keys")
    }
    return container
}

/// A bounded writer avoids allocating an oversized escaped JSON result before checking its size.
internal enum DocumentCompositionJSON {
    static func encode(
        rootID: String,
        entries: [DocumentEntry],
        sources: [String: Data],
        maximumBytes: Int
    ) throws -> Data {
        var writer = Writer(maximumBytes: maximumBytes)
        try writer.append("{\n  \"entries\": [")
        for (index, entry) in entries.sorted(by: { $0.id < $1.id }).enumerated() {
            try DocumentStorageCancellation.check()
            try writer.append(index == 0 ? "\n" : ",\n")
            try writer.append("    {\n      \"id\": ")
            try writer.string(entry.id)
            try writer.append(",\n      \"references\": [")
            for (referenceIndex, reference) in entry.references.enumerated() {
                try writer.append(referenceIndex == 0 ? "\n" : ",\n")
                try writer.append("        {\"attributes\": {")
                for (attributeIndex, key) in reference.attributes.keys.sorted().enumerated() {
                    try writer.append(attributeIndex == 0 ? "" : ", ")
                    try writer.string(key)
                    try writer.append(": ")
                    try writer.string(reference.attributes[key] ?? "")
                }
                try writer.append("}, \"targetID\": ")
                try writer.string(reference.targetID)
                try writer.append("}")
            }
            try writer.append(entry.references.isEmpty ? "],\n      \"source\": " : "\n      ],\n      \"source\": ")
            guard let source = sources[entry.id] else {
                throw DocumentCompositionError.invalidProfile("definition source missing")
            }
            try writer.string(source)
            try writer.append("\n    }")
        }
        try writer.append("\n  ],\n  \"rootID\": ")
        try writer.string(rootID)
        try writer.append(",\n  \"schema\": \"3md-composition-1\"\n}")
        try DocumentStorageCancellation.check()
        return writer.data
    }

    static func decode(_ data: Data, limits: DocumentCompositionLimits) throws -> DocumentCompositionManifest {
        guard data.count <= limits.maximumProfileBytes else { throw DocumentCompositionError.profileBytesExceeded }
        var scanner = Scanner(bytes: Array(data), limits: limits)
        try scanner.scan()
        try DocumentStorageCancellation.check()
        do {
            return try JSONDecoder().decode(DocumentCompositionManifest.self, from: data)
        } catch let error as DocumentCompositionError {
            throw error
        } catch {
            throw DocumentCompositionError.invalidProfile("JSON fields have invalid types or values")
        }
    }

    private struct Writer {
        let maximumBytes: Int
        var data = Data()

        mutating func append(_ text: String) throws {
            try append(text.utf8)
        }

        mutating func append<Bytes: Collection>(_ bytes: Bytes) throws where Bytes.Element == UInt8 {
            guard bytes.count <= maximumBytes - data.count else {
                throw DocumentCompositionError.profileBytesExceeded
            }
            data.append(contentsOf: bytes)
        }

        mutating func string(_ text: String) throws { try string(Data(text.utf8)) }

        mutating func string(_ bytes: Data) throws {
            try append("\"")
            var run = bytes.startIndex
            for index in bytes.indices {
                if index.isMultiple(of: 4_096) { try DocumentStorageCancellation.check() }
                let escape: String?
                switch bytes[index] {
                case 34: escape = "\\\""
                case 92: escape = "\\\\"
                case 8: escape = "\\b"
                case 9: escape = "\\t"
                case 10: escape = "\\n"
                case 12: escape = "\\f"
                case 13: escape = "\\r"
                case 0...31: escape = String(format: "\\u%04x", bytes[index])
                default: escape = nil
                }
                if let escape {
                    try append(bytes[run..<index])
                    try append(escape)
                    run = index + 1
                }
            }
            try append(bytes[run..<bytes.endIndex])
            try append("\"")
        }
    }

    /// Foundation decoders discard duplicate keys. Scan before decoding and bound record allocations.
    private struct Scanner {
        let bytes: [UInt8]
        let limits: DocumentCompositionLimits
        var index = 0
        var arrayElements = 0
        var objects = 0

        mutating func scan() throws {
            try value(depth: 0)
            try whitespace()
            guard index == bytes.count else { throw invalid("trailing JSON input") }
        }

        mutating func value(depth: Int) throws {
            try DocumentStorageCancellation.check()
            guard depth <= 12 else { throw invalid("excessive JSON nesting") }
            try whitespace()
            guard index < bytes.count else { throw invalid("truncated JSON") }
            switch bytes[index] {
            case 123: try object(depth: depth + 1)
            case 91: try array(depth: depth + 1)
            case 34: _ = try string(isKey: false)
            case 116: try literal("true")
            case 102: try literal("false")
            case 110: try literal("null")
            case 45, 48...57:
                // The manifest has no numbers; reject them before generic decoding allocates records.
                throw invalid("numeric JSON fields are not part of this profile")
            default: throw invalid("invalid JSON value")
            }
        }

        mutating func object(depth: Int) throws {
            objects += 1
            guard objects <= 1 + limits.maximumDefinitions + 2 * limits.maximumReferences else {
                throw invalid("too many JSON records")
            }
            index += 1
            try whitespace()
            if consume(125) { return }
            var keys: Set<String> = []
            while true {
                guard let key = try string(isKey: true), keys.insert(key).inserted else {
                    throw invalid("duplicate JSON object key")
                }
                guard keys.count <= max(3, limits.maximumReferenceAttributes) else {
                    throw DocumentCompositionError.referenceAttributesExceeded
                }
                try whitespace()
                guard consume(58) else { throw invalid("missing JSON colon") }
                try value(depth: depth)
                try whitespace()
                if consume(125) { return }
                guard consume(44) else { throw invalid("missing JSON comma") }
                try whitespace()
            }
        }

        mutating func array(depth: Int) throws {
            index += 1
            try whitespace()
            if consume(93) { return }
            while true {
                arrayElements += 1
                guard arrayElements <= limits.maximumDefinitions + limits.maximumReferences else {
                    throw invalid("too many JSON array elements")
                }
                try value(depth: depth)
                try whitespace()
                if consume(93) { return }
                guard consume(44) else { throw invalid("missing JSON comma") }
                try whitespace()
            }
        }

        mutating func string(isKey: Bool) throws -> String? {
            guard consume(34) else { throw invalid("JSON key must be a string") }
            let start = index - 1
            while index < bytes.count {
                if index.isMultiple(of: 4_096) { try DocumentStorageCancellation.check() }
                let byte = bytes[index]
                index += 1
                if byte == 34 {
                    guard isKey else { return nil }
                    guard index - start <= 6 * limits.maximumReferenceAttributeBytes + 256 else {
                        throw DocumentCompositionError.referenceAttributesExceeded
                    }
                    do {
                        return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
                    } catch {
                        throw invalid("invalid JSON key escape")
                    }
                }
                guard byte >= 32 else { throw invalid("unescaped JSON control character") }
                if byte == 92 {
                    guard index < bytes.count else { throw invalid("truncated JSON escape") }
                    let escaped = bytes[index]
                    index += 1
                    if escaped == 117 {
                        guard bytes.count - index >= 4 else { throw invalid("truncated Unicode escape") }
                        for digit in bytes[index..<(index + 4)] {
                            guard (48...57).contains(digit) || (65...70).contains(digit) || (97...102).contains(digit)
                            else { throw invalid("invalid Unicode escape") }
                        }
                        index += 4
                    } else if ![UInt8(34), 92, 47, 98, 102, 110, 114, 116].contains(escaped) {
                        throw invalid("invalid JSON escape")
                    }
                }
            }
            throw invalid("unterminated JSON string")
        }

        mutating func literal(_ text: String) throws {
            guard bytes.count - index >= text.utf8.count,
                bytes[index..<(index + text.utf8.count)].elementsEqual(text.utf8)
            else { throw invalid("invalid JSON literal") }
            index += text.utf8.count
        }

        mutating func whitespace() throws {
            while index < bytes.count, [UInt8(32), 9, 10, 13].contains(bytes[index]) {
                if index.isMultiple(of: 4_096) { try DocumentStorageCancellation.check() }
                index += 1
            }
        }

        mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        func invalid(_ message: String) -> DocumentCompositionError { .invalidProfile(message) }
    }
}
