import XCTest

@testable import ThreeMD

// MARK: - MarkdownRendererTests

final class MarkdownRendererTests: XCTestCase {
    private let renderer = MarkdownRenderer()

    // MARK: - Headings

    func testH1() {
        let html = renderer.render("# Hello")
        XCTAssertEqual(html, "<h1>Hello</h1>")
    }

    func testH2() {
        let html = renderer.render("## Section")
        XCTAssertEqual(html, "<h2>Section</h2>")
    }

    func testH3() {
        let html = renderer.render("### Sub")
        XCTAssertEqual(html, "<h3>Sub</h3>")
    }

    func testH4() {
        let html = renderer.render("#### Deep")
        XCTAssertEqual(html, "<h4>Deep</h4>")
    }

    func testH5() {
        let html = renderer.render("##### Deeper")
        XCTAssertEqual(html, "<h5>Deeper</h5>")
    }

    func testH6() {
        let html = renderer.render("###### Deepest")
        XCTAssertEqual(html, "<h6>Deepest</h6>")
    }

    func testHeadingRequiresSpaceAfterHash() {
        // `#word` with no space is a paragraph, not an h1.
        let html = renderer.render("#NoSpace")
        XCTAssertTrue(html.contains("<p>"))
        XCTAssertFalse(html.contains("<h1>"))
    }

    // MARK: - Paragraphs

    func testSingleLineParagraph() {
        let html = renderer.render("Hello world")
        XCTAssertEqual(html, "<p>Hello world</p>")
    }

    func testMultiLineParagraphJoinsWithSpace() {
        let md = "Line one\nLine two"
        let html = renderer.render(md)
        XCTAssertEqual(html, "<p>Line one Line two</p>")
    }

    func testBlankLineSeparatesParagraphs() {
        let md = "First\n\nSecond"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<p>First</p>"))
        XCTAssertTrue(html.contains("<p>Second</p>"))
    }

    // MARK: - Unordered Lists

    func testUnorderedListDash() {
        let md = "- Alpha\n- Beta\n- Gamma"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>Alpha</li>"))
        XCTAssertTrue(html.contains("<li>Beta</li>"))
        XCTAssertTrue(html.contains("<li>Gamma</li>"))
        XCTAssertTrue(html.contains("</ul>"))
    }

    func testUnorderedListAsterisk() {
        let md = "* One\n* Two"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>One</li>"))
        XCTAssertTrue(html.contains("<li>Two</li>"))
    }

    // MARK: - Task Lists

    func testUncheckedTaskItem() {
        let md = "- [ ] Todo"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled>"))
        XCTAssertTrue(html.contains("Todo"))
    }

    func testCheckedTaskItemLowercase() {
        let md = "- [x] Done"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled checked>"))
        XCTAssertTrue(html.contains("Done"))
    }

    func testCheckedTaskItemUppercase() {
        let md = "- [X] Done"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled checked>"))
    }

    // MARK: - Ordered Lists

    func testOrderedList() {
        let md = "1. First\n2. Second\n3. Third"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertTrue(html.contains("<li>First</li>"))
        XCTAssertTrue(html.contains("<li>Second</li>"))
        XCTAssertTrue(html.contains("<li>Third</li>"))
        XCTAssertTrue(html.contains("</ol>"))
    }

    // MARK: - Fenced Code Blocks

    func testFencedCodeBlock() {
        let md = "```\nlet x = 1\nlet y = 2\n```"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<pre><code>"))
        XCTAssertTrue(html.contains("let x = 1"))
        XCTAssertTrue(html.contains("let y = 2"))
        XCTAssertTrue(html.contains("</code></pre>"))
    }

    func testFencedCodeBlockWithLanguage() {
        let md = "```swift\nfunc foo() {}\n```"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<pre><code>"))
        XCTAssertTrue(html.contains("func foo() {}"))
    }

