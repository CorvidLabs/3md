import Foundation
import XCTest

@testable import ThreeMD

#if canImport(CryptoKit)
import CryptoKit
#endif


final class DocumentStorageTests: XCTestCase {
    func testCheckedInExtensionManifestDescribesTheActualSixArtifacts() throws {
        let manifest = try JSONDecoder().decode(
            DocumentExtensionFixtureManifest.self,
            from: Self.extensionFixture("manifest.json")
        )
        XCTAssertEqual(manifest.schema, "threemd-extension-fixtures-1")
        XCTAssertEqual(manifest.binaryContainerVersion, DocumentStorageCodec.containerVersion)
        XCTAssertEqual(manifest.compositionProfile, "3md-composition-1")
        let expected = Set([
            "canopy.3md", "canopy.3mdb", "canopy.lzfse.3mdb",
            "shared-grove.3md", "shared-grove.3mdb", "shared-grove.lzfse.3mdb",
        ])
        XCTAssertEqual(Set(manifest.files.map(\.file)), expected)
        XCTAssertEqual(manifest.files.count, expected.count)
        for file in manifest.files {
            // Do not follow arbitrary paths from a receipt; this is the checked-in fixture whitelist.
            guard expected.contains(file.file) else { return XCTFail("Unexpected fixture \(file.file)") }
            let bytes = try Self.extensionFixture(file.file)
            XCTAssertEqual(bytes.count, file.bytes, file.file)
            XCTAssertEqual(file.sha256.utf8.count, 64)
            XCTAssertTrue(file.sha256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
            #if canImport(CryptoKit)
            if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
                let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                XCTAssertEqual(digest, file.sha256, file.file)
            }
            #endif
        }
    }

    func testCheckedInPortableCanopyRoundTripsToItsReadableDocument() throws {
        let readable = try Self.extensionFixture("canopy.3md")
        let portable = try Self.extensionFixture("canopy.3mdb")
        let document = try DocumentStorageCodec.decode(readable)
        XCTAssertEqual(document.axis, .space)
        XCTAssertEqual(document.title, "Reusable canopy")
        XCTAssertEqual(document.metadata["material"], "mint")
        XCTAssertEqual(document.planes.map(\.body), [".#\n##", "##\n.#"])
        XCTAssertEqual(try DocumentStorageCodec.decode(portable), document)
        XCTAssertEqual(try DocumentStorageCodec.encode(document), readable)
        XCTAssertEqual(try DocumentStorageCodec.encode(document, format: .binary(compression: .none)), portable)
    }

