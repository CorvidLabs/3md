import Foundation

/// A string-to-string object scanner checks keys before a dictionary can discard duplicate JSON spellings.
internal struct DocumentFileLedgerScanner {
    let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func references() throws -> [DocumentFileReference] {
        try take(123)
        try whitespace()
        if consume(125) { return try finish([]) }
        var references: [DocumentFileReference] = []
        var keys: Set<String> = []
        while true {
            try DocumentStorageCancellation.check()
            let glyph = try string()
            guard glyph.utf8.count == 1, let byte = glyph.utf8.first, (33...126).contains(byte) else {
                throw DocumentFileCompositionError.invalidGlyph(glyph)
            }
            guard keys.insert(glyph).inserted else {
                throw DocumentFileCompositionError.invalidLedger("duplicate JSON key")
            }
            try take(58)
            let source = try string()
            references.append(.init(glyph: glyph, source: source))
            try whitespace()
            if consume(125) { return try finish(references.sorted { $0.glyph < $1.glyph }) }
            try take(44)
        }
    }

    private mutating func finish(_ references: [DocumentFileReference]) throws -> [DocumentFileReference] {
        try whitespace()
        guard index == bytes.count else { throw DocumentFileCompositionError.invalidLedger("trailing JSON") }
        return references
    }

    private mutating func string() throws -> String {
        try whitespace()
        let start = index
        try take(34)
        while index < bytes.count {
            if index.isMultiple(of: 4_096) { try DocumentStorageCancellation.check() }
            let byte = bytes[index]
            index += 1
            guard byte >= 32 else { throw DocumentFileCompositionError.invalidLedger("unescaped JSON control") }
            if byte == 34 {
                do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) } catch {
                    throw DocumentFileCompositionError.invalidLedger("malformed JSON string")
                }
            }
            if byte == 92 {
                guard index < bytes.count else { break }
                index += 1
            }
        }
        throw DocumentFileCompositionError.invalidLedger("unterminated JSON string")
    }

    private mutating func whitespace() throws {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) {
            if index.isMultiple(of: 4_096) { try DocumentStorageCancellation.check() }
            index += 1
        }
    }

    private mutating func take(_ byte: UInt8) throws {
        try whitespace()
        guard consume(byte) else { throw DocumentFileCompositionError.invalidLedger("malformed string object") }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
}
