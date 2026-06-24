import XCTest

@testable import ThreeMD

final class HTMLRendererTests: XCTestCase {
    private let renderer = HTMLRenderer()
    private let parser = Parser()

    // MARK: - Structure

    func testOutputIsStandaloneHTML() throws {
        let document = try singlePlaneDocument()
        let html = renderer.render(document)
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<html lang=\"en\">"))
        XCTAssertTrue(html.contains("</html>"))
    }

    func testOutputContainsHeadAndBody() throws {
        let document = try singlePlaneDocument()
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("<head>"))
        XCTAssertTrue(html.contains("</head>"))
        XCTAssertTrue(html.contains("<body>"))
        XCTAssertTrue(html.contains("</body>"))
    }

    func testPlaneCountMatchesSections() throws {
        let source = """
            ---
            3md: 0.1
            axis: time
            ---
            @plane z=0 label="Monday"
            # Monday

            @plane z=1 label="Tuesday"
            # Tuesday

            @plane z=2 label="Wednesday"
            # Wednesday
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        let sectionCount = html.components(separatedBy: "<section data-z=").count - 1
        XCTAssertEqual(sectionCount, 3)
    }

    func testSectionCarriesDataZ() throws {
        let source = """
            ---
            3md: 0.1
            axis: frame
            ---
            @plane z=42
            body
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("data-z=\"42\""))
    }

    func testSectionCarriesAriaLabel() throws {
        let source = """
            ---
            3md: 0.1
            axis: time
            ---
            @plane z=0 label="Monday"
            # Monday
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("aria-label=\"Monday\""))
    }

    func testLabelRenderedAsHeading() throws {
        let source = """
            ---
            3md: 0.1
            axis: time
            ---
            @plane z=0 label="Sprint Start"
            content
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("<h2>Sprint Start</h2>"))
    }

    func testBodyRenderedAsMarkdown() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            Hello world
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("<p>Hello world</p>"))
    }

    // MARK: - Axis and Title

    func testAxisEmittedInMeta() throws {
        let source = """
            ---
            3md: 0.1
            axis: depth
            ---
            @plane z=0
            body
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("content=\"depth\""))
    }

    func testTitleEmittedInTitleElement() throws {
        let source = """
            ---
            3md: 0.1
            title: My Document
            ---
            @plane z=0
            body
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("<title>My Document</title>"))
    }

    func testTitleEmittedInH1() throws {
        let source = """
            ---
            3md: 0.1
            title: My Document
            ---
            @plane z=0
            body
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("<h1>My Document</h1>"))
    }

    func testVersionEmittedInMeta() throws {
        let document = try singlePlaneDocument()
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("content=\"0.1\""))
    }

    func testMissingTitleFallsBackToDefault() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            body
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("<title>3md Document</title>"))
    }

    // MARK: - HTML Escaping

    func testAmpersandEscaped() throws {
        let html = renderer.render(documentWithBody("Tom &amp; Jerry"))
        XCTAssertTrue(html.contains("Tom &amp;amp; Jerry"))
    }

    func testLessThanEscaped() throws {
        let html = renderer.render(documentWithBody("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testDoubleQuoteEscaped() throws {
        let html = renderer.render(documentWithBody("say \"hello\""))
        XCTAssertTrue(html.contains("say &quot;hello&quot;"))
    }

    func testSingleQuoteEscaped() throws {
        let html = renderer.render(documentWithBody("it's fine"))
        XCTAssertTrue(html.contains("it&#39;s fine"))
    }

    func testTitleSpecialCharsEscaped() throws {
        let document = Document(
            version: "0.1",
            axis: .time,
            title: "<Script> & 'Danger'",
            planes: [Plane(z: 0, body: "ok")]
        )
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("&lt;Script&gt; &amp; &#39;Danger&#39;"))
    }

    func testLabelSpecialCharsEscaped() throws {
        let source = """
            ---
            3md: 0.1
            axis: layer
            ---
            @plane z=0 label="A & B"
            content
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("A &amp; B"))
    }

    // MARK: - Preamble

    func testPreambleRenderedInSection() throws {
        let source = """
            ---
            3md: 0.1
            axis: layer
            ---
            Preamble text here.

            @plane z=0
            body
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("class=\"preamble\""))
        XCTAssertTrue(html.contains("Preamble text here."))
    }

    // MARK: - Decimal Z

    func testDecimalZInDataAttribute() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=1.5
            halfway
            """
        let document = try parser.parse(source)
        let html = renderer.render(document)
        XCTAssertTrue(html.contains("data-z=\"1.5\""))
    }

    // MARK: - Helpers

    private func singlePlaneDocument() throws -> Document {
        let source = """
            ---
            3md: 0.1
            axis: time
            title: Test
            ---
            @plane z=0
            body
            """
        return try parser.parse(source)
    }

    private func documentWithBody(_ body: String) -> Document {
        Document(
            version: "0.1",
            axis: .layer,
            planes: [Plane(z: 0, body: body)]
        )
    }
}
