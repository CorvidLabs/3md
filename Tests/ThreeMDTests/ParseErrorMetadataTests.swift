import XCTest

@testable import ThreeMD

/// Tests for machine-readable ``ParseError`` metadata.
final class ParseErrorMetadataTests: XCTestCase {
    func testMissingVersionCode() {
        let error = ParseError.missingVersion

        XCTAssertEqual(error.code, "missingVersion")
        XCTAssertNil(error.line)
        XCTAssertNil(error.detail)
    }

    func testInvalidDirectiveMetadata() {
        let error = ParseError.invalidPlaneDirective(line: 7, detail: "expected key=value")

        XCTAssertEqual(error.code, "invalidPlaneDirective")
        XCTAssertEqual(error.line, 7)
        XCTAssertEqual(error.detail, "expected key=value")
    }

    func testDuplicatePlaneMetadata() {
        let error = ParseError.duplicatePlane(z: 2)

        XCTAssertEqual(error.code, "duplicatePlane")
        XCTAssertNil(error.line)
        XCTAssertEqual(error.detail, "2.0")
    }
}
