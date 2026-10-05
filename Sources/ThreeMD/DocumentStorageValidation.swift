import Foundation

internal enum DocumentStorageValidation {
    static func parse(_ data: Data, limits: DocumentDecodeLimits) throws -> Document {
        try DocumentStorageCancellation.check()
        guard data.count <= limits.maximumDecodedBytes else { throw DocumentStorageError.oversizedOutput }
        var lines = 1
        var record = 0
        for (index, byte) in data.enumerated() {
            if index.isMultiple(of: 65_536) { try DocumentStorageCancellation.check() }
            if byte == 10 {
                lines += 1
                record = 0
                guard lines <= limits.maximumLines else { throw DocumentStorageError.tooManyLines }
            } else {
                record += 1
                guard record <= limits.maximumRecordBytes else { throw DocumentStorageError.oversizedRecord }
            }
        }
        guard let source = String(data: data, encoding: .utf8) else { throw DocumentStorageError.invalidUTF8 }
        try preflightPlanes(source, limits: limits)
        let document: Document
        do { document = try Parser().parse(source) } catch let error as ParseError {
            throw DocumentStorageError.invalidText(error)
        }
        try DocumentStorageCancellation.check()
        try validateRecords(document, limits: limits)
        return document
    }

    static func canonicalData(_ document: Document, limits: DocumentDecodeLimits) throws -> Data {
        try DocumentStorageCancellation.check()
        try validateRecords(document, limits: limits)
        guard !document.version.isEmpty else {
            throw DocumentStorageError.invalidDocument("The version must be nonempty.")
        }
        var seen: Set<Double> = []
        for plane in document.planes {
            try DocumentStorageCancellation.check()
            guard plane.z.isFinite, plane.x?.isFinite != false, plane.y?.isFinite != false else {
                throw DocumentStorageError.invalidDocument("Plane coordinates must be finite.")
            }
            guard seen.insert(plane.z).inserted else {
                throw DocumentStorageError.invalidDocument("Plane positions must be unique.")
            }
        }
        var writer = BoundedDocumentWriter(maximumBytes: limits.maximumDecodedBytes)
        try writer.line("---")
        try writer.append("3md: ")
        try writer.quoted(document.version)
        try writer.line()
        try writer.append("axis: ")
        try writer.quoted(document.axis.rawValue)
        try writer.line()
        if let title = document.title {
            try writer.append("title: ")
            try writer.quoted(title)
            try writer.line()
        }
        for key in document.metadata.keys.sorted() {
            try DocumentStorageCancellation.check()
            guard !["3md", "axis", "title"].contains(key.lowercased()), !key.contains(":"),
                !key.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            else {
                throw DocumentStorageError.invalidDocument("Metadata keys cannot shadow reserved fields or comments.")
            }
            try writer.append(key)
            try writer.append(": ")
            try writer.quoted(document.metadata[key] ?? "")
            try writer.line()
        }
        try writer.line("---")
        if let preamble = document.preamble { try writer.line(); try writer.line(preamble) }
        for plane in document.planes {
            try DocumentStorageCancellation.check()
            try writer.line()
            try writer.append("@plane z=\(plane.z.formatted3MD())")
            if let label = plane.label { try writer.append(" label="); try writer.quoted(label) }
            if let x = plane.x { try writer.append(" x=\(x.formatted3MD())") }
            if let y = plane.y { try writer.append(" y=\(y.formatted3MD())") }
            for key in plane.attributes.keys.sorted() {
                try DocumentStorageCancellation.check()
                guard !["z", "x", "y", "label"].contains(key.lowercased()), key == key.lowercased(), !key.contains("=")
                else {
                    throw DocumentStorageError.invalidDocument(
                        "Attribute keys must be lowercase and cannot shadow coordinates or labels."
                    )
                }
                try writer.append(" ")
                try writer.append(key)
                try writer.append("=")
                try writer.quoted(plane.attributes[key] ?? "")
            }
            try writer.line()
            if !plane.body.isEmpty { try writer.line(plane.body) }
        }
        let data = writer.data
        let restored: Document
        do { restored = try parse(data, limits: limits) } catch let error as DocumentStorageError {
            if case .invalidText(let parseError) = error {
                throw DocumentStorageError.invalidDocument(parseError.localizedDescription)
            }
            throw error
        }
        guard restored == document else {
            throw DocumentStorageError.invalidDocument(
                "Text serialization would change metadata, whitespace, fences or planes."
            )
        }
        try DocumentStorageCancellation.check()
        return data
    }

