@preconcurrency import Foundation

// MARK: - Parser

/// Parses 3md source text into a ``Document``.
///
/// The grammar is intentionally small:
///
/// ```
/// ---
/// 3md: 0.1
/// axis: time
/// title: My Week
/// ---
/// @plane z=0 label="Monday"
/// # Monday
/// - [ ] Standup
///
/// @plane z=1 label="Tuesday"
/// # Tuesday
/// ```
///
/// Frontmatter is required and must declare a `3md` version. Planes are
/// introduced by `@plane` directives carrying `key=value` attributes; the text
/// between directives is plain Markdown. A document with no directives parses as
/// a single plane at `z = 0`.
public struct Parser: Sendable {
    // MARK: - Initializers

    /// Creates a parser.
    public init() {}

    // MARK: - Public Methods

    /// Parses 3md source text.
    /// - Parameter source: The full contents of a `.3md` file.
    /// - Returns: The parsed ``Document``.
    /// - Throws: ``ParseError`` if the source is malformed.
    public func parse(_ source: String) throws -> Document {
        var normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }
        var lines = normalized.components(separatedBy: "\n")

        let frontmatter = try extractFrontmatter(&lines)
        let (version, axis, title, metadata) = try interpretFrontmatter(frontmatter.fields)
        let (preamble, planes) = try parseBody(lines, startingAtLine: frontmatter.bodyStartLine)