    func testFencedCodeBlockPreservesMarkdownLookingContent() {
        // Markdown constructs inside a code fence must NOT be rendered as HTML.
        let md = "```\n# Not a heading\n**not bold**\n- not a list\n```"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("# Not a heading"))
        XCTAssertTrue(html.contains("**not bold**"))
        XCTAssertTrue(html.contains("- not a list"))
        XCTAssertFalse(html.contains("<h1>"))
        XCTAssertFalse(html.contains("<strong>"))
        XCTAssertFalse(html.contains("<ul>"))
    }

    func testFencedCodeBlockEscapesHTML() {
        let md = "```\n<script>alert('xss')</script>\n```"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
    }

    // MARK: - Blockquotes

    func testBlockquote() {
        let md = "> A wise saying."
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<blockquote>"))
        XCTAssertTrue(html.contains("A wise saying."))
        XCTAssertTrue(html.contains("</blockquote>"))
    }

    func testMultiLineBlockquote() {
        let md = "> Line one\n> Line two"
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<blockquote>"))
        XCTAssertTrue(html.contains("Line one"))
        XCTAssertTrue(html.contains("Line two"))
    }

    // MARK: - Bold

    func testBoldDoubleAsterisk() {
        let html = renderer.render("**bold**")
        XCTAssertEqual(html, "<p><strong>bold</strong></p>")
    }

    func testBoldDoubleUnderscore() {
        let html = renderer.render("__bold__")
        XCTAssertEqual(html, "<p><strong>bold</strong></p>")
    }

    func testBoldMidSentence() {
        let html = renderer.render("This is **very** important")
        XCTAssertTrue(html.contains("<strong>very</strong>"))
    }

    // MARK: - Italic

    func testItalicAsterisk() {
        let html = renderer.render("*italic*")
        XCTAssertEqual(html, "<p><em>italic</em></p>")
    }

    func testItalicUnderscore() {
        let html = renderer.render("_italic_")
        XCTAssertEqual(html, "<p><em>italic</em></p>")
    }

    // MARK: - Inline Code

    func testInlineCode() {
        let html = renderer.render("`someFunc()`")
        XCTAssertEqual(html, "<p><code>someFunc()</code></p>")
    }

    func testInlineCodeEscapesHTML() {
        let html = renderer.render("`<script>`")
        XCTAssertTrue(html.contains("<code>&lt;script&gt;</code>"))
        XCTAssertFalse(html.contains("<script>"))
    }

    func testInlineCodeDoesNotRenderMarkdown() {
        // Bold markers inside backticks must be verbatim.
        let html = renderer.render("`**not bold**`")
        XCTAssertTrue(html.contains("<code>**not bold**</code>"))
        XCTAssertFalse(html.contains("<strong>"))
    }

    // MARK: - Links

    func testLink() {
        let html = renderer.render("[Swift](https://swift.org)")
        XCTAssertTrue(html.contains("<a href=\"https://swift.org\">Swift</a>"))
    }

    func testLinkHrefIsEscaped() {
        let html = renderer.render("[click](https://example.com/path?a=1&b=2)")
        XCTAssertTrue(html.contains("href=\"https://example.com/path?a=1&amp;b=2\""))
    }

    func testLinkTextIsEscaped() {
        let html = renderer.render("[Tom & Jerry](https://example.com)")
        XCTAssertTrue(html.contains(">Tom &amp; Jerry<"))
    }

    // MARK: - HTML Escaping (plain text)

    func testAmpersandInParagraphIsEscaped() {
        let html = renderer.render("AT&T")
        XCTAssertTrue(html.contains("AT&amp;T"))
    }

    func testLessThanInParagraphIsEscaped() {
        let html = renderer.render("<not a tag>")
        XCTAssertTrue(html.contains("&lt;not a tag&gt;"))
    }

    func testDoubleQuoteInParagraphIsEscaped() {
        let html = renderer.render("He said \"hello\"")
        XCTAssertTrue(html.contains("He said &quot;hello&quot;"))
    }

    func testSingleQuoteInParagraphIsEscaped() {
        let html = renderer.render("it's fine")
        XCTAssertTrue(html.contains("it&#39;s fine"))
    }

    // MARK: - Mixed content

    func testHeadingFollowedByParagraph() {
        let md = "# Title\n\nSome body text."
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<p>Some body text.</p>"))
    }

    func testParagraphWithBoldAndLink() {
        let md = "See **[Swift](https://swift.org)** for details."
        let html = renderer.render(md)
        XCTAssertTrue(html.contains("<strong>"))
        XCTAssertTrue(html.contains("<a href=\"https://swift.org\">Swift</a>"))
    }
}
