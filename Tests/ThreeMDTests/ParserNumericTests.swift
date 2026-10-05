import XCTest

@testable import ThreeMD

final class ParserNumericTests: XCTestCase {
    func testFiniteDecimalGrammarIsPreservedForEveryCoordinate() throws {
        let accepted = [
            "0", "-0", "+0", "123", "-123", "+123", "01", "000.000",
            "1.", "1.25", ".5", "-.5", "+.5", "1.e2", "-1.25E-2", "1e3", "1E+3",
            "5e-324", "-5e-324", "1.7976931348623157e308",
        ]
        for raw in accepted {
            let source = "---\n3md: 1.0\n---\n@plane z=\(raw) x=\(raw) y=\(raw)\n"
            let document = try Parser().parse(source)
            let plane = try XCTUnwrap(document.planes.first)
            let expected = try XCTUnwrap(Double(raw))
            XCTAssertEqual(plane.z, expected, raw)
            XCTAssertEqual(plane.x, expected, raw)
            XCTAssertEqual(plane.y, expected, raw)
        }
    }

    func testMalformedAndNonfiniteNumbersAreRejectedForEveryCoordinate() {
        let rejected = [
            "", "+", "-", ".", "+.", "-.", "1e", "1e+", "1e-", "e1", "--1", "1..0",
            "0x10", "nan", "NaN", "inf", "Infinity", "1e309", "١", "１", "1_000", "1x",
        ]
        for key in ["z", "x", "y"] {
            for raw in rejected {
                let position = key == "z" ? "" : "z=0 "
                let source = "---\n3md: 1.0\n---\n@plane \(position)\(key)=\"\(raw)\"\n"
                XCTAssertThrowsError(try Parser().parse(source), "\(key)=\(raw)") { error in
                    guard case .invalidPlaneDirective = error as? ParseError else {
                        return XCTFail("Expected invalidPlaneDirective, got \(error)")
                    }
                }
            }
        }
    }
}
