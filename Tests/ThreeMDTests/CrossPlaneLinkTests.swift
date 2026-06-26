import XCTest

@testable import ThreeMD

/// Unit tests for ``Document/links()`` cross-plane link extraction.
final class CrossPlaneLinkTests: XCTestCase {
    private let parser = Parser()

    // MARK: - Basic extraction

    func testBasicLinkNoText() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            see [[z=1]]

            @plane z=1
            there
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertEqual(result.count, 1)
        let link = try XCTUnwrap(result.first)
        XCTAssertEqual(link.sourceZ, 0)
        XCTAssertEqual(link.targetZ, 1)
        XCTAssertNil(link.text)
        XCTAssertTrue(link.targetExists)
    }

    // MARK: - Link with text

    func testLinkWithText() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            [[z=1|go there]]

            @plane z=1
            there
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertEqual(result.count, 1)
        let link = try XCTUnwrap(result.first)
        XCTAssertEqual(link.sourceZ, 0)
        XCTAssertEqual(link.targetZ, 1)
        XCTAssertEqual(link.text, "go there")
        XCTAssertTrue(link.targetExists)
    }

    // MARK: - Empty explicit text

    func testLinkWithEmptyText() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            [[z=1|]]

            @plane z=1
            there
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertEqual(result.count, 1)
        let link = try XCTUnwrap(result.first)
        XCTAssertEqual(link.text, "")
    }

    // MARK: - Multiple links

    func testMultipleLinksLeftToRight() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            first [[z=1]] then [[z=2|two]]

            @plane z=1
            a

            @plane z=2
            b
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].targetZ, 1)
        XCTAssertNil(result[0].text)
        XCTAssertEqual(result[1].targetZ, 2)
        XCTAssertEqual(result[1].text, "two")
    }

    func testLinksAcrossMultiplePlanesInSourceOrder() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            [[z=2]]

            @plane z=1
            [[z=0]]

            @plane z=2
            nothing
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].sourceZ, 0)
        XCTAssertEqual(result[0].targetZ, 2)
        XCTAssertEqual(result[1].sourceZ, 1)
        XCTAssertEqual(result[1].targetZ, 0)
    }

    // MARK: - Dangling references

    func testDanglingLinkTargetExistsFalse() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            go [[z=99]]
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertEqual(result.count, 1)
        let link = try XCTUnwrap(result.first)
        XCTAssertEqual(link.targetZ, 99)
        XCTAssertFalse(link.targetExists)
    }

    // MARK: - Decimal targets

    func testDecimalTarget() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            half [[z=1.5]]

            @plane z=1.5
            mid
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertEqual(result.count, 1)
        let link = try XCTUnwrap(result.first)
        XCTAssertEqual(link.targetZ, 1.5)
        XCTAssertTrue(link.targetExists)
    }

    func testNegativeDecimalTarget() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            back [[z=-1]]

            @plane z=-1
            behind
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertEqual(result.count, 1)
        let link = try XCTUnwrap(result.first)
        XCTAssertEqual(link.targetZ, -1)
        XCTAssertTrue(link.targetExists)
    }

    func testScientificNotationTarget() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            big [[z=1e3]]

            @plane z=1000
            far
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertEqual(result.count, 1)
        let link = try XCTUnwrap(result.first)
        XCTAssertEqual(link.targetZ, 1000)
        XCTAssertTrue(link.targetExists)
    }

    // MARK: - Invalid targets ignored

    func testNonDecimalTargetIgnored() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            [[z=abc]] and [[z=inf]] and [[notz]]
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertTrue(result.isEmpty)
    }

    func testHexTargetIgnored() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            [[z=0x1F]]
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertTrue(result.isEmpty)
    }

    func testNanTargetIgnored() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            [[z=nan]]
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertTrue(result.isEmpty)
    }

    func testOrdinaryMarkdownLinkNotExtracted() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            [text](http://example.com)
            """
        let document = try parser.parse(source)
        let result = document.links()

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Empty document

    func testDocumentWithNoLinksReturnsEmpty() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            just text
            """
        let document = try parser.parse(source)
        XCTAssertTrue(document.links().isEmpty)
    }

    // MARK: - Diagnostics

    func testDanglingLinksFiltersOnlyMissingTargets() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            ok [[z=1]] missing [[z=99]]

            @plane z=1
            there
            """
        let document = try parser.parse(source)
        let result = document.danglingLinks()

        XCTAssertEqual(result.count, 1)
        let link = try XCTUnwrap(result.first)
        XCTAssertEqual(link.sourceZ, 0)
        XCTAssertEqual(link.targetZ, 99)
        XCTAssertFalse(link.targetExists)
    }

    func testLinkGraphCollapsesRepeatedEdgesInEncounterOrder() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            [[z=1]] and [[z=1|again]] and [[z=2]]

            @plane z=1
            [[z=2]]

            @plane z=2
            done
            """
        let document = try parser.parse(source)
        let result = document.linkGraph()

        XCTAssertEqual(
            result,
            [
                CrossPlaneLinkEdge(sourceZ: 0, targetZ: 1, targetExists: true, count: 2),
                CrossPlaneLinkEdge(sourceZ: 0, targetZ: 2, targetExists: true, count: 1),
                CrossPlaneLinkEdge(sourceZ: 1, targetZ: 2, targetExists: true, count: 1),
            ]
        )
    }

    func testLinkGraphKeepsDanglingEdgeStatus() throws {
        let source = """
            ---
            3md: 0.1
            ---
            @plane z=0
            [[z=99]] and [[z=99|again]]
            """
        let document = try parser.parse(source)

        XCTAssertEqual(
            document.linkGraph(),
            [CrossPlaneLinkEdge(sourceZ: 0, targetZ: 99, targetExists: false, count: 2)]
        )
    }
}
