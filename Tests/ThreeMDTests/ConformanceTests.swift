import XCTest

@testable import ThreeMD

/// Runs the shared cross-language conformance vectors in `conformance/` through
/// the Swift parser. The same vectors are run by the TypeScript package, so a
/// green run here proves the two implementations agree.
final class ConformanceTests: XCTestCase {
    // MARK: - Vector model

    private struct Vector: Decodable {
        let name: String
        let source: String
        let expected: ExpectedDocument?
        let error: String?
    }

    private struct ExpectedDocument: Decodable {
        let version: String
        let axis: String
        let title: String?
        let metadata: [String: String]
        let preamble: String?
        let planes: [ExpectedPlane]
    }

    private struct ExpectedPlane: Decodable {
        let z: Double
        let label: String?
        let x: Double?
        let y: Double?
        let attributes: [String: String]
        let body: String
    }

    // MARK: - Tests

    func testConformanceVectors() throws {
        let parser = Parser()
        let vectors = try loadVectors()
        XCTAssertFalse(vectors.isEmpty, "no conformance vectors were found")

        for (file, vector) in vectors {
            if let expected = vector.expected {
                let document: Document
                do {
                    document = try parser.parse(vector.source)
                } catch {
                    XCTFail("\(file): expected success but threw \(error) [\(vector.name)]")
                    continue
                }
                assertMatches(document, expected, file: file, name: vector.name)
            } else if let expectedError = vector.error {
                XCTAssertThrowsError(try parser.parse(vector.source), "\(file): \(vector.name)") { error in
                    guard let parseError = error as? ParseError else {
                        return XCTFail("\(file): threw non-ParseError \(error)")
                    }
                    XCTAssertEqual(code(of: parseError), expectedError, "\(file): wrong error [\(vector.name)]")
                }
            } else {
                XCTFail("\(file): vector has neither 'expected' nor 'error'")
            }
        }
    }

    // MARK: - Helpers

    private func assertMatches(_ document: Document, _ expected: ExpectedDocument, file: String, name: String) {
        let tag = "\(file) [\(name)]"
        XCTAssertEqual(document.version, expected.version, "version mismatch: \(tag)")
        XCTAssertEqual(document.axis.rawValue, expected.axis, "axis mismatch: \(tag)")
        XCTAssertEqual(document.title, expected.title, "title mismatch: \(tag)")
        XCTAssertEqual(document.metadata, expected.metadata, "metadata mismatch: \(tag)")
        XCTAssertEqual(document.preamble, expected.preamble, "preamble mismatch: \(tag)")
        XCTAssertEqual(document.planes.count, expected.planes.count, "plane count mismatch: \(tag)")

        for (plane, want) in zip(document.planes, expected.planes) {
            XCTAssertEqual(plane.z, want.z, "z mismatch: \(tag)")
            XCTAssertEqual(plane.label, want.label, "label mismatch: \(tag)")
            XCTAssertEqual(plane.x, want.x, "x mismatch: \(tag)")
            XCTAssertEqual(plane.y, want.y, "y mismatch: \(tag)")
            XCTAssertEqual(plane.attributes, want.attributes, "attributes mismatch: \(tag)")
            XCTAssertEqual(plane.body, want.body, "body mismatch: \(tag)")
        }
    }

    private func code(of error: ParseError) -> String {
        switch error {
        case .missingFrontmatter: return "missingFrontmatter"
        case .invalidFrontmatter: return "invalidFrontmatter"
        case .missingVersion: return "missingVersion"
        case .missingPlanePosition: return "missingPlanePosition"
        case .invalidPlaneDirective: return "invalidPlaneDirective"
        case .duplicatePlane: return "duplicatePlane"
        }
    }

    private func loadVectors() throws -> [(file: String, vector: Vector)] {
        let directory = conformanceDirectory()
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(atPath: directory.path) else {
            XCTFail("conformance directory not found at \(directory.path)")
            return []
        }
        let decoder = JSONDecoder()
        var result: [(file: String, vector: Vector)] = []
        for entry in entries.sorted() where entry.hasSuffix(".json") {
            let url = directory.appendingPathComponent(entry)
            let data = try Data(contentsOf: url)
            let vector = try decoder.decode(Vector.self, from: data)
            result.append((file: entry, vector: vector))
        }
        return result
    }

    /// Locates the repository's `conformance/` directory relative to this source
    /// file: Tests/ThreeMDTests/ConformanceTests.swift is three levels deep.
    private func conformanceDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("conformance")
    }
}