    #if canImport(Compression)
    func testCheckedInCompressedCanopyRoundTripsToItsReadableDocument() throws {
        let readable = try Self.extensionFixture("canopy.3md")
        let compressed = try Self.extensionFixture("canopy.lzfse.3mdb")
        let document = try DocumentStorageCodec.decode(readable)
        XCTAssertEqual(try DocumentStorageCodec.decode(compressed), document)
        let encodedAgain = try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse))
        XCTAssertEqual(try DocumentStorageCodec.decode(encodedAgain), document)
    }
    #endif

    func testPortableContainerFixedVector() throws {
        let document = Document(version: "1.0", axis: .layer, planes: [])
        let expected = try Self.hex(
            "336d6462696e0d0a01000100000000000000000021000000000000002100000000000000"
                + "27cca0ba2d2d2d0a336d643a2022312e30220a617869733a20226c61796572220a2d2d2d0a"
        )
        let encoded = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        XCTAssertEqual(encoded, expected)
        XCTAssertEqual(try DocumentStorageCodec.decode(expected), document)
        XCTAssertEqual(
            try DocumentStorageChecksum.checksum(header: Data(), payload: Data("123456789".utf8)),
            0xCBF4_3926
        )
        XCTAssertEqual(DocumentStorageCodec.containerVersion, 1)
        XCTAssertEqual(DocumentStorageCodec.headerByteCount, 40)
        XCTAssertTrue(DocumentStorageCodec.isBinary(encoded))
        XCTAssertFalse(DocumentStorageCodec.isBinary(Data("3MDB".utf8)))
        XCTAssertFalse(DocumentStorageCodec.isBinary(Data("3mdbin\r".utf8)))
    }

    func testGeneralDocumentsPreserveUnicodeCustomAxesAndFractionalPositions() throws {
        let document = Document(
            version: "future-version",
            axis: Axis(rawValue: "temperature °c"),
            title: "研究 · Café 🐦",
            metadata: ["author": "'literal quotes'", "source": "C:\\notes\\\"draft\""],
            preamble: "# Overview\n\n[Later](3md://z/2.125)",
            planes: [
                Plane(
                    z: -1.25,
                    label: "Cold 雪",
                    x: -0.5,
                    y: 0.125,
                    attributes: ["style": "bold / green", "custom": "'preserved'"],
                    body: "```text\n@plane z=999\n```\n\n雪 → café"
                ),
                Plane(z: 2.125, label: "'Warm'", body: "~~~text\n@plane z=-99\n~~~\n\nDone"),
            ]
        )
        try DocumentStorageCodec.validate(document)
        for format in [DocumentStorageFormat.text, .binary(compression: .none)] {
            let encoded = try DocumentStorageCodec.encode(document, format: format)
            XCTAssertEqual(try DocumentStorageCodec.decode(encoded), document)
            XCTAssertEqual(try DocumentStorageCodec.encode(document, format: format), encoded)
        }
        for axis in [Axis.time, .depth, .layer, .frame, .space, Axis(rawValue: "another dimension")] {
            let value = Document(version: "0.1", axis: axis, planes: [Plane(z: 0.001, body: "body")])
            XCTAssertEqual(try DocumentStorageCodec.decode(DocumentStorageCodec.encode(value)), value)
        }
    }

    func testStorageRetainsTextGrammarAndLegacySerializerPreservesLiteralQuotes() throws {
        let source = "---\n3md: 9.5\ncustom: first\ncustom: last\n---\n@plane z=0 custom=first custom=last\nbody\n"
        let existing = try Parser().parse(source)
        XCTAssertEqual(try DocumentStorageCodec.decode(Data(source.utf8)), existing)
        XCTAssertEqual(existing.metadata["custom"], "last")
        XCTAssertEqual(existing.planes.first?.attributes["custom"], "last")
        let document = Document(version: "1.0", axis: .layer, title: "'quoted'", planes: [])
        let legacy = Serializer().render(document)
        XCTAssertTrue(legacy.contains("title: \"'quoted'\"\n"))
        let reparsed = try Parser().parse(legacy)
        XCTAssertEqual(reparsed, document)
        XCTAssertEqual(reparsed.title.map { Array($0.utf8) }, document.title.map { Array($0.utf8) })
        XCTAssertTrue(
            String(decoding: try DocumentStorageCodec.encode(document), as: UTF8.self).contains("title: \"'quoted'\"")
        )
        XCTAssertEqual(try DocumentStorageCodec.decode(DocumentStorageCodec.encode(document)), document)
    }

    func testBinaryDecodeHandlesDataSlices() throws {
        let document = Document(version: "1.0", axis: .space, planes: [Plane(z: 0.5, body: "Hello")])
        let encoded = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        var prefixed = Data([0, 1, 2, 3, 4])
        prefixed.append(encoded)
        let slice = prefixed.dropFirst(5)
        XCTAssertEqual(try DocumentStorageCodec.decode(slice), document)
    }

    func testDirectDocumentValidationRejectsLossyOrAmbiguousSerialization() throws {
        let values = [
            Document(version: "", axis: .layer, planes: []),
            Document(version: "1.0\naxis: time", axis: .layer, planes: []),
            Document(version: "1.0", axis: .layer, title: "first\rsecond", planes: []),
            Document(version: "1.0", axis: .layer, metadata: ["TITLE": "shadow"], planes: []),
            Document(version: "1.0", axis: .layer, metadata: ["a:b": "value"], planes: []),
            Document(version: "1.0", axis: .layer, metadata: ["# comment": "value"], planes: []),
            Document(version: "1.0", axis: .layer, preamble: "Only preamble", planes: []),
            Document(version: "1.0", axis: .layer, preamble: "```", planes: [Plane(z: 0, body: "body")]),
            Document(version: "1.0", axis: .layer, planes: [Plane(z: .infinity, body: "body")]),
            Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, x: .nan, body: "body")]),
            Document(version: "1.0", axis: .layer, planes: [Plane(z: -0.0, body: "a"), Plane(z: 0, body: "b")]),
            Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, attributes: ["Z": "1"], body: "body")]),
            Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, attributes: ["Style": "bold"], body: "body")]),
            Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, body: "\nbody\n")]),
            Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, body: "body\n@plane z=1\ninjected")]),
        ]
        for document in values {
            XCTAssertThrowsError(try DocumentStorageCodec.validate(document)) { error in
                guard case .invalidDocument = error as? DocumentStorageError else {
                    return XCTFail("Expected invalidDocument, got \(error)")
                }
            }
        }
    }

    func testAllHeaderFieldsAndCorruptionAreChecked() throws {
        let original = try DocumentStorageCodec.encode(
            Document(version: "1.0", axis: .layer, planes: []),
            format: .binary(compression: .none)
        )
        for count in 8..<40 {
            Self.assertError(.invalidContainer) { try DocumentStorageCodec.decode(Data(original.prefix(count))) }
        }
        var changed = original
        changed[8] = 2
        Self.assertError(.unsupportedVersion(2)) { try DocumentStorageCodec.decode(changed) }
        changed = original
        changed[10] = 2
        Self.assertError(.unsupportedPayloadKind(2)) { try DocumentStorageCodec.decode(changed) }
        changed = original
        changed[11] = 255
        Self.assertError(.unsupportedCompression(255)) { try DocumentStorageCodec.decode(changed) }
        changed = original
        changed[12] = 1
        Self.assertError(.unsupportedFlags(1)) { try DocumentStorageCodec.decode(changed) }
        changed = original
        changed[16] = 1
        Self.assertError(.nonzeroReserved) { try DocumentStorageCodec.decode(changed) }
        changed = original
        Self.write(UInt64.max, into: &changed, at: 28)
        Self.assertError(.oversizedOutput) { try DocumentStorageCodec.decode(changed) }
        changed = original
        Self.write(UInt64.max, into: &changed, at: 20)
        Self.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(changed) }
        changed = original
        changed.append(0)
        Self.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(changed) }
        changed = Data(original.dropLast())
        Self.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(changed) }
        changed = original
        changed[36] ^= 1
        Self.assertError(.checksumMismatch) { try DocumentStorageCodec.decode(changed) }
        changed = original
        changed[40] ^= 1
        Self.assertError(.checksumMismatch) { try DocumentStorageCodec.decode(changed) }
        changed = original
        Self.write(UInt64(32), into: &changed, at: 28)
        Self.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(changed) }
    }

    func testContainerPayloadMustBeValidUTF8AndThreeMDText() throws {
        let original = try DocumentStorageCodec.encode(
            Document(version: "1.0", axis: .layer, planes: []),
            format: .binary(compression: .none)
        )
        var invalid = try Self.replacingPayload(original, with: Data([0xFF]))
        Self.write(UInt64(1), into: &invalid, at: 28)
        try Self.updateChecksum(&invalid)
        Self.assertError(.invalidUTF8) { try DocumentStorageCodec.decode(invalid) }
        var missingHeader = try Self.replacingPayload(original, with: Data("Not 3md".utf8))
        Self.write(UInt64(7), into: &missingHeader, at: 28)
        try Self.updateChecksum(&missingHeader)
        Self.assertError(.invalidText(.missingFrontmatter)) { try DocumentStorageCodec.decode(missingHeader) }
    }

    static func assertError<Value>(
        _ expected: DocumentStorageError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Value
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? DocumentStorageError, expected, file: file, line: line)
        }
    }

    static func extensionFixture(_ name: String) throws -> Data {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = repository.appendingPathComponent("Examples/Extensions", isDirectory: true)
            .appendingPathComponent(name)
        return try Data(contentsOf: file)
    }

    static func replacingPayload(_ container: Data, with payload: Data) throws -> Data {
        var result = Data(container.prefix(40))
        result.append(payload)
        write(UInt64(payload.count), into: &result, at: 20)
        try updateChecksum(&result)
        return result
    }

    static func updateChecksum(_ container: inout Data) throws {
        let checksum = try DocumentStorageChecksum.checksum(
            header: Data(container.prefix(36)),
            payload: Data(container.dropFirst(40))
        )
        write(checksum, into: &container, at: 36)
    }

    static func write<Value: FixedWidthInteger>(_ value: Value, into data: inout Data, at offset: Int) {
        for index in 0..<MemoryLayout<Value>.size {
            data[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8))
        }
    }

    private static func hex(_ source: String) throws -> Data {
        var bytes: [UInt8] = []
        let digits = Array(source)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let byte = UInt8(String(digits[index...index + 1]), radix: 16) else {
                throw DocumentStorageError.invalidContainer
            }
            bytes.append(byte)
        }
        return Data(bytes)
    }
}

private struct DocumentExtensionFixtureManifest: Decodable {
    let schema: String
    let binaryContainerVersion: UInt16
    let compositionProfile: String
    let files: [File]

    struct File: Decodable {
        let file: String
        let bytes: Int
        let sha256: String
    }
}
