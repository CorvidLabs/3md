// MARK: - MarkdownRenderer

/// Converts a CommonMark subset of Markdown to HTML.
///
/// This renderer handles the constructs that appear most often in 3md plane bodies:
/// headings, paragraphs, lists (ordered, unordered, and task), blockquotes,
/// fenced code blocks, and the most common inline styles. It is intentionally
/// a *subset* implementation: constructs not listed below are treated as plain
/// paragraph text, which is always safe to render.
///
/// ## Supported block constructs
/// - ATX headings (`#` through `######`) -> `<h1>` through `<h6>`
/// - Paragraphs separated by blank lines
/// - Unordered lists (`-` or `*` prefix) -> `<ul><li>`
/// - Ordered lists (`1.` prefix) -> `<ol><li>`
/// - Task list items (`- [ ]` / `- [x]`) -> a checkbox `<input disabled>` glyph
/// - Fenced code blocks (``` ... ```) -> `<pre><code>` (content is verbatim and escaped)
/// - Blockquotes (`>` prefix) -> `<blockquote>`
///
/// ## Supported inline constructs
/// - Bold: `**text**` or `__text__`
/// - Italic: `*text*` or `_text_`
/// - Inline code: `` `code` ``
/// - Links: `[text](url)`
/// - Cross-plane links: `[[z=N]]` or `[[z=N|text]]` -> `<a href="#plane-z-F">TEXT</a>`
///
/// ## Safety
/// All text content and link hrefs are HTML-escaped. Fenced code block contents
/// are escaped and never re-parsed as Markdown.
///
/// The renderer is stateless and safe to call from multiple concurrent contexts.
public struct MarkdownRenderer: Sendable {

    // MARK: - Initializers

    /// Creates a Markdown renderer.
    public init() {}

    // MARK: - Public Methods

    /// Renders a Markdown string to an HTML fragment.
    ///
    /// The output is an HTML fragment (not a full document). Block elements are
    /// separated by newlines. Text not matching any supported construct is wrapped
    /// in a `<p>` element.
    ///
    /// - Parameter markdown: The Markdown source to render.
    /// - Returns: An HTML fragment string.
    public func render(_ markdown: String) -> String {
        let blocks = parseBlocks(markdown)
        return blocks.map { renderBlock($0) }.joined(separator: "\n")
    }

    // MARK: - Private Types