    private static func validateRecords(_ document: Document, limits: DocumentDecodeLimits) throws {
        guard document.planes.count <= limits.maximumPlanes else { throw DocumentStorageError.tooManyPlanes }
        // Charge a conservative lower bound before sorting keys or constructing serialized records.
        var total = 0
        func charge(_ value: String) throws {
            let count = value.utf8.count
            guard count < limits.maximumDecodedBytes - total else { throw DocumentStorageError.oversizedOutput }
            total += count + 1
        }
        func scalar(_ value: String) throws {
            guard value.utf8.count <= limits.maximumRecordBytes else { throw DocumentStorageError.oversizedRecord }
            guard !value.contains("\n"), !value.contains("\r") else {
                throw DocumentStorageError.invalidDocument("Scalar fields cannot contain physical line breaks.")
            }
            try charge(value)
        }
        try scalar(document.version)
        try scalar(document.axis.rawValue)
        if let title = document.title { try scalar(title) }
        for (key, value) in document.metadata {
            try DocumentStorageCancellation.check(); try scalar(key); try scalar(value)
        }
        if let preamble = document.preamble {
            guard preamble.utf8.count <= limits.maximumRecordBytes else { throw DocumentStorageError.oversizedRecord }
            try charge(preamble)
        }
        for plane in document.planes {
            try DocumentStorageCancellation.check()
            guard plane.body.utf8.count <= limits.maximumRecordBytes else { throw DocumentStorageError.oversizedRecord }
            try charge(plane.body)
            if let label = plane.label { try scalar(label) }
            for (key, value) in plane.attributes {
                try DocumentStorageCancellation.check(); try scalar(key); try scalar(value)
            }
        }
    }

    /// Mirrors only frontmatter/fence/directive boundaries, preserving the existing parser's version and duplicate-key rules.
    private static func preflightPlanes(_ source: String, limits: DocumentDecodeLimits) throws {
        var normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        var started = false
        var body = false
        var fence: Character?
        var planes = 0
        var recordBytes = 0
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            try DocumentStorageCancellation.check()
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !started { if trimmed == "---" { started = true }; continue }
            if !body { if trimmed == "---" { body = true }; continue }
            var directive = false
            if let open = fence {
                if trimmed.hasPrefix(String(repeating: open, count: 3)) { fence = nil }
            } else if trimmed.hasPrefix("```") {
                fence = "`"
            } else if trimmed.hasPrefix("~~~") {
                fence = "~"
            } else if raw == "@plane" || raw.hasPrefix("@plane ") || raw.hasPrefix("@plane\t") {
                directive = true
            }
            if directive {
                planes += 1
                recordBytes = 0
                guard planes <= limits.maximumPlanes else { throw DocumentStorageError.tooManyPlanes }
            } else {
                let count = raw.utf8.count
                guard count <= limits.maximumRecordBytes - recordBytes else {
                    throw DocumentStorageError.oversizedRecord
                }
                recordBytes += count
                if recordBytes < limits.maximumRecordBytes { recordBytes += 1 }
            }
        }
    }
}

/// Appends only after checking the remaining byte budget; no interpolated record can exceed that budget first.
private struct BoundedDocumentWriter {
    let maximumBytes: Int
    private(set) var data = Data()

    mutating func append(_ value: String) throws {
        try DocumentStorageCancellation.check()
        guard value.utf8.count <= maximumBytes - data.count else { throw DocumentStorageError.oversizedOutput }
        data.append(contentsOf: value.utf8)
    }

    mutating func line(_ value: String = "") throws {
        try append(value)
        guard data.count < maximumBytes else { throw DocumentStorageError.oversizedOutput }
        data.append(10)
    }

    mutating func quoted(_ value: String) throws {
        var count = 2
        for (index, byte) in value.utf8.enumerated() {
            if index.isMultiple(of: 65_536) { try DocumentStorageCancellation.check() }
            count += byte == 34 || byte == 92 ? 2 : 1
            guard count <= maximumBytes - data.count else { throw DocumentStorageError.oversizedOutput }
        }
        guard count <= maximumBytes - data.count else { throw DocumentStorageError.oversizedOutput }
        data.append(34)
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        data.append(contentsOf: escaped.utf8)
        data.append(34)
    }
}
