import Foundation
import XCTest

@testable import ThreeMD

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class DocumentStorageBoundsTests: XCTestCase {
    func testLimitsArePositiveAndHaveNoAbsoluteCeiling() throws {
        let standard = DocumentDecodeLimits.standard
        XCTAssertEqual(standard.maximumEncodedBytes, Int.max)
        XCTAssertEqual(standard.maximumDecodedBytes, Int.max)
        XCTAssertEqual(standard.maximumLines, Int.max)
        XCTAssertEqual(standard.maximumPlanes, Int.max)
        XCTAssertEqual(standard.maximumRecordBytes, Int.max)
        XCTAssertEqual(try DocumentDecodeLimits(), standard)
        let fiveGigabytes = 5 * 1_024 * 1_024 * 1_024
        let wide = try DocumentDecodeLimits(
            maximumEncodedBytes: fiveGigabytes,
            maximumDecodedBytes: fiveGigabytes,
            maximumLines: 2_000_000,
            maximumPlanes: 200_000,
            maximumRecordBytes: fiveGigabytes
        )
        XCTAssertEqual(wide.maximumEncodedBytes, fiveGigabytes)
        XCTAssertEqual(wide.maximumRecordBytes, fiveGigabytes)
        DocumentStorageTests.assertError(.invalidLimits) { try DocumentDecodeLimits(maximumEncodedBytes: 0) }
        DocumentStorageTests.assertError(.invalidLimits) { try DocumentDecodeLimits(maximumDecodedBytes: -1) }
        DocumentStorageTests.assertError(.invalidLimits) { try DocumentDecodeLimits(maximumLines: 0) }
        DocumentStorageTests.assertError(.invalidLimits) { try DocumentDecodeLimits(maximumPlanes: -5) }
        DocumentStorageTests.assertError(.invalidLimits) { try DocumentDecodeLimits(maximumRecordBytes: 0) }
    }

    func testADocumentPastTheOldCeilingRoundTrips() throws {
        let body = String(repeating: "a", count: 64 * 1_024 * 1_024 + 1)
        let document = Document(version: "1", axis: .layer, planes: [Plane(z: 0, body: body)])
        let text = try DocumentStorageCodec.encode(document)
        XCTAssertGreaterThan(text.count, 64 * 1_024 * 1_024)
        XCTAssertEqual(try DocumentStorageCodec.decode(text), document)
        let binary = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        XCTAssertEqual(try DocumentStorageCodec.decode(binary), document)
        // Blank-only bodies are collapsed by the text format.
        // 100,001 lines of "a" stay, and they pass the old line cap.
        let manyLines = Array(repeating: "a", count: 100_001).joined(separator: "\n")
        let lines = Document(version: "1", axis: .layer, planes: [Plane(z: 0, body: manyLines)])
        XCTAssertEqual(try DocumentStorageCodec.decode(DocumentStorageCodec.encode(lines)), lines)
    }

    func testTextAndPortableBinaryAcceptExactByteBounds() throws {
        let document = Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, body: "Exact boundary")])
        let source = try DocumentStorageCodec.encode(document)
        let sourceLimits = try DocumentDecodeLimits(
            maximumEncodedBytes: source.count,
            maximumDecodedBytes: source.count
        )
        XCTAssertEqual(try DocumentStorageCodec.encode(document, limits: sourceLimits), source)
        XCTAssertEqual(try DocumentStorageCodec.decode(source, limits: sourceLimits), document)
        let inputTooSmall = try DocumentDecodeLimits(maximumEncodedBytes: source.count - 1)
        DocumentStorageTests.assertError(.oversizedInput) {
            try DocumentStorageCodec.decode(source, limits: inputTooSmall)
        }
        DocumentStorageTests.assertError(.oversizedInput) {
            try DocumentStorageCodec.encode(document, limits: inputTooSmall)
        }
        let outputTooSmall = try DocumentDecodeLimits(maximumDecodedBytes: source.count - 1)
        DocumentStorageTests.assertError(.oversizedOutput) {
            try DocumentStorageCodec.encode(document, limits: outputTooSmall)
        }
        DocumentStorageTests.assertError(.oversizedOutput) {
            try DocumentStorageCodec.decode(source, limits: outputTooSmall)
        }

        let binary = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        let exact = try DocumentDecodeLimits(maximumEncodedBytes: binary.count, maximumDecodedBytes: source.count)
        XCTAssertEqual(
            try DocumentStorageCodec.encode(document, format: .binary(compression: .none), limits: exact),
            binary
        )
        XCTAssertEqual(try DocumentStorageCodec.decode(binary, limits: exact), document)
        DocumentStorageTests.assertError(.oversizedOutput) {
            try DocumentStorageCodec.decode(binary, limits: outputTooSmall)
        }
        let smallerBinary = try DocumentDecodeLimits(maximumEncodedBytes: binary.count - 1)
        DocumentStorageTests.assertError(.oversizedInput) {
            try DocumentStorageCodec.encode(document, format: .binary(compression: .none), limits: smallerBinary)
        }

        // The same bounds hold for the payload kind 1 text container.
        let textContainer = try DocumentStorageCodec.encodeTextContainer(document)
        let exactText = try DocumentDecodeLimits(
            maximumEncodedBytes: textContainer.count,
            maximumDecodedBytes: source.count
        )
        XCTAssertEqual(try DocumentStorageCodec.encodeTextContainer(document, limits: exactText), textContainer)
        XCTAssertEqual(try DocumentStorageCodec.decode(textContainer, limits: exactText), document)
        DocumentStorageTests.assertError(.oversizedOutput) {
            try DocumentStorageCodec.decode(textContainer, limits: outputTooSmall)
        }
        let smallerText = try DocumentDecodeLimits(maximumEncodedBytes: textContainer.count - 1)
        DocumentStorageTests.assertError(.oversizedInput) {
            try DocumentStorageCodec.encodeTextContainer(document, limits: smallerText)
        }
        DocumentStorageTests.assertError(.oversizedInput) {
            try DocumentStorageCodec.decode(textContainer, limits: smallerText)
        }
    }

    func testPhysicalLinesAreBoundedBeforeParsingEvenForBlankInputs() throws {
        let limits = try DocumentDecodeLimits(maximumLines: 5)
        let source = try DocumentStorageCodec.encode(Document(version: "1.0", axis: .layer, planes: []))
        XCTAssertEqual(try DocumentStorageCodec.decode(source, limits: limits).planes.count, 0)
        var excess = source
        excess.append(10)
        DocumentStorageTests.assertError(.tooManyLines) { try DocumentStorageCodec.decode(excess, limits: limits) }
        // The old default refused 100,000 newline bytes before parsing. That refusal is now a caller limit.
        let historicalLineCap = try DocumentDecodeLimits(maximumLines: 100_000)
        DocumentStorageTests.assertError(.tooManyLines) {
            try DocumentStorageCodec.decode(
                Data(repeating: 10, count: 100_000),
                limits: historicalLineCap
            )
        }
    }

    func testPlanePreflightIgnoresDirectivesInsideBothKindsOfFences() throws {
        let onePlane = try DocumentDecodeLimits(maximumPlanes: 1)
        let document = Document(
            version: "1.0",
            axis: .layer,
            planes: [Plane(z: 0, body: "```text\n@plane z=1\n```\n~~~text\n@plane z=2\n~~~")]
        )
        XCTAssertEqual(
            try DocumentStorageCodec.decode(DocumentStorageCodec.encode(document), limits: onePlane),
            document
        )
        let two = Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, body: "a"), Plane(z: 1, body: "b")])
        DocumentStorageTests.assertError(.tooManyPlanes) { try DocumentStorageCodec.validate(two, limits: onePlane) }
        let source = try DocumentStorageCodec.encode(two)
        DocumentStorageTests.assertError(.tooManyPlanes) { try DocumentStorageCodec.decode(source, limits: onePlane) }
    }

    func testRecordBoundIncludesWholePlaneBodiesAndEscapedScalarLines() throws {
        let limits = try DocumentDecodeLimits(maximumRecordBytes: 64)
        let body = String(repeating: "a", count: 40) + "\n" + String(repeating: "b", count: 40)
        let raw = Data(("---\n3md: 1.0\n---\n@plane z=0\n" + body).utf8)
        DocumentStorageTests.assertError(.oversizedRecord) { try DocumentStorageCodec.decode(raw, limits: limits) }
        let oversized = Document(version: "1.0", axis: .layer, title: String(repeating: "a", count: 65), planes: [])
        DocumentStorageTests.assertError(.oversizedRecord) {
            try DocumentStorageCodec.validate(oversized, limits: limits)
        }
        let escaped = Document(version: "1.0", axis: .layer, title: String(repeating: "\"", count: 40), planes: [])
        DocumentStorageTests.assertError(.oversizedRecord) { try DocumentStorageCodec.encode(escaped, limits: limits) }
    }

    func testCombinedScalarAndDirectiveBytesCannotBypassTheOutputBound() throws {
        let limits = try DocumentDecodeLimits(maximumDecodedBytes: 256, maximumRecordBytes: 256)
        let metadata = Document(
            version: "1.0",
            axis: .layer,
            metadata: [String(repeating: "k", count: 120): String(repeating: "\"", count: 100)],
            planes: []
        )
        DocumentStorageTests.assertError(.oversizedOutput) { try DocumentStorageCodec.encode(metadata, limits: limits) }
        let directive = Document(
            version: "1.0",
            axis: .layer,
            planes: [
                Plane(
                    z: 0,
                    label: String(repeating: "\"", count: 80),
                    attributes: ["extra": String(repeating: "x", count: 100)],
                    body: ""
                )
            ]
        )
        DocumentStorageTests.assertError(.oversizedOutput) {
            try DocumentStorageCodec.encode(directive, limits: limits)
        }
    }

    @MainActor
    func testCanceledTasksCannotReturnPartiallyEncodedOrDecodedDocuments() async throws {
        let document = Document(version: "1.0", axis: .space, planes: [Plane(z: 0, body: "A bounded document")])
        let binary = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        let operations: [@Sendable () throws -> Void] = [
            { try DocumentStorageCodec.validate(document) },
            { _ = try DocumentStorageCodec.encode(document) },
            { _ = try DocumentStorageCodec.encode(document, format: .binary(compression: .none)) },
            { _ = try DocumentStorageCodec.decode(binary) },
        ]
        for operation in operations {
            let gate = DocumentStorageCancellationGate()
            let task = Task.detached {
                await gate.park()
                try operation()
            }
            await gate.waitUntilParked()
            task.cancel()
            await gate.release()
            do {
                try await task.value
                XCTFail("A canceled operation returned success")
            } catch { XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)") }
        }
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal actor DocumentStorageCancellationGate {
    private var parked = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func park() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            parked = true
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilParked() async {
        if parked { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