    /// A parsed block-level element.
    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(lines: [String])
        case unorderedList(items: [ListItem])
        case orderedList(items: [ListItem])
        case fencedCode(language: String?, content: String)
        case blockquote(lines: [String])
    }

    /// A list item, which may be a task item.
    private struct ListItem {
        /// Whether this item has a checkbox marker (task list).
        let isTask: Bool
        /// Whether the task checkbox is checked.
        let isChecked: Bool
        /// The item text after stripping list markers.
        let text: String
    }

    // MARK: - Block Parsing

    /// Parses raw Markdown text into an array of block elements.
    /// - Parameter markdown: The raw Markdown source.
    /// - Returns: The parsed block elements.
    private func parseBlocks(_ markdown: String) -> [Block] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [Block] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip blank lines between blocks.
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                let (block, next) = parseFencedCode(lines: lines, from: index)
                blocks.append(block)
                index = next
                continue
            }

            // ATX heading.
            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            // Blockquote.
            if trimmed.hasPrefix(">") {
                let (block, next) = parseBlockquote(lines: lines, from: index)
                blocks.append(block)
                index = next
                continue
            }

            // Unordered list.
            if isUnorderedListMarker(trimmed) {
                let (block, next) = parseUnorderedList(lines: lines, from: index)
                blocks.append(block)
                index = next
                continue
            }

            // Ordered list.
            if isOrderedListMarker(trimmed) {
                let (block, next) = parseOrderedList(lines: lines, from: index)
                blocks.append(block)
                index = next
                continue
            }

            // Paragraph: accumulate until blank line or block-level element.
            let (block, next) = parseParagraph(lines: lines, from: index)
            blocks.append(block)
            index = next
        }

        return blocks
    }

    /// Parses a fenced code block starting at `startIndex`.
    ///
    /// - Parameters:
    ///   - lines: All document lines.
    ///   - startIndex: The index of the opening fence line.
    /// - Returns: The parsed block and the index of the first line after the block.
    private func parseFencedCode(lines: [String], from startIndex: Int) -> (Block, Int) {
        let openingFence = lines[startIndex].trimmingCharacters(in: .whitespaces)
        // The language hint is whatever follows the triple backtick.
        let afterBackticks = String(openingFence.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let language: String? = afterBackticks.isEmpty ? nil : afterBackticks

        var contentLines: [String] = []
        var index = startIndex + 1

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                // Closing fence found; advance past it.
                index += 1
                break
            }
            contentLines.append(lines[index])
            index += 1
        }

        let content = contentLines.joined(separator: "\n")
        return (.fencedCode(language: language, content: content), index)
    }

    /// Attempts to parse an ATX heading from a trimmed line.
    ///
    /// - Parameter line: A whitespace-trimmed line.
    /// - Returns: A heading block, or `nil` if the line is not a heading.
    private func parseHeading(_ line: String) -> Block? {
        guard line.hasPrefix("#") else { return nil }

        var level = 0
        var rest = line[line.startIndex...]

        while rest.first == "#" && level < 6 {
            level += 1
            rest = rest.dropFirst()
        }

        // Must have a space after the hashes (or the line is only hashes).
        guard rest.first == " " || rest.isEmpty else { return nil }

        let text = String(rest).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    /// Parses a blockquote block starting at `startIndex`.
    ///
    /// - Parameters:
    ///   - lines: All document lines.
    ///   - startIndex: The index of the first `>` line.
    /// - Returns: The parsed block and the index of the first line after the block.
    private func parseBlockquote(lines: [String], from startIndex: Int) -> (Block, Int) {
        var quoteLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            guard trimmed.hasPrefix(">") else { break }

            // Strip the `>` prefix and optional following space.
            var stripped = String(trimmed.dropFirst())
            if stripped.hasPrefix(" ") {
                stripped = String(stripped.dropFirst())
            }
            quoteLines.append(stripped)
            index += 1
        }

        return (.blockquote(lines: quoteLines), index)
    }

    /// Returns `true` when a trimmed line begins an unordered list item.
    /// - Parameter line: A whitespace-trimmed line.
    private func isUnorderedListMarker(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ")
    }

    /// Returns `true` when a trimmed line begins an ordered list item.
    /// - Parameter line: A whitespace-trimmed line.
    private func isOrderedListMarker(_ line: String) -> Bool {
        // Match one or more digits followed by `.` and a space.
        guard let dotIndex = line.firstIndex(of: ".") else { return false }
        let prefix = line[line.startIndex..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }) else { return false }
        let afterDot = line.index(after: dotIndex)
        return afterDot < line.endIndex && line[afterDot] == " "
    }

    /// Parses an unordered list starting at `startIndex`.
    ///
    /// - Parameters:
    ///   - lines: All document lines.
    ///   - startIndex: The index of the first list item line.
    /// - Returns: The parsed block and the index of the first line after the list.
    private func parseUnorderedList(lines: [String], from startIndex: Int) -> (Block, Int) {
        var items: [ListItem] = []
        var index = startIndex

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard isUnorderedListMarker(trimmed) else { break }

            // Strip the `- ` or `* ` prefix.
            let afterMarker = String(trimmed.dropFirst(2))
            items.append(parseListItem(afterMarker))
            index += 1
        }

        return (.unorderedList(items: items), index)
    }

    /// Parses an ordered list starting at `startIndex`.
    ///
    /// - Parameters:
    ///   - lines: All document lines.
    ///   - startIndex: The index of the first list item line.
    /// - Returns: The parsed block and the index of the first line after the list.
    private func parseOrderedList(lines: [String], from startIndex: Int) -> (Block, Int) {
        var items: [ListItem] = []
        var index = startIndex

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard isOrderedListMarker(trimmed) else { break }

            // Strip up to and including the `. ` after the number.
            guard let dotIndex = trimmed.firstIndex(of: ".") else { break }
            let afterDot = trimmed.index(dotIndex, offsetBy: 2)
            let afterMarker = String(trimmed[afterDot...])
            items.append(parseListItem(afterMarker))
            index += 1
        }

        return (.orderedList(items: items), index)
    }

    /// Parses a single list item from text that already has the list marker stripped.
    ///
    /// - Parameter text: The item text after the `- ` / `* ` / `N. ` prefix.
    /// - Returns: A `ListItem` with task-checkbox metadata if applicable.
    private func parseListItem(_ text: String) -> ListItem {
        if text.hasPrefix("[ ] ") {
            return ListItem(isTask: true, isChecked: false, text: String(text.dropFirst(4)))
        }
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            return ListItem(isTask: true, isChecked: true, text: String(text.dropFirst(4)))
        }
        return ListItem(isTask: false, isChecked: false, text: text)
    }

    /// Parses a paragraph starting at `startIndex`, stopping at blank lines or
    /// block-level constructs.
    ///
    /// - Parameters:
    ///   - lines: All document lines.
    ///   - startIndex: The index of the first line of the paragraph.
    /// - Returns: The parsed block and the index of the first line after the block.
    private func parseParagraph(lines: [String], from startIndex: Int) -> (Block, Int) {
        var paragraphLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { break }
            if trimmed.hasPrefix("```") { break }
            if parseHeading(trimmed) != nil { break }
            if trimmed.hasPrefix(">") { break }
            if isUnorderedListMarker(trimmed) { break }
            if isOrderedListMarker(trimmed) { break }

            paragraphLines.append(trimmed)
            index += 1
        }

        return (.paragraph(lines: paragraphLines), index)
    }

    // MARK: - Block Rendering

    /// Converts a parsed block element to an HTML string.
    /// - Parameter block: The block to render.
    /// - Returns: An HTML string for the block.
    private func renderBlock(_ block: Block) -> String {
        switch block {
        case .heading(let level, let text):
            return "<h\(level)>\(renderInline(text))</h\(level)>"

        case .paragraph(let lines):
            let rendered = lines.map { renderInline($0) }.joined(separator: " ")
            return "<p>\(rendered)</p>"

        case .unorderedList(let items):
            let rendered = items.map { renderListItem($0) }.joined(separator: "\n")
            return "<ul>\n\(rendered)\n</ul>"

        case .orderedList(let items):
            let rendered = items.map { renderListItem($0) }.joined(separator: "\n")
            return "<ol>\n\(rendered)\n</ol>"

        case .fencedCode(_, let content):
            // Content is verbatim: escape only, never re-parse.
            return "<pre><code>\(escape(content))</code></pre>"

        case .blockquote(let lines):
            let inner = lines.map { renderInline($0) }.joined(separator: "\n")
            return "<blockquote>\(inner)</blockquote>"
        }
    }

    /// Renders a single list item to an HTML `<li>` string.
    /// - Parameter item: The list item to render.
    /// - Returns: An HTML `<li>` string.
    private func renderListItem(_ item: ListItem) -> String {
        if item.isTask {
            let checked = item.isChecked ? " checked" : ""
            let checkbox = "<input type=\"checkbox\" disabled\(checked)> "
            return "<li>\(checkbox)\(renderInline(item.text))</li>"
        }
        return "<li>\(renderInline(item.text))</li>"
    }

    // MARK: - Inline Rendering

    /// Converts a line of Markdown text to an HTML string by processing inline
    /// constructs in a single left-to-right pass.
    ///
    /// The pass identifies the leftmost inline delimiter at each position and
    /// emits the corresponding HTML. All plain-text characters are HTML-escaped
    /// as they are emitted. Inline code content is escaped verbatim (never
    /// re-parsed). Bold and italic are processed greedily: the first matching
    /// close delimiter wins.
    ///
    /// Processing order (by leftmost match):
    /// 1. Inline code: `` `...` ``
    /// 2. Bold: `**...**` or `__...__`
    /// 3. Italic: `*...*` or `_..._`
    /// 4. Links: `[text](url)`
    ///
    /// - Parameter text: A single line of Markdown text.
    /// - Returns: The line with inline constructs replaced by HTML and plain text escaped.
    private func renderInline(_ text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]

            // Inline code: `` `code` ``.
            if char == "`" {
                let afterTick = text.index(after: index)
                if afterTick < text.endIndex,
                    let closeTick = text[afterTick...].firstIndex(of: "`")
                {
                    let codeContent = String(text[afterTick..<closeTick])
                    result += "<code>\(escape(codeContent))</code>"
                    index = text.index(after: closeTick)
                    continue
                }
            }

            // Bold: **text** (two-character delimiter, must check before single *).
            if char == "*" || char == "_" {
                let next = text.index(after: index)
                if next < text.endIndex && text[next] == char {
                    let delimiter = String(repeating: char, count: 2)
                    let searchStart = text.index(after: next)
                    if searchStart < text.endIndex,
                        let closeRange = text.range(of: delimiter, range: searchStart..<text.endIndex)
                    {
                        let inner = renderInline(String(text[searchStart..<closeRange.lowerBound]))
                        result += "<strong>\(inner)</strong>"
                        index = closeRange.upperBound
                        continue
                    }
                }
            }

            // Italic: *text* or _text_ (single-character delimiter).
            if char == "*" || char == "_" {
                let searchStart = text.index(after: index)
                if searchStart < text.endIndex,
                    let closeIndex = text[searchStart...].firstIndex(of: char)
                {
                    let inner = renderInline(String(text[searchStart..<closeIndex]))
                    result += "<em>\(inner)</em>"
                    index = text.index(after: closeIndex)
                    continue
                }
            }

            // Cross-plane links: [[z=N]] or [[z=N|text]].
            // Must be checked before the ordinary Markdown link rule because both
            // start with `[`. A `[[z=N]]` whose target is not a finite decimal is
            // left as literal body text (the `[[` falls through to plain-char emit).
            if char == "[" {
                let afterFirst = text.index(after: index)
                if afterFirst < text.endIndex, text[afterFirst] == "[" {
                    let afterSecond = text.index(after: afterFirst)
                    if afterSecond < text.endIndex, text[afterSecond...].hasPrefix("z=") {
                        if let (anchor, endIndex) = parseCrossPlaneLink(in: text, from: index) {
                            result += anchor
                            index = endIndex
                            continue
                        }
                    }
                }
            }

            // Links: [text](url).
            if char == "[" {
                let afterBracket = text.index(after: index)
                if let closeBracket = text[afterBracket...].firstIndex(of: "]") {
                    let afterCloseBracket = text.index(after: closeBracket)
                    if afterCloseBracket < text.endIndex,
                        text[afterCloseBracket] == "(",
                        let closeParen = text[afterCloseBracket...].firstIndex(of: ")")
                    {
                        let linkText = String(text[afterBracket..<closeBracket])
                        let urlStart = text.index(after: afterCloseBracket)
                        let url = String(text[urlStart..<closeParen])
                        result += "<a href=\"\(escape(url))\">\(escape(linkText))</a>"
                        index = text.index(after: closeParen)
                        continue
                    }
                }
            }

            // Plain character: emit HTML-escaped.
            result += escapeChar(char)
            index = text.index(after: index)
        }

        return result
    }

    /// Attempts to parse a `[[z=N]]` or `[[z=N|text]]` cross-plane link starting
    /// at `start` in `text`.
    ///
    /// Returns the rendered `<a>` anchor and the index just past `]]` on success,
    /// or `nil` when the sequence is not a valid cross-plane link (invalid decimal
    /// target, malformed brackets, etc.).
    ///
    /// - Parameters:
    ///   - text: The full inline text being parsed.
    ///   - start: The index of the opening `[`.
    /// - Returns: The HTML anchor string and end index, or `nil`.
    private func parseCrossPlaneLink(in text: String, from start: String.Index) -> (String, String.Index)? {
        // We already verified text[start] == "[" and text[start+1] == "[".
        // Move past "[[z=".
        guard
            let zEqStart = text.index(start, offsetBy: 4, limitedBy: text.endIndex),
            zEqStart <= text.endIndex
        else { return nil }

        // Scan for the first `|` or `]` to delimit the target token.
        var scanIndex = zEqStart
        while scanIndex < text.endIndex, text[scanIndex] != "|", text[scanIndex] != "]" {
            scanIndex = text.index(after: scanIndex)
        }

        guard scanIndex < text.endIndex else { return nil }

        let targetRaw = String(text[zEqStart..<scanIndex])
        guard !targetRaw.isEmpty, let targetZ = parseFiniteDecimalInLink(targetRaw) else { return nil }

        let linkText: String?
        let afterTarget: String.Index

        if text[scanIndex] == "|" {
            // Optional text after pipe: collect until `]`.
            afterTarget = text.index(after: scanIndex)
            var pipeEnd = afterTarget
            while pipeEnd < text.endIndex, text[pipeEnd] != "]" {
                pipeEnd = text.index(after: pipeEnd)
            }
            guard pipeEnd < text.endIndex else { return nil }
            linkText = String(text[afterTarget..<pipeEnd])
            scanIndex = pipeEnd
        } else {
            linkText = nil
        }

        // Expect `]]` closing.
        guard
            scanIndex < text.endIndex, text[scanIndex] == "]",
            let nextIndex = text.index(scanIndex, offsetBy: 1, limitedBy: text.endIndex),
            nextIndex < text.endIndex, text[nextIndex] == "]"
        else { return nil }

        let endIndex = text.index(after: nextIndex)
        let formatted = targetZ.formatted3MD()
        let displayText = linkText.map { escape($0) } ?? "z=\(escape(formatted))"
        let anchor = "<a href=\"#plane-z-\(escape(formatted))\">\(displayText)</a>"
        return (anchor, endIndex)
    }

    /// Validates and parses a finite decimal from a link target capture group.
    ///
    /// Mirrors the grammar used by ``Parser`` for the `z` attribute.
    private func parseFiniteDecimalInLink(_ raw: String) -> Double? {
        let pattern = #"^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$"#
        guard raw.range(of: pattern, options: .regularExpression) != nil else { return nil }
        guard let value = Double(raw), value.isFinite else { return nil }
        return value
    }

    // MARK: - HTML Escaping

    /// Escapes a single character for safe embedding in HTML text content.
    ///
    /// Only the characters with special HTML meaning are replaced; all other
    /// characters are returned as a one-character string.
    ///
    /// - Parameter char: The character to escape.
    /// - Returns: The HTML-safe representation of the character.
    private func escapeChar(_ char: Character) -> String {
        switch char {
        case "&": return "&amp;"
        case "<": return "&lt;"
        case ">": return "&gt;"
        case "\"": return "&quot;"
        case "'": return "&#39;"
        default: return String(char)
        }
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
}
