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
        var parts = ["@plane", "z=\(plane.z.formatted3MD())"]

        if let label = plane.label {
            parts.append("label=\(quoteIfNeeded(label, forceQuote: true))")
        }
        if let x = plane.x {
            parts.append("x=\(x.formatted3MD())")
        }
        if let y = plane.y {
            parts.append("y=\(y.formatted3MD())")
        }

        let extraParts = plane.attributes.keys.sorted().map { key in
            "\(key)=\(quoteIfNeeded(plane.attributes[key] ?? "", forceQuote: true))"
        }
        parts.append(contentsOf: extraParts)

        return parts.joined(separator: " ")
    }

    /// Wraps `value` in double quotes if it contains whitespace, a quote, a
    /// backslash, or is empty (or if `forceQuote` is `true`). Backslashes and
    /// double-quotes are escaped so the value round-trips through ``Parser``.
    private func quoteIfNeeded(_ value: String, forceQuote: Bool = false) -> String {
        let needsQuote =
            forceQuote || value.contains(" ") || value.contains("\t")
            || value.contains("\"") || value.contains("\\") || value.isEmpty
        guard needsQuote else { return value }
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