        return Document(
            version: version,
            axis: axis,
            title: title,
            metadata: metadata,
            preamble: preamble,
            planes: planes
        )
    }

    // MARK: - Private Types

    /// The result of extracting and splitting the frontmatter block from the source.
    private struct Frontmatter {
        /// The parsed key-value pairs from inside the `---` fences.
        let fields: [(key: String, value: String)]
        /// 1-based line number of the first body line, after the closing `---`.
        let bodyStartLine: Int
    }

    /// A pending plane whose body lines are still being accumulated.
    private struct PendingPlane {
        let lineNumber: Int
        let attributes: [String: String]
        var bodyLines: [String]
    }

    // MARK: - Private Methods

    private func extractFrontmatter(_ lines: inout [String]) throws -> Frontmatter {
        var index = lines.startIndex
        while index < lines.endIndex, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }
        guard index < lines.endIndex, lines[index].trimmingCharacters(in: .whitespaces) == "---" else {
            throw ParseError.missingFrontmatter
        }

        index += 1
        var fields: [(key: String, value: String)] = []

        while index < lines.endIndex {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                lines = index + 1 < lines.endIndex ? Array(lines[(index + 1)...]) : []
                return Frontmatter(fields: fields, bodyStartLine: index + 2)
            }
            if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                guard let separator = trimmed.firstIndex(of: ":") else {
                    throw ParseError.invalidFrontmatter("expected 'key: value', found '\(trimmed)'")
                }
                let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
                let raw = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                fields.append((key: key, value: unquote(raw)))
            }
            index += 1
        }

        throw ParseError.invalidFrontmatter("frontmatter block was not closed with '---'")
    }

    private func interpretFrontmatter(
        _ fields: [(key: String, value: String)]
    ) throws -> (version: String, axis: Axis, title: String?, metadata: [String: String]) {
        var version: String?
        var axis = Axis.layer
        var title: String?
        var metadata: [String: String] = [:]

        for field in fields {
            switch field.key.lowercased() {
            case "3md":
                version = field.value
            case "axis":
                axis = Axis(rawValue: field.value)
            case "title":
                title = field.value
            default:
                metadata[field.key] = field.value
            }
        }

        guard let resolvedVersion = version, !resolvedVersion.isEmpty else {
            throw ParseError.missingVersion
        }
        return (resolvedVersion, axis, title, metadata)
    }

    private func parseBody(
        _ lines: [String],
        startingAtLine bodyStartLine: Int
    ) throws -> (preamble: String?, planes: [Plane]) {
        var seenZ: Set<Double> = []
        var planes: [Plane] = []
        var pending: PendingPlane?
        var preambleLines: [String] = []
        var fence: Character?

        for (offset, raw) in lines.enumerated() {
            let lineNumber = bodyStartLine + offset
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // A directive must begin at column 0 and sit outside a fenced code
            // block, so a `@plane` line inside ``` or ~~~ (or indented as a code
            // block) is treated as body text, not a new plane.
            var isDirective = false
            if let open = fence {
                if trimmed.hasPrefix(String(repeating: open, count: 3)) { fence = nil }
            } else if let opened = fenceCharacter(of: trimmed) {
                fence = opened
            } else if raw.first != " ", raw.first != "\t", firstToken(of: raw) == "@plane" {
                isDirective = true
            }

            guard isDirective else {
                if pending != nil {
                    pending?.bodyLines.append(raw)
                } else {
                    preambleLines.append(raw)
                }
                continue
            }

            if let flushed = pending {
                let plane = try makePlane(from: flushed)
                guard seenZ.insert(plane.z).inserted else {
                    throw ParseError.duplicatePlane(z: plane.z)
                }
                planes.append(plane)
            }

            let attributes = try parseDirective(trimmed, line: lineNumber)
            pending = PendingPlane(lineNumber: lineNumber, attributes: attributes, bodyLines: [])
        }

        if let flushed = pending {
            let plane = try makePlane(from: flushed)
            guard seenZ.insert(plane.z).inserted else {
                throw ParseError.duplicatePlane(z: plane.z)
            }
            planes.append(plane)
        }

        let preamble = collapse(preambleLines)

        if planes.isEmpty {
            guard let content = preamble else { return (nil, []) }
            return (nil, [Plane(z: 0, body: content)])
        }
        return (preamble, planes)
    }

    private func makePlane(from pending: PendingPlane) throws -> Plane {
        let attributes = pending.attributes
        let line = pending.lineNumber

        guard let zRaw = attributes["z"] else {
            throw ParseError.missingPlanePosition(line: line)
        }
        guard let z = parseFiniteDecimal(zRaw) else {
            throw ParseError.invalidPlaneDirective(
                line: line,
                detail: "z must be a finite decimal number, found '\(zRaw)'"
            )
        }

        let x = try optionalDouble(attributes["x"], key: "x", line: line)
        let y = try optionalDouble(attributes["y"], key: "y", line: line)
        let label = attributes["label"]

        let reserved: Set<String> = ["z", "x", "y", "label"]
        let extras = attributes.filter { !reserved.contains($0.key) }

        return Plane(z: z, label: label, x: x, y: y, attributes: extras, body: collapse(pending.bodyLines) ?? "")
    }

    private func optionalDouble(_ value: String?, key: String, line: Int) throws -> Double? {
        guard let value else { return nil }
        guard let number = parseFiniteDecimal(value) else {
            throw ParseError.invalidPlaneDirective(
                line: line,
                detail: "\(key) must be a finite decimal number, found '\(value)'"
            )
        }
        return number
    }

    private func parseDirective(_ trimmed: String, line: Int) throws -> [String: String] {
        let remainder = String(trimmed.dropFirst("@plane".count)).trimmingCharacters(in: .whitespaces)
        return try tokenize(remainder, line: line).reduce(into: [:]) { result, token in
            guard let separator = token.firstIndex(of: "=") else {
                throw ParseError.invalidPlaneDirective(line: line, detail: "expected key=value, found '\(token)'")
            }
            let key = String(token[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = unquote(String(token[token.index(after: separator)...]).trimmingCharacters(in: .whitespaces))
            guard !key.isEmpty else {
                throw ParseError.invalidPlaneDirective(line: line, detail: "empty attribute key in '\(token)'")
            }
            result[key] = value
        }
    }

    // MARK: - Lexing Helpers

    private func firstToken(of line: String) -> String {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
    }

    /// Splits a directive remainder into tokens, keeping quoted spans intact.
    /// A backslash inside a quoted span escapes the next character, so `\"`
    /// does not close a double-quoted value. Throws on an unterminated quote.
    private func tokenize(_ input: String, line: Int) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var activeQuote: Character?
        var escaped = false

        for character in input {
            if let quote = activeQuote {
                current.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == quote {
                    activeQuote = nil
                }
            } else if character == "\"" || character == "'" {
                activeQuote = character
                current.append(character)
            } else if character == " " || character == "\t" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        guard activeQuote == nil else {
            throw ParseError.invalidPlaneDirective(line: line, detail: "unterminated quote in '\(input)'")
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last else { return value }
        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else { return value }
        return unescape(String(value.dropFirst().dropLast()))
    }

    /// Reverses the serializer's backslash escaping, so `\\` becomes `\` and
    /// `\"` becomes `"`. Any other escaped character yields the character
    /// itself. This makes a quoted value round-trip through the serializer.
    private func unescape(_ value: String) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping {
                result.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping { result.append("\\") }
        return result
    }

    /// Parses a finite decimal number for `z`/`x`/`y`: optional sign, digits with
    /// an optional fraction, and an optional exponent. Hex, `inf`, `nan`, and
    /// values that overflow to infinity are rejected, so the Swift and
    /// TypeScript parsers agree on the numeric grammar.
    private func parseFiniteDecimal(_ raw: String) -> Double? {
        let pattern = "^[+-]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?$"
        guard raw.range(of: pattern, options: .regularExpression) != nil else { return nil }
        guard let value = Double(raw), value.isFinite else { return nil }
        return value
    }

    /// Returns the fence character if a trimmed line opens a fenced code block
    /// (three or more backticks or tildes), otherwise `nil`.
    private func fenceCharacter(of trimmed: String) -> Character? {
        if trimmed.hasPrefix("```") { return "`" }
        if trimmed.hasPrefix("~~~") { return "~" }
        return nil
    }

    /// Joins body lines, dropping leading and trailing blank lines.
    /// Returns `nil` when nothing but whitespace remains.
    private func collapse(_ lines: [String]) -> String? {
        var slice = lines[...]
        while let first = slice.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            slice = slice.dropFirst()
        }
        while let last = slice.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            slice = slice.dropLast()
        }
        guard !slice.isEmpty else { return nil }
        return slice.joined(separator: "\n")
    }
}
