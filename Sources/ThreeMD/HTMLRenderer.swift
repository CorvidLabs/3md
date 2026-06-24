@preconcurrency import Foundation


// MARK: - HTMLRenderer

/// Renders a ``Document`` as a clean, accessible, standalone HTML document.
///
/// Each plane becomes a semantic `<section>` element carrying a `data-z`
/// attribute, the plane's label as a heading, and the Markdown body in a
/// `<pre>` block. The body text is HTML-escaped to prevent injection. No
/// Markdown rendering is performed; the raw body is presented verbatim inside
/// `<pre>`.
///
/// The renderer is stateless and safe to call from multiple concurrent contexts.
public struct HTMLRenderer: Sendable {

    // MARK: - Initializers

    /// Creates an HTML renderer.
    public init() {}

    // MARK: - Public Methods

    /// Renders a document to a standalone HTML string.
    ///
    /// The output is a complete HTML5 document with:
    /// - A `<meta charset>` and viewport declaration.
    /// - The document title as both `<title>` and `<h1>`.
    /// - The axis and version surfaced in `<meta>` elements.
    /// - One `<section data-z="...">` per plane, in source order.
    ///
    /// - Parameter document: The document to render.
    /// - Returns: A self-contained HTML5 string.
    public func render(_ document: Document) -> String {
        var lines: [String] = []

        lines.append("<!DOCTYPE html>")
        lines.append("<html lang=\"en\">")
        lines.append("<head>")
        lines.append("<meta charset=\"utf-8\">")
        lines.append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
        lines.append("<meta name=\"generator\" content=\"ThreeMD\">")
        lines.append("<meta name=\"3md-version\" content=\"\(escape(document.version))\">")
        lines.append("<meta name=\"3md-axis\" content=\"\(escape(document.axis.rawValue))\">")

        let titleText = document.title ?? "3md Document"
        lines.append("<title>\(escape(titleText))</title>")
        lines.append("</head>")
        lines.append("<body>")
        lines.append("<header>")
        lines.append("<h1>\(escape(titleText))</h1>")
        lines.append("<p>Axis: <code>\(escape(document.axis.rawValue))</code></p>")
        lines.append("</header>")
        lines.append("<main>")

        if let preamble = document.preamble {
            lines.append("<section class=\"preamble\">")
            lines.append("<pre>\(escape(preamble))</pre>")
            lines.append("</section>")
        }

        for plane in document.planes {
            lines.append(contentsOf: planeSection(for: plane))
        }

        lines.append("</main>")
        lines.append("</body>")
        lines.append("</html>")

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private Methods

    /// Builds the HTML lines for a single plane section.
    /// - Parameter plane: The plane to render.
    /// - Returns: Lines of HTML for a `<section>` element.
    private func planeSection(for plane: Plane) -> [String] {
        var lines: [String] = []
        let zFormatted = formatZ(plane.z)

        var openTag = "<section data-z=\"\(escape(zFormatted))\""
        if let label = plane.label {
            openTag += " aria-label=\"\(escape(label))\""
        }
        openTag += ">"
        lines.append(openTag)

        if let label = plane.label {
            lines.append("<h2>\(escape(label))</h2>")
        } else {
            lines.append("<h2>Plane \(escape(zFormatted))</h2>")
        }

        if !plane.body.isEmpty {
            lines.append("<pre>\(escape(plane.body))</pre>")
        }

        lines.append("</section>")
        return lines
    }

    /// Escapes a string for safe embedding in HTML text or attribute values.
    ///
    /// Replaces the five characters that carry special meaning in HTML:
    /// `&`, `<`, `>`, `"`, and `'`.
    ///
    /// - Parameter string: The raw string to escape.
    /// - Returns: An HTML-safe string.
    private func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Formats a `Double` z position as a compact string, using integer form
    /// when the value is whole and within safe range.
    ///
    /// - Parameter value: The z position to format.
    /// - Returns: A string representation.
    private func formatZ(_ value: Double) -> String {
        guard value == value.rounded(), abs(value) < 1e15 else { return String(value) }
        return String(Int(value))
    }
}
