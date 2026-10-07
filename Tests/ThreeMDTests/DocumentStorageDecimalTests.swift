import Foundation
import XCTest

@testable import ThreeMD

final class DocumentStorageDecimalTests: XCTestCase {
    func testLongMalformedDecimalRejectsReadableAndChecksummedBinaryWithoutBacktracking() throws {
        let source = Self.malformedDecimalSource(digits: 4_096)
        let original = try DocumentStorageCodec.encodeTextContainer(Document(version: "1.0", axis: .layer, planes: []))
        var binary = try DocumentStorageTests.replacingPayload(original, with: source)
        DocumentStorageTests.write(UInt64(source.count), into: &binary, at: 28)
        try DocumentStorageTests.updateChecksum(&binary)
        XCTAssertLessThan(binary.count, DocumentDecodeLimits.standard.maximumEncodedBytes)
        XCTAssertLessThan(source.count, DocumentDecodeLimits.standard.maximumRecordBytes)
        let started = ProcessInfo.processInfo.systemUptime
        for data in [source, binary] {
            XCTAssertThrowsError(try DocumentStorageCodec.decode(data)) { error in
                guard case .invalidText(.invalidPlaneDirective) = error as? DocumentStorageError else {
                    return XCTFail("Expected invalidText(invalidPlaneDirective), got \(error)")
                }
            }
        }
        // The former ambiguous decimal regex took approximately four seconds
        // per 4 KiB payload. A generous bound catches that resource regression.
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2)
    }

    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    func testCancellationDuringAnInvalidParseRemainsCancellationError() async throws {
        let source = Self.malformedDecimalSource(digits: 4_096)
        let task = Task.detached {
            try DocumentStorageValidation.parse(source, limits: .standard) { source in
                // Cancel only after storage's UTF-8 and resource preflight has
                // completed, then exercise a real parser failure synchronously.
                withUnsafeCurrentTask { $0?.cancel() }
                return try Parser().parse(source)
            }
        }
        do {
            _ = try await task.value
            XCTFail("A canceled parse returned a document")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }
    }

    private static func malformedDecimalSource(digits: Int) -> Data {
        Data(("---\n3md: 1.0\n---\n@plane z=" + String(repeating: "1", count: digits) + "x\n").utf8)
    }
}
