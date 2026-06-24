import XCTest

@testable import ThreeMD

final class ParserTests: XCTestCase {
    private let parser = Parser()

    // MARK: - Frontmatter

    func testParsesFrontmatter() throws {
        let source = """
            ---
            3md: 0.1
            axis: time
            title: My Week
            author: leif
            ---
            @plane z=0
            # Monday
            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.version, "0.1")
        XCTAssertEqual(document.axis, .time)
        XCTAssertEqual(document.title, "My Week")
        XCTAssertEqual(document.metadata["author"], "leif")
    }

    func testMissingFrontmatterThrows() {
        let source = "# Just markdown\n"
        XCTAssertThrowsError(try parser.parse(source)) { error in
            XCTAssertEqual(error as? ParseError, .missingFrontmatter)
        }
    }

    func testMissingVersionThrows() {
        let source = """
            ---
            axis: time
            ---
            @plane z=0
            body
            """
        XCTAssertThrowsError(try parser.parse(source)) { error in
            XCTAssertEqual(error as? ParseError, .missingVersion)
        }
    }

    func testUnclosedFrontmatterThrows() {
        let source = """
            ---
            3md: 0.1
            axis: time
            """
        XCTAssertThrowsError(try parser.parse(source)) { error in
            guard case .invalidFrontmatter = error as? ParseError else {
                return XCTFail("expected invalidFrontmatter, got \(error)")
            }
        }
    }

    func testAxisDefaultsToLayer() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            body
            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.axis, .layer)
    }

    func testFrontmatterIgnoresCommentLines() throws {
        let source = """
            ---
            # this is a comment
            3md: 0.1
            axis: depth
            ---
            @plane z=0
            body
            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.version, "0.1")
        XCTAssertEqual(document.axis, .depth)
    }

    func testFrontmatterStripsQuotedValues() throws {
        let source = """
            ---
            3md: 0.1
            title: "My quoted title"
            ---
            @plane z=0
            body
            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.title, "My quoted title")
    }

    func testLeadingBlankLinesBeforeFrontmatter() throws {
        let source = "\n\n---\n3md: 0.1\n---\n@plane z=0\nbody"
        let document = try parser.parse(source)
        XCTAssertEqual(document.version, "0.1")
    }

    func testWindowsLineEndingsNormalized() throws {
        let source = "---\r\n3md: 0.1\r\n---\r\n@plane z=0\r\nbody"
        let document = try parser.parse(source)
        XCTAssertEqual(document.planes.first?.body, "body")
    }

    // MARK: - Planes

    func testParsesMultiplePlanes() throws {
        let source = """
            ---
            3md: 0.1
            axis: time
            ---
            @plane z=0 label="Monday"
            # Monday
            - [ ] Standup

            @plane z=1 label="Tuesday"
            # Tuesday
            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.planes.count, 2)
        XCTAssertEqual(document.planes[0].z, 0)
        XCTAssertEqual(document.planes[0].label, "Monday")
        XCTAssertEqual(document.planes[0].body, "# Monday\n- [ ] Standup")
        XCTAssertEqual(document.planes[1].label, "Tuesday")
        XCTAssertEqual(document.planes[1].body, "# Tuesday")
    }

    func testParsesPlaneCoordinatesAndAttributes() throws {
        let source = """
            ---
            3md: 0.1
            axis: space
            ---
            @plane z=2.5 x=10 y=-3 color=red note="top right"
            content
            """
        let document = try parser.parse(source)
        let plane = try XCTUnwrap(document.planes.first)
        XCTAssertEqual(plane.z, 2.5)
        XCTAssertEqual(plane.x, 10)
        XCTAssertEqual(plane.y, -3)
        XCTAssertEqual(plane.attributes["color"], "red")
        XCTAssertEqual(plane.attributes["note"], "top right")
    }

    func testNegativeZValue() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=-1
            below zero
            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.planes.first?.z, -1)
    }

    func testDecimalZValue() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0.5
            halfway
            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.planes.first?.z, 0.5)
    }

    func testPlaneBodyTrimsLeadingAndTrailingBlanks() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0

            content

            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.planes.first?.body, "content")
    }

    func testPlainMarkdownBecomesSinglePlane() throws {
        let source = """
            ---
            3md: 0.1
            ---
            # Hello
            Just one plane.
            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.planes.count, 1)
        XCTAssertEqual(document.planes[0].z, 0)
        XCTAssertEqual(document.planes[0].body, "# Hello\nJust one plane.")
        XCTAssertNil(document.preamble)
    }

    func testPreambleBeforeFirstPlane() throws {
        let source = """
            ---
            3md: 0.1
            axis: frame
            ---
            Intro text.

            @plane z=0
            frame zero
            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.preamble, "Intro text.")
        XCTAssertEqual(document.planes.count, 1)
        XCTAssertEqual(document.planes[0].body, "frame zero")
    }

    func testEmptyDocumentProducesNoPlanes() throws {
        let source = """
            ---
            3md: 0.1
            ---
            """
        let document = try parser.parse(source)
        XCTAssertTrue(document.planes.isEmpty)
        XCTAssertNil(document.preamble)
    }

    func testReservedAttributeKeysNotInExtras() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0 x=1 y=2 label="A" custom=B
            body
            """
        let document = try parser.parse(source)
        let plane = try XCTUnwrap(document.planes.first)
        XCTAssertNil(plane.attributes["z"])
        XCTAssertNil(plane.attributes["x"])
        XCTAssertNil(plane.attributes["y"])
        XCTAssertNil(plane.attributes["label"])
        XCTAssertEqual(plane.attributes["custom"], "B")
    }

    // MARK: - Errors

    func testMissingPlanePositionThrows() {
        let source = """
            ---
            3md: 0.1
            ---
            @plane label="oops"
            body
            """
        XCTAssertThrowsError(try parser.parse(source)) { error in
            guard case .missingPlanePosition = error as? ParseError else {
                return XCTFail("expected missingPlanePosition, got \(error)")
            }
        }
    }

    func testNonNumericPositionThrows() {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=soon
            body
            """
        XCTAssertThrowsError(try parser.parse(source)) { error in
            guard case .invalidPlaneDirective = error as? ParseError else {
                return XCTFail("expected invalidPlaneDirective, got \(error)")
            }
        }
    }

    func testNonNumericXThrows() {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0 x=left
            body
            """
        XCTAssertThrowsError(try parser.parse(source)) { error in
            guard case .invalidPlaneDirective = error as? ParseError else {
                return XCTFail("expected invalidPlaneDirective, got \(error)")
            }
        }
    }

    func testNonNumericYThrows() {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0 y=top
            body
            """
        XCTAssertThrowsError(try parser.parse(source)) { error in
            guard case .invalidPlaneDirective = error as? ParseError else {
                return XCTFail("expected invalidPlaneDirective, got \(error)")
            }
        }
    }

    func testDuplicatePositionThrows() {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            a

            @plane z=0
            b
            """
        XCTAssertThrowsError(try parser.parse(source)) { error in
            XCTAssertEqual(error as? ParseError, .duplicatePlane(z: 0))
        }
    }

    func testInvalidDirectiveTokenThrows() {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0 badtoken
            body
            """
        XCTAssertThrowsError(try parser.parse(source)) { error in
            guard case .invalidPlaneDirective = error as? ParseError else {
                return XCTFail("expected invalidPlaneDirective, got \(error)")
            }
        }
    }

    // MARK: - Lookups

    func testPlanesByZAreSorted() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=2
            two

            @plane z=0
            zero

            @plane z=1
            one
            """
        let document = try parser.parse(source)
        XCTAssertEqual(document.planesByZ.map(\.z), [0, 1, 2])
        XCTAssertEqual(document.plane(atZ: 1)?.body, "one")
    }

    func testPlaneAtZReturnsNilForMissingPosition() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            only plane
            """
        let document = try parser.parse(source)
        XCTAssertNil(document.plane(atZ: 99))
    }

    // MARK: - Axis

    func testAxisRawValueNormalized() {
        XCTAssertEqual(Axis(rawValue: "  TIME  ").rawValue, "time")
        XCTAssertEqual(Axis(rawValue: "DEPTH").rawValue, "depth")
    }

    func testKnownAxesMatchSpec() {
        XCTAssertEqual(Axis.time.rawValue, "time")
        XCTAssertEqual(Axis.depth.rawValue, "depth")
        XCTAssertEqual(Axis.layer.rawValue, "layer")
        XCTAssertEqual(Axis.frame.rawValue, "frame")
        XCTAssertEqual(Axis.space.rawValue, "space")
    }

    // MARK: - ParseError

    func testParseErrorDescriptions() {
        XCTAssertNotNil(ParseError.missingFrontmatter.errorDescription)
        XCTAssertNotNil(ParseError.invalidFrontmatter("oops").errorDescription)
        XCTAssertNotNil(ParseError.missingVersion.errorDescription)
        XCTAssertNotNil(ParseError.invalidPlaneDirective(line: 1, detail: "bad").errorDescription)
        XCTAssertNotNil(ParseError.missingPlanePosition(line: 1).errorDescription)
        XCTAssertNotNil(ParseError.duplicatePlane(z: 0).errorDescription)
    }

    // MARK: - Round Trip

    func testRoundTripThroughSerializer() throws {
        let source = """
            ---
            3md: 0.1
            axis: time
            title: Sprint
            ---
            @plane z=0 label="Day one"
            # Day one
            - ship it

            @plane z=1 label="Day two"
            # Day two
            """
        let document = try parser.parse(source)
        let rendered = Serializer().render(document)
        let reparsed = try parser.parse(rendered)
        XCTAssertEqual(reparsed, document)
    }

    func testRoundTripWithMetadataAndAttributes() throws {
        let source = """
            ---
            3md: 0.1
            axis: frame
            title: Bouncing dot
            fps: "12"
            ---
            @plane z=0 label="frame-0"
            ```
            o........
            ```
            """
        let document = try parser.parse(source)
        let rendered = Serializer().render(document)
        let reparsed = try parser.parse(rendered)
        XCTAssertEqual(reparsed.metadata["fps"], "12")
        XCTAssertEqual(reparsed.planes.first?.label, "frame-0")
    }

    func testRoundTripWithPreamble() throws {
        let source = """
            ---
            3md: 0.1
            axis: layer
            ---
            Intro preamble.

            @plane z=0
            body
            """
        let document = try parser.parse(source)
        let rendered = Serializer().render(document)
        let reparsed = try parser.parse(rendered)
        XCTAssertEqual(reparsed.preamble, "Intro preamble.")
    }
}
