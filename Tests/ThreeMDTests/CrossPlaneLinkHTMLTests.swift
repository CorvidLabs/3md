import XCTest

@testable import ThreeMD

/// Tests for cross-plane link rendering in ``MarkdownRenderer`` and section ID
/// generation in ``HTMLRenderer``.
final class CrossPlaneLinkHTMLTests: XCTestCase {
    private let markdownRenderer = MarkdownRenderer()
    private let htmlRenderer = HTMLRenderer()
    private let parser = Parser()

    // MARK: - Section ID generation

    func testSectionHasIdAttribute() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=42
            body
            """
        let document = try parser.parse(source)
        let html = htmlRenderer.render(document)
        XCTAssertTrue(html.contains("id=\"plane-z-42\""), "Expected id attribute for z=42")
    }

    func testSectionIdForDecimalZ() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=1.5
            body
            """
        let document = try parser.parse(source)
        let html = htmlRenderer.render(document)
        XCTAssertTrue(html.contains("id=\"plane-z-1.5\""), "Expected id attribute for z=1.5")
    }

    func testSectionIdForNegativeZ() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=-2
            body
            """
        let document = try parser.parse(source)
        let html = htmlRenderer.render(document)
        XCTAssertTrue(html.contains("id=\"plane-z--2\""), "Expected id attribute for z=-2")
    }

    func testSectionIdPrecedesDataZ() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            body
            """
        let document = try parser.parse(source)
        let html = htmlRenderer.render(document)
        // id must appear before data-z in the opening tag
        let idRange = html.range(of: "id=\"plane-z-0\"")
        let dataZRange = html.range(of: "data-z=\"0\"")
        XCTAssertNotNil(idRange)
        XCTAssertNotNil(dataZRange)
        if let id = idRange, let dz = dataZRange {
            XCTAssertLessThan(id.lowerBound, dz.lowerBound)
        }
    }

    // MARK: - Inline anchor rendering (no text)

    func testCrossPlaneAnchorNoText() {
        let html = markdownRenderer.render("see [[z=2]]")
        XCTAssertTrue(
            html.contains("<a href=\"#plane-z-2\">z=2</a>"),
            "Expected default anchor label 'z=2', got: \(html)"
        )
    }

    func testCrossPlaneAnchorWithText() {
        let html = markdownRenderer.render("[[z=0|back to start]]")
        XCTAssertTrue(
            html.contains("<a href=\"#plane-z-0\">back to start</a>"),
            "Expected anchor with link text, got: \(html)"
        )
    }

    func testCrossPlaneAnchorEmptyText() {
        let html = markdownRenderer.render("[[z=1|]]")
        XCTAssertTrue(
            html.contains("<a href=\"#plane-z-1\"></a>"),
            "Expected anchor with empty display text, got: \(html)"
        )
    }

    func testCrossPlaneAnchorDecimalTarget() {
        let html = markdownRenderer.render("[[z=1.5]]")
        XCTAssertTrue(
            html.contains("<a href=\"#plane-z-1.5\">z=1.5</a>"),
            "Expected anchor with decimal target, got: \(html)"
        )
    }

    func testCrossPlaneAnchorNegativeTarget() {
        let html = markdownRenderer.render("[[z=-1]]")
        XCTAssertTrue(
            html.contains("<a href=\"#plane-z--1\">z=-1</a>"),
            "Expected anchor with negative target, got: \(html)"
        )
    }

    func testCrossPlaneAnchorScientificNotation() {
        // 1e3 rounds to whole number, so formatted as "1000"
        let html = markdownRenderer.render("[[z=1e3]]")
        XCTAssertTrue(
            html.contains("<a href=\"#plane-z-1000\">z=1000</a>"),
            "Expected scientific notation normalized in anchor, got: \(html)"
        )
    }

    // MARK: - HTML escaping in anchors

    func testCrossPlaneAnchorTextIsEscaped() {
        let html = markdownRenderer.render("[[z=0|a & b]]")
        XCTAssertTrue(
            html.contains("a &amp; b"),
            "Expected ampersand escaped in link text, got: \(html)"
        )
    }

    func testCrossPlaneAnchorDefaultTextIsEscaped() {
        // "z=0" does not contain special HTML characters, but confirm escaping path
        let html = markdownRenderer.render("[[z=0]]")
        XCTAssertTrue(html.contains("z=0</a>"), "Expected label 'z=0', got: \(html)")
    }

    // MARK: - Invalid targets left as literal text

    func testInvalidTargetNotRenderedAsAnchor() {
        let html = markdownRenderer.render("[[z=abc]]")
        XCTAssertFalse(html.contains("<a "), "Expected no anchor for invalid target, got: \(html)")
    }

    func testHexTargetNotRenderedAsAnchor() {
        let html = markdownRenderer.render("[[z=0xFF]]")
        XCTAssertFalse(html.contains("<a "), "Expected no anchor for hex target, got: \(html)")
    }

    func testInfTargetNotRenderedAsAnchor() {
        let html = markdownRenderer.render("[[z=inf]]")
        XCTAssertFalse(html.contains("<a "), "Expected no anchor for inf target, got: \(html)")
    }

    // MARK: - Anchors resolve to section IDs in full document

    func testAnchorHrefMatchesSectionId() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            see [[z=1]] for details

            @plane z=1
            details
            """
        let document = try parser.parse(source)
        let html = htmlRenderer.render(document)
        XCTAssertTrue(
            html.contains("<a href=\"#plane-z-1\">z=1</a>"),
            "Expected anchor pointing to #plane-z-1, got excerpt: \(String(html.prefix(2000)))"
        )
        XCTAssertTrue(
            html.contains("id=\"plane-z-1\""),
            "Expected section with id='plane-z-1'"
        )
    }
}
