@preconcurrency import Foundation


// MARK: - Serializer

/// Renders a ``Document`` back into 3md source text.
///
/// The output round-trips through ``Parser``: parsing serialized text yields an
/// equivalent document.
public struct Serializer: Sendable {
    // MARK: - Initializers

    /// Creates a serializer.
    public init() {}

    // MARK: - Public Methods

    /// Renders a document to 3md source text.
    /// - Parameter document: The document to render.
    /// - Returns: The serialized `.3md` contents.
    public func render(_ document: Document) -> String {
        var lines = frontmatterLines(for: document)

        if let preamble = document.preamble {
            lines.append("")
            lines.append(preamble)
        }

        for plane in document.planes {
            lines.append("")
            lines.append(directiveLine(for: plane))
            if !plane.body.isEmpty {
                lines.append(plane.body)
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private Methods

    private func frontmatterLines(for document: Document) -> [String] {
        var lines = ["---", "3md: \(document.version)", "axis: \(document.axis.rawValue)"]

        if let title = document.title {
            lines.append("title: \(quoteIfNeeded(title))")
        }

        let extraLines = document.metadata.keys.sorted().map { key in
            "\(key): \(quoteIfNeeded(document.metadata[key] ?? ""))"
        }
        lines.append(contentsOf: extraLines)
        lines.append("---")

        return lines
    }

    private func directiveLine(for plane: Plane) -> String {
        var parts = ["@plane", "z=\(format(plane.z))"]

        if let label = plane.label {
            parts.append("label=\(quoteIfNeeded(label, forceQuote: true))")
        }
        if let x = plane.x {
            parts.append("x=\(format(x))")
        }
        if let y = plane.y {
            parts.append("y=\(format(y))")
        }

        let extraParts = plane.attributes.keys.sorted().map { key in
            "\(key)=\(quoteIfNeeded(plane.attributes[key] ?? "", forceQuote: true))"
        }
        parts.append(contentsOf: extraParts)

        return parts.joined(separator: " ")
    }

    /// Formats a `Double` as an integer string when the value is whole and in range,
    /// falling back to the default decimal representation otherwise.
    private func format(_ value: Double) -> String {
        guard value == value.rounded(), abs(value) < 1e15 else { return String(value) }
        return String(Int(value))
    }

    /// Wraps `value` in double quotes if it contains whitespace, is empty, or
    /// if `forceQuote` is `true`. Embedded double-quotes are escaped.
    private func quoteIfNeeded(_ value: String, forceQuote: Bool = false) -> String {
        let needsQuote = forceQuote || value.contains(" ") || value.contains("\t") || value.isEmpty
        guard needsQuote else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
