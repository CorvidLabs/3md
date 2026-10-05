import XCTest

@testable import ThreeMD

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class DocumentDiagnosticTests: XCTestCase {
    func testSourceParseDiagnosticsPreserveRealLineEvidence() throws {
        let report = try DocumentDiagnostics.inspect(source: "---\n3md: 0.1\n---\n\n@plane label=\"Missing\"\nBody\n")
        XCTAssertEqual(report.diagnostics.first?.code, .parseFailure)
        XCTAssertEqual(report.diagnostics.first?.sourceLine, 5)
        XCTAssertEqual(report.diagnostics.first?.path, "source")
        XCTAssertNil(DocumentDiagnostics.parseFailure(.duplicatePlane(z: 0)).sourceLine)
        XCTAssertNil(DocumentDiagnostics.parseFailure(.missingFrontmatter).sourceLine)
    }

    func testValueDiagnosticsHavePlanePathsAndNoInventedLines() throws {
        let document = Document(
            version: "0.1",
            axis: .layer,
            planes: [
                .init(z: 0, attributes: ["3md-id": "good"], body: "One"),
                .init(z: 1, attributes: ["3md-id": "good"], body: "Two"),
                .init(z: 1, attributes: ["3md-id": "../bad"], body: "Three"),
            ]
        )
        let report = try DocumentDiagnostics.inspect(document)
        XCTAssertEqual(report.diagnostics.map(\.code), [.duplicateIdentity, .invalidIdentity, .duplicatePosition])
        XCTAssertEqual(
            report.diagnostics.map(\.path),
            ["planes[1].attributes[3md-id]", "planes[2].attributes[3md-id]", "planes[2].z"]
        )
        XCTAssertTrue(report.diagnostics.allSatisfy { $0.sourceLine == nil })
        XCTAssertFalse(report.isTruncated)
    }

    func testCompositionDiagnosticsScopeRepeatedInstanceIDsByOwner() throws {
        let document = Document(version: "0.1", axis: .layer, planes: [.init(z: 0, body: "Body")])
        let composition = try DocumentComposition(
            rootID: "root",
            entries: [
                .init(id: "leaf", document: document),
                .init(
                    id: "root",
                    document: document,
                    references: [
                        .init(targetID: "leaf", attributes: ["3md-id": "same"]),
                        .init(targetID: "leaf", attributes: ["3md-id": "same"]),
                    ]
                ),
            ]
        )
        let report = try DocumentDiagnostics.inspect(composition)
        XCTAssertEqual(report.diagnostics.count, 1)
        XCTAssertEqual(report.diagnostics.first?.path, "entries[1].references[1].attributes[3md-id]")
    }

    func testDiagnosticCeilingSignalsUninspectedRemainder() throws {
        let document = Document(
            version: "0.1",
            axis: .layer,
            planes: (0..<20).map {
                .init(z: Double($0), attributes: ["3md-id": ""], body: "Body")
            }
        )
        let report = try DocumentDiagnostics.inspect(document, limits: .init(maximumDiagnostics: 2))
        XCTAssertEqual(report.diagnostics.count, 2)
        XCTAssertTrue(report.isTruncated)
        XCTAssertEqual(report.diagnostics.last?.path, "planes[1].attributes[3md-id]")
    }

    func testDiagnosticInputAndValueByteWorkAreBounded() throws {
        let limits = try DocumentEditLimits(maximumDiagnosticBytes: 64)
        XCTAssertThrowsError(try DocumentDiagnostics.inspect(source: String(repeating: "x", count: 65), limits: limits))
        { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .payloadLimit)
        }
        let document = Document(
            version: "0.1",
            axis: .layer,
            planes: [.init(z: 0, body: String(repeating: "x", count: 64))]
        )
        XCTAssertThrowsError(try DocumentDiagnostics.inspect(document, limits: limits)) { error in
            XCTAssertEqual((error as? DocumentEditError)?.diagnostic.code, .payloadLimit)
        }
    }

    func testHostileLinkPrefixesDoNotTriggerLegacyRegexDuringDiagnostics() throws {
        let body = String(repeating: "[[z=", count: 30_000)
        let document = Document(version: "0.1", axis: .layer, planes: [.init(z: 0, body: body)])
        XCTAssertTrue(try DocumentDiagnostics.inspect(document).diagnostics.isEmpty)
    }

    func testSharedDecimalScannerRejectsLongMalformedLinkNumberAndPreservesGrammar() throws {
        let malformed = "[[z=" + String(repeating: "7", count: 100_000) + "x]]"
        let document = Document(
            version: "0.1",
            axis: .layer,
            planes: [.init(z: 0, body: malformed + " [[z=+1.e0|valid]]")]
        )
        XCTAssertEqual(document.links().map(\.targetZ), [1])
        for valid in ["1", "1.", ".1", "+1.e0", "-0", "2E-3"] { XCTAssertNotNil(FiniteDecimal.parse(valid)) }
        for invalid in ["", ".", "1e", "1x", "1e999", "inf", "nan", "0x1", "1 2"] {
            XCTAssertNil(FiniteDecimal.parse(invalid))
        }
    }

    func testCancellationIsNeverConvertedIntoAValidationDiagnostic() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DocumentDiagnostics.inspect(source: "---\n3md: 0.1\n---\n")
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch {
            XCTFail("\(error)")
        }
    }
}
