import Foundation
import XCTest

@testable import ThreeMD

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
final class DocumentStorageCompressionTests: XCTestCase {
    #if canImport(Compression)
    func testAppleLZFSECompressionIsDeterministicAndRoundTripsGeneralText() throws {
        let document = Document(
            version: "1.0",
            axis: Axis(rawValue: "temperature"),
            title: "雪 · Unicode",
            planes: [Plane(z: -1.25, body: String(repeating: "A repeated Unicode line 雪.\n", count: 4_096) + "end")]
        )
        let text = try DocumentStorageCodec.encode(document)
        let compressed = try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse))
        XCTAssertLessThan(compressed.count, text.count / 10)
        XCTAssertEqual(try DocumentStorageCodec.decode(compressed), document)
        XCTAssertEqual(try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse)), compressed)
        XCTAssertEqual(Array(compressed.suffix(4)), [0x62, 0x76, 0x78, 0x24])
        let limits = try DocumentDecodeLimits(maximumEncodedBytes: compressed.count, maximumDecodedBytes: text.count)
        XCTAssertEqual(try DocumentStorageCodec.decode(compressed, limits: limits), document)
    }

    func testLZFSERejectsTrailingAndConcatenatedStreamsWithValidChecksums() throws {
        let document = Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, body: "A complete document")])
        let encoded = try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse))
        let payload = Data(encoded.dropFirst(40))
        let trailing = try DocumentStorageTests.replacingPayload(encoded, with: payload + Data([0]))
        DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(trailing) }
        let concatenated = try DocumentStorageTests.replacingPayload(encoded, with: payload + payload)
        DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(concatenated) }
        let hiddenTrailing = try DocumentStorageTests.replacingPayload(
            encoded,
            with: payload + Data([0]) + Data([0x62, 0x76, 0x78, 0x24])
        )
        DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(hiddenTrailing) }
    }

    func testLargeFirstStreamDrainsMultipleChunksBeforeFinalMarkerAndRejectsConcatenation() throws {
        let document = Document(
            version: "1.0",
            axis: .space,
            planes: [Plane(z: 0, body: String(repeating: "a", count: 300_000))]
        )
        let encoded = try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse))
        XCTAssertEqual(try DocumentStorageCodec.decode(encoded), document)
        let second = try DocumentStorageCodec.encode(
            Document(version: "1.0", axis: .layer, planes: []),
            format: .binary(compression: .lzfse)
        )
        let joined = try DocumentStorageTests.replacingPayload(
            encoded,
            with: Data(encoded.dropFirst(40)) + Data(second.dropFirst(40))
        )
        DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(joined) }
    }

    func testDeclaredOutputSizeCannotTruncateOrGrowDecompression() throws {
        let document = Document(
            version: "1.0",
            axis: .layer,
            planes: [Plane(z: 0, body: String(repeating: "a", count: 200_000))]
        )
        let text = try DocumentStorageCodec.encode(document)
        let original = try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse))
        for declared in [1, 65_536, text.count - 1, text.count + 1] {
            var changed = original
            DocumentStorageTests.write(UInt64(declared), into: &changed, at: 28)
            try DocumentStorageTests.updateChecksum(&changed)
            DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(changed) }
        }
        let lowOutput = try DocumentDecodeLimits(maximumDecodedBytes: 1)
        DocumentStorageTests.assertError(.oversizedOutput) {
            try DocumentStorageCodec.decode(original, limits: lowOutput)
        }
        let lowInput = try DocumentDecodeLimits(maximumEncodedBytes: 40)
        DocumentStorageTests.assertError(.oversizedInput) {
            try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse), limits: lowInput)
        }
    }

    func testEveryTruncationAndMalformedCompressionPayloadFailsWithoutPartialResults() throws {
        let original = try DocumentStorageCodec.encode(
            Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, body: "small")]),
            format: .binary(compression: .lzfse)
        )
        let payload = Data(original.dropFirst(40))
        for count in 0..<payload.count {
            let truncated = try DocumentStorageTests.replacingPayload(original, with: Data(payload.prefix(count)))
            XCTAssertThrowsError(
                try DocumentStorageCodec.decode(truncated),
                "Accepted truncated payload of \(count) bytes"
            )
        }
        for seed in UInt8(0)..<32 {
            let malformed =
                Data((0..<64).map { UInt8(truncatingIfNeeded: $0 * 17) ^ seed }) + Data([0x62, 0x76, 0x78, 0x24])
            let changed = try DocumentStorageTests.replacingPayload(original, with: malformed)
            XCTAssertThrowsError(try DocumentStorageCodec.decode(changed), "Accepted malformed stream seed \(seed)")
        }
    }

    @MainActor
    func testCanceledCompressionAndDecompressionRemainCancellationErrors() async throws {
        let document = Document(
            version: "1.0",
            axis: .space,
            planes: [Plane(z: 0, body: String(repeating: "a", count: 100_000))]
        )
        let data = try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse))
        let operations: [@Sendable () throws -> Void] = [
            { _ = try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse)) },
            { _ = try DocumentStorageCodec.decode(data) },
        ]
        for operation in operations {
            let gate = DocumentStorageCancellationGate()
            let task = Task.detached {
                await gate.park(); try operation()
            }
            await gate.waitUntilParked()
            task.cancel()
            await gate.release()
            do { try await task.value; XCTFail("Canceled compression returned success") } catch {
                XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
            }
        }
    }
    #else
    func testUnavailableNativeCompressionHasAnExplicitPortableFailure() throws {
        let document = Document(version: "1.0", axis: .layer, planes: [])
        DocumentStorageTests.assertError(.compressionUnavailable(.lzfse)) {
            try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse))
        }
        var binary = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        binary[11] = 1
        try DocumentStorageTests.updateChecksum(&binary)
        DocumentStorageTests.assertError(.compressionUnavailable(.lzfse)) { try DocumentStorageCodec.decode(binary) }
    }
    #endif
}
