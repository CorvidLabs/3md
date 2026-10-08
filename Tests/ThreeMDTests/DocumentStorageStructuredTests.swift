import Foundation
import XCTest

@testable import ThreeMD

#if canImport(CryptoKit)
import CryptoKit
#endif

/// Payload kind 2 (SPEC 11.3): goldens, hostile vectors, the unit checklist of the ThreeMD 2.1 test plan (section 3),
/// property tests at CI volume (section 4) and the limit, cancellation and concurrency tests (section 5).
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal final class DocumentStorageStructuredTests: XCTestCase {
    // MARK: - Goldens

    internal func testEveryGoldenIsByteIdenticalAndDecodesToTheBoundedTextDecode() throws {
        let manifest = try StructuredFixtures.manifest()
        XCTAssertEqual(manifest.schema, "3md-structured-golden-1")
        XCTAssertEqual(manifest.files.count, 54)
        var textContainers = 0
        for entry in manifest.files {
            let bytes = try StructuredFixtures.data(entry.kind2File)
            XCTAssertEqual(bytes.count, entry.bytes, entry.id)
            XCTAssertEqual(bytes.count - DocumentStorageCodec.headerByteCount, entry.payloadBytes, entry.id)
            let expected = try StructuredFixtures.expectedDocument(entry)
            let limits = entry.kind == "composition" ? try StructuredFixtures.profileLimits() : .standard
            // 1. The writer reproduces the anchor from the bounded text decode of the canonical text.
            XCTAssertEqual(
                try DocumentStorageCodec.encode(expected, format: .binary(compression: .none), limits: limits),
                bytes,
                entry.id
            )
            // 2. The anchor decodes to exactly that document: bytes of every string, bits of every number.
            let decoded = try DocumentStorageCodec.decode(bytes)
            StructuredFixtures.assertExactlyEqual(decoded, expected, entry.id)
            XCTAssertEqual(decoded.planes.count, entry.planes, entry.id)
            XCTAssertEqual(try DocumentStorageCodec.encode(decoded).count, entry.canonicalBytes, entry.id)
            // 3. Re-encoding the decoded value is byte-identical (P2).
            XCTAssertEqual(try DocumentStorageCodec.encode(decoded, format: .binary(compression: .none)), bytes)
            // 4. Header inspection.
            let info = try XCTUnwrap(try DocumentStorageCodec.containerInfo(bytes), entry.id)
            XCTAssertEqual(info.containerVersion, 1, entry.id)
            XCTAssertEqual(info.payloadKind, .structuredDocument, entry.id)
            XCTAssertEqual(info.compression, 0, entry.id)
            XCTAssertEqual(info.flags, 0, entry.id)
            XCTAssertEqual(info.reserved, 0, entry.id)
            XCTAssertEqual(info.encodedPayloadByteCount, UInt64(entry.payloadBytes), entry.id)
            XCTAssertEqual(info.decodedPayloadByteCount, UInt64(entry.payloadBytes), entry.id)
            XCTAssertEqual(String(format: "%08x", info.checksum), entry.crc32, entry.id)
            // 5. The committed kind-1 file of the same case decodes to the same value and is rewritten byte for byte.
            if let file = entry.textContainerFile {
                let textContainer = try StructuredFixtures.data(file)
                StructuredFixtures.assertExactlyEqual(try DocumentStorageCodec.decode(textContainer), expected, file)
                XCTAssertEqual(try DocumentStorageCodec.encodeTextContainer(expected, limits: limits), textContainer)
                XCTAssertEqual(try DocumentStorageCodec.containerInfo(textContainer)?.payloadKind, .canonicalText)
                textContainers += 1
            }
            // 6. Composition envelopes reopen as the composition of the readable source.
            if entry.kind == "composition" {
                let composition = try DocumentCompositionCodec.decode(StructuredFixtures.data(entry.sourceFile))
                XCTAssertEqual(entry.compositionEnvelope, true, entry.id)
                XCTAssertEqual(try DocumentCompositionCodec.decode(bytes), composition, entry.id)
                XCTAssertEqual(
                    try DocumentCompositionCodec.encode(DocumentCompositionCodec.decode(bytes)),
                    try DocumentCompositionCodec.encode(composition),
                    entry.id
                )
            }
            // 7. The file is the committed one.
            #if canImport(CryptoKit)
            XCTAssertEqual(StructuredFixtures.sha256(bytes), entry.sha256, entry.id)
            #endif
        }
        XCTAssertEqual(textContainers, 24)
    }

    internal func testWorkedExamplesHoldTheBytesAndChecksumsOfTheSpecification() throws {
        let expectations: [(String, UInt32)] = [
            ("worked-document", 0x8A5B_3B70), ("worked-numbers", 0xDB5A_2326), ("worked-keys", 0x649E_B26B),
        ]
        for (name, checksum) in expectations {
            let document = try XCTUnwrap(StructuredFixtures.workedDocuments[name])
            let file = try StructuredFixtures.data("conformance/structured/\(name).3mdb")
            XCTAssertEqual(try DocumentStorageCodec.encode(document, format: .binary(compression: .none)), file, name)
            StructuredFixtures.assertExactlyEqual(try DocumentStorageCodec.decode(file), document, name)
            XCTAssertEqual(try DocumentStorageCodec.containerInfo(file)?.checksum, checksum, name)
            XCTAssertEqual(Array(file.prefix(11)), Array("3mdbin\r\n".utf8) + [1, 0, 2], name)
        }
        // SPEC 11.3.17 example 1, byte for byte.
        let example = try StructuredFixtures.data("conformance/structured/worked-document.3mdb")
        XCTAssertEqual(
            StructuredFixtures.payload(example),
            StructuredFixtures.hex(
                "01" + "03312e30" + "0474696d65" + "045765656b" + "01" + "056f776e6572" + "036f7073" + "02" + "41"
                    + "00"
                    + "034d6f6e" + "00" + "0923205374616e647570" + "46" + "0000c03f" + "03" + "03547565" + "01"
                    + "046b696e64" + "046e6f7465" + "0753686970206974"
            )
        )
        // SPEC 11.3.17 example 3: the decomposed key sorts before "z" by its first byte 0x65.
        let keys = try StructuredFixtures.data("conformance/structured/worked-keys.3mdb")
        XCTAssertEqual(Array(keys[45..<49]), [0x03, 0x65, 0xCC, 0x81])
        XCTAssertEqual(Array(keys[51..<53]), [0x01, 0x7A])
    }

    internal func testSizeGateHoldsForEveryExampleAndTheCorpus() throws {
        let sizes = try JSONDecoder().decode(
            SizeFixture.self,
            from: StructuredFixtures.data("conformance/structured/sizes.json")
        )
        XCTAssertEqual(sizes.perFile.count, 293)
        var canonicalTotal = 0
        var structuredTotal = 0
        for file in sizes.perFile {
            let document = try DocumentStorageCodec.decode(StructuredFixtures.data(file.file))
            let canonical = try DocumentStorageCodec.encode(document)
            let structured = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
            XCTAssertEqual(canonical.count, file.canonical, file.file)
            XCTAssertEqual(structured.count, file.kind2, file.file)
            XCTAssertLessThanOrEqual(structured.count, canonical.count, file.file)
            canonicalTotal += canonical.count
            structuredTotal += structured.count
        }
        XCTAssertEqual(canonicalTotal, sizes.examples.canonical)
        XCTAssertEqual(structuredTotal, sizes.examples.kind2)
        XCTAssertLessThanOrEqual(Double(structuredTotal), 0.98 * Double(canonicalTotal))
        let synthetic = try XCTUnwrap(sizes.large["synthetic-2000"])
        let sculpt = try XCTUnwrap(sizes.large["sculpt-4096-32x20"])
        XCTAssertLessThanOrEqual(Double(synthetic.kind2), 0.995 * Double(synthetic.canonical))
        XCTAssertLessThanOrEqual(Double(sculpt.kind2), 0.98 * Double(sculpt.canonical))
    }

    // MARK: - Vectors

    internal func testEveryVectorReportsItsCodeUnderItsLimits() throws {
        let fixture = try JSONDecoder().decode(
            VectorFixture.self,
            from: StructuredFixtures.data("conformance/structured/vectors.json")
        )
        XCTAssertEqual(fixture.schema, "3md-structured-vectors-1")
        XCTAssertEqual(fixture.vectors.count, 156)
        XCTAssertEqual(fixture.vectors.filter { $0.limits != nil }.count, 30)
        var checked = 0
        for vector in fixture.vectors {
            #if canImport(Compression)
            // The Swift LZFSE backend decodes this stream, so the vector holds only for readers without one.
            if vector.requiresNoLZFSE == true { continue }
            #endif
            let bytes = try StructuredFixtures.data(vector.file)
            let limits = try vector.limits?.decodeLimits() ?? .standard
            let outcome = StructuredFixtures.outcome { try DocumentStorageCodec.decode(bytes, limits: limits) }
            XCTAssertEqual(outcome, vector.expected, "\(vector.name) (\(vector.rule))")
            if outcome == "ok" {
                // An ok vector is the canonical encoding of its value under standard limits.
                let document = try DocumentStorageCodec.decode(bytes, limits: limits)
                XCTAssertEqual(try DocumentStorageCodec.encode(document, format: .binary(compression: .none)), bytes)
            }
            checked += 1
        }
        #if canImport(Compression)
        XCTAssertEqual(checked, 155)
        #else
        XCTAssertEqual(checked, 156)
        #endif
    }

    // MARK: - Numbers

    internal func testNumericPowersSpellAsTheSharedCanonicalNumbersAndRoundTripBitExactly() throws {
        let fixture = try JSONDecoder().decode(
            NumericPowers.self,
            from: StructuredFixtures.data("conformance/extensions/numeric-powers.json")
        )
        XCTAssertEqual(fixture.schema, "3md-canonical-numbers-1")
        XCTAssertEqual(fixture.vectors.count, 4_318)
        XCTAssertEqual(Set(fixture.vectors.map(\.bitPattern)).count, 4_316)
        var planes: [Plane] = []
        var seen = Set<UInt64>()
        for vector in fixture.vectors {
            let bits = try XCTUnwrap(UInt64(vector.bitPattern, radix: 16), vector.name)
            let value = Double(bitPattern: bits)
            XCTAssertEqual(value.formatted3MD(), vector.formatted, vector.name)
            if seen.insert(bits).inserted { planes.append(Plane(z: value, x: value, y: -value, body: "")) }
        }
        // One document holds every distinct value; kind 2 stores each bit for bit and its metrics spell each value.
        let document = Document(version: "1", axis: .layer, planes: planes)
        let text = try DocumentStorageCodec.encode(document)
        let binary = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        let decoded = try DocumentStorageCodec.decode(binary)
        XCTAssertEqual(decoded.planes.map { $0.z.bitPattern }, planes.map { $0.z.bitPattern })
        XCTAssertEqual(decoded.planes.map { $0.y?.bitPattern }, planes.map { $0.y?.bitPattern })
        let exact = try DocumentDecodeLimits(maximumDecodedBytes: text.count)
        XCTAssertEqual(try DocumentStorageCodec.decode(binary, limits: exact), decoded)
        let below = try DocumentDecodeLimits(maximumDecodedBytes: text.count - 1)
        DocumentStorageTests.assertError(.oversizedOutput) { try DocumentStorageCodec.decode(binary, limits: below) }
    }
}

// MARK: - Unit Checklist

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension DocumentStorageStructuredTests {
    internal func testVarEncodesMinimallyAndDecodesEveryBoundary() throws {
        let boundaries: [(Int, Int)] = [
            (0, 1), (127, 1), (128, 2), (16_383, 2), (16_384, 3), (2_097_151, 3), (2_097_152, 4), ((1 << 28) - 1, 4),
            (1 << 28, 5), (5 * 1_024 * 1_024 * 1_024, 5),
        ]
        for (value, length) in boundaries {
            var bytes: [UInt8] = []
            DocumentStorageStructured.appendVariable(value, to: &bytes)
            XCTAssertEqual(bytes.count, length, "\(value)")
            XCTAssertEqual(DocumentStorageStructured.variableLength(value), length, "\(value)")
            XCTAssertEqual(try Self.readVariable(bytes), value, "\(value)")
        }
        XCTAssertEqual(try Self.readVariable([0x80, 0x01]), 128)
        XCTAssertEqual(try Self.readVariable([0xFF, 0xFF, 0xFF, 0x7F]), (1 << 28) - 1)
        XCTAssertEqual(try Self.readVariable([0x80, 0x80, 0x80, 0x80, 0x01]), 1 << 28)
        XCTAssertEqual(try Self.readVariable([0xFF, 0xFF, 0xFF, 0xFF, 0x01]), (1 << 29) - 1)
        // V1: no byte remains. V2: a continuation on the last allowed byte. V3: a final zero byte.
        // A coordinate stays at 4 bytes, so the same 5-byte integer is rejected there.
        let rejections: [([UInt8], DocumentStorageError)] = [
            ([], .lengthMismatch), ([0x80], .lengthMismatch), ([0xFF, 0xFF, 0xFF], .lengthMismatch),
            ([0xFF, 0xFF, 0xFF, 0x80], .lengthMismatch),
            ([0x81, 0x00], .invalidContainer), ([0x80, 0x00], .invalidContainer),
            ([0x80, 0x80, 0x00], .invalidContainer), ([0x80, 0x80, 0x80, 0x00], .invalidContainer),
            ([0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80], .invalidContainer),
        ]
        for (bytes, expected) in rejections {
            DocumentStorageTests.assertError(expected) { try Self.readVariable(bytes) }
        }
        DocumentStorageTests.assertError(.invalidContainer) {
            try Self.readVariable([0xFF, 0xFF, 0xFF, 0xFF, 0x01], maximumBytes: 4)
        }
        let coordinate = try StructuredFixtures.container(
            [0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x00, 0x00]
        )
        DocumentStorageTests.assertError(.invalidContainer) { try DocumentStorageCodec.decode(coordinate) }
        // `ff ff ff 7f` as a string length is far past the remaining bytes (Str1).
        let file = try StructuredFixtures.container([0x00, 0xFF, 0xFF, 0xFF, 0x7F, 0x31, 0x00, 0x00, 0x00])
        DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(file) }
    }

    internal func testCountFramingDividesAndPrecedesThePlaneLimitAtTheLargestCounts() throws {
        // A Count is compared with floor(remaining / min) before anything is reserved, so the largest Var cannot
        // overflow 32-bit arithmetic or allocate; plane-count framing precedes the S8 plane limit.
        let largest: [UInt8] = [0xFF, 0xFF, 0xFF, 0x7F]
        let metadata = try StructuredFixtures.container([0x00, 0x01, 0x31, 0x00] + largest + [0x00])
        DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(metadata) }
        let planes = try StructuredFixtures.container([0x00, 0x01, 0x31, 0x00, 0x00] + largest + [0x01, 0x00, 0x00])
        DocumentStorageTests.assertError(.lengthMismatch) {
            try DocumentStorageCodec.decode(planes, limits: try DocumentDecodeLimits(maximumPlanes: 1))
        }
        let attributes = try StructuredFixtures.container([0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00] + largest)
        DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(attributes) }
        // Exactly at the edge: two planes of four bytes each in eight remaining bytes.
        let edge = try StructuredFixtures.container(
            [0x00, 0x01, 0x31, 0x00, 0x00, 0x02, 0x01, 0x00, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00]
        )
        XCTAssertEqual(try DocumentStorageCodec.decode(edge).planes.map(\.z), [0, 1])
        DocumentStorageTests.assertError(.tooManyPlanes) {
            try DocumentStorageCodec.decode(edge, limits: try DocumentDecodeLimits(maximumPlanes: 1))
        }
    }

    internal func testNumberFormsFollowTheCanonicalTableAndDecodeBitExactly() throws {
        let p27 = 134_217_728.0
        let cases: [(Double, Int)] = [
            (0, 1), (1, 1), (-1, 1), (p27 - 1, 1), (-p27, 1), (p27, 2), (-p27 - 1, 3), (-p27 * 2, 2),
            (16_777_217, 1), (0.5, 2), (0.1, 3), (1.5, 2), (9_007_199_254_740_992, 2), (9_007_199_254_740_994, 3),
            (5e-324, 3), (1.401298464324817e-45, 2), (Double(Float.greatestFiniteMagnitude), 2),
            (1.7976931348623157e308, 3), (0x1p-140, 2), (1e15, 3), (1e16, 3), (1e-7, 3), (-0.75, 2),
        ]
        for (value, form) in cases {
            XCTAssertEqual(DocumentStorageStructured.form(of: value), form, "\(value)")
            let document = Document(
                version: "1",
                axis: Axis(rawValue: ""),
                planes: [Plane(z: value, x: value, y: value, body: "")]
            )
            let file = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
            let payload = StructuredFixtures.payload(file)
            XCTAssertEqual(payload[6], UInt8(form | form << 2 | form << 4), "\(value)")
            let decoded = try XCTUnwrap(DocumentStorageCodec.decode(file).planes.first)
            XCTAssertEqual(decoded.z.bitPattern, value.bitPattern, "\(value)")
            XCTAssertEqual(decoded.x?.bitPattern, value.bitPattern, "\(value)")
            XCTAssertEqual(decoded.y?.bitPattern, value.bitPattern, "\(value)")
        }
        // Zigzag at the range edges: -2^27 is the largest Var, 2^27 - 1 the one below it.
        for (value, encoded) in [(-p27, [0xFF, 0xFF, 0xFF, 0x7F]), (p27 - 1, [0xFE, 0xFF, 0xFF, 0x7F]), (-1, [0x01])] {
            let document = Document(version: "1", axis: Axis(rawValue: ""), planes: [Plane(z: value, body: "")])
            let payload = StructuredFixtures.payload(
                try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
            )
            XCTAssertEqual(Array(payload[7..<(7 + encoded.count)]), encoded.map { UInt8($0) }, "\(value)")
        }
        // -0 has no encoding: the writer stores +0 (payload 00 01 31 00 00 01 01 00 00 01 61).
        let negativeZero = Document(version: "1", axis: Axis(rawValue: ""), planes: [Plane(z: -0.0, body: "a")])
        let file = try DocumentStorageCodec.encode(negativeZero, format: .binary(compression: .none))
        XCTAssertEqual(
            StructuredFixtures.payload(file),
            [0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x61]
        )
        XCTAssertEqual(try DocumentStorageCodec.decode(file).planes.first?.z.bitPattern, 0)
        // Non-finite values take forms 2 (infinities) and 3 (NaN) and the self-check rejects them.
        XCTAssertEqual(DocumentStorageStructured.form(of: .infinity), 2)
        XCTAssertEqual(DocumentStorageStructured.form(of: -.infinity), 2)
        XCTAssertEqual(DocumentStorageStructured.form(of: .nan), 3)
    }

    internal func testChecksumSlicingMatchesTheBytewiseDefinitionAtEveryAlignment() throws {
        XCTAssertEqual(
            try DocumentStorageChecksum.checksum(header: Data(), payload: Data("123456789".utf8)),
            0xCBF4_3926
        )
        var random = SeededGenerator(seed: 0x00C0_FFEE)
        let storage = (0..<320).map { _ in UInt8.random(in: 0...255, using: &random) }
        for _ in 0..<10_000 {
            let count = Int.random(in: 0...300, using: &random)
            let alignment = Int.random(in: 0..<8, using: &random)
            let reference = Self.bytewiseChecksum(storage[alignment..<(alignment + count)])
            let sliced = try storage.withUnsafeBytes { raw in
                try DocumentStorageChecksum.update(
                    0xFFFF_FFFF,
                    UnsafeRawBufferPointer(rebasing: raw[alignment..<(alignment + count)])
                ) ^ 0xFFFF_FFFF
            }
            XCTAssertEqual(sliced, reference, "length \(count) at offset \(alignment)")
        }
        // Every kind-1 anchor keeps its CRC.
        for entry in try StructuredFixtures.manifest().files {
            guard let file = entry.textContainerFile else { continue }
            let data = try StructuredFixtures.data(file)
            let computed = try DocumentStorageChecksum.checksum(header: data.prefix(36), payload: data.dropFirst(40))
            XCTAssertEqual(try DocumentStorageCodec.containerInfo(data)?.checksum, computed, file)
        }
    }

    internal func testUTF8ValidityIsRepairedDecodingThatEqualsTheInputBytes() throws {
        // String(decoding:) repairs ill-formed input; some repairs keep the length, so only byte equality is exact.
        XCTAssertEqual(Array(String(decoding: [0xF0, 0x90, 0x80], as: UTF8.self).utf8), [0xEF, 0xBF, 0xBD])
        XCTAssertEqual(
            Array(String(decoding: [0xF0, 0x90, 0x80, 0x41], as: UTF8.self).utf8),
            [0xEF, 0xBF, 0xBD, 0x41]
        )
        XCTAssertEqual(String(decoding: [0xC0, 0x80], as: UTF8.self).utf8.count, 6)
        XCTAssertEqual(String(decoding: [0xED, 0xA0, 0x80], as: UTF8.self).utf8.count, 9)
        let valid: [[UInt8]] = [
            [0x00], [0x7F], [0xC2, 0x80], [0xDF, 0xBF], [0xE0, 0xA0, 0x80], [0xE0, 0xBF, 0xBF], [0xE1, 0x80, 0x80],
            [0xEC, 0xBF, 0xBF], [0xED, 0x80, 0x80], [0xED, 0x9F, 0xBF], [0xEE, 0x80, 0x80], [0xEF, 0xBF, 0xBF],
            [0xEF, 0xBB, 0xBF], [0xF0, 0x90, 0x80, 0x80], [0xF0, 0xBF, 0xBF, 0xBF], [0xF1, 0x80, 0x80, 0x80],
            [0xF3, 0xBF, 0xBF, 0xBF], [0xF4, 0x80, 0x80, 0x80], [0xF4, 0x8F, 0xBF, 0xBF],
        ]
        let invalid: [[UInt8]] = [
            [0x80], [0xBF], [0xC0, 0x80], [0xC1, 0xBF], [0xC2], [0xC2, 0x41], [0xE0, 0x80, 0x80], [0xE0, 0x9F, 0xBF],
            [0xE1, 0x80], [0xED, 0xA0, 0x80], [0xED, 0xBF, 0xBF], [0xF0, 0x80, 0x80, 0x80], [0xF0, 0x8F, 0xBF, 0xBF],
            [0xF4, 0x90, 0x80, 0x80], [0xF5, 0x80, 0x80, 0x80], [0xFF], [0xFE], [0xF0, 0x90, 0x80],
            [0xF0, 0x90, 0x80, 0x41],
        ]
        for bytes in valid {
            let decoded = try DocumentStorageCodec.decode(Self.versionContainer(bytes))
            XCTAssertEqual(Array(decoded.version.utf8), bytes)
        }
        for bytes in invalid {
            DocumentStorageTests.assertError(.invalidUTF8) {
                try DocumentStorageCodec.decode(Self.versionContainer(bytes))
            }
        }
    }

    internal func testChunkedUTF8ValidationAgreesWithWholeValidationAcrossChunkBoundaries() throws {
        let scalar: [UInt8] = [0xF0, 0x9F, 0x98, 0x80]
        for length in [65_535, 65_536, 65_537, 200_000] {
            var boundaries = [65_536]
            if length > 131_072 { boundaries.append(131_072) }
            for boundary in boundaries {
                for start in (boundary - 3)...boundary where start + scalar.count <= length {
                    var body = [UInt8](repeating: 0x61, count: length)
                    body.replaceSubrange(start..<(start + 4), with: scalar)
                    var broken = body
                    broken[start + 3] = 0x61
                    for (bytes, wellFormed) in [(body, true), (broken, false)] {
                        let whole = String(decoding: bytes, as: UTF8.self).utf8.elementsEqual(bytes)
                        XCTAssertEqual(whole, wellFormed)
                        let file = try Self.bodyContainer(bytes)
                        let outcome = StructuredFixtures.outcome { try DocumentStorageCodec.decode(file) }
                        XCTAssertEqual(outcome, wellFormed ? "ok" : "invalidUTF8", "\(length) at \(start)")
                    }
                    let decoded = try DocumentStorageCodec.decode(Self.bodyContainer(body))
                    XCTAssertTrue(decoded.planes.first?.body.utf8.elementsEqual(body) == true)
                }
            }
            // A body that ends in the first two bytes of a three-byte scalar is ill-formed at every length.
            var truncated = [UInt8](repeating: 0x61, count: length)
            truncated.replaceSubrange((length - 2)..<length, with: [0xE2, 0x82])
            DocumentStorageTests.assertError(.invalidUTF8) {
                try DocumentStorageCodec.decode(Self.bodyContainer(truncated))
            }
        }
    }

    internal func testSegmentRulesMatchTheTextRoundTripOnHandCases() throws {
        let bodies: [(String, Bool)] = [
            ("", true), ("a\r", false), ("a\r\nb", false), ("a\rb", true), ("\na", false), ("a\n", false),
            (" \na", false), ("a\n\u{A0}", false), ("\u{3000}\na", false), ("@plane", false), ("a\n@plane z=2", false),
            ("a\n@plane\tz", false), (" @plane", true), ("@planet", true), ("a\n@plane\u{A0}z", true),
            ("```\n~~~\n@plane\n```", true), ("~~~\nx\n~~~\n@plane", false), ("\u{A0}```\n@plane\n\u{A0}```", true),
            ("\u{3000}~~~\n@plane z=1\n~~~", true), ("\u{FEFF}a", true), ("a\u{0}b", true), ("```", true),
            ("~~~text\n```\n@plane", true), ("a\n\n\nb", true), ("\u{2028}", true), ("\u{85}", true),
            ("\u{200B}", false),
        ]
        for (body, accepted) in bodies {
            let final = Document(version: "1", axis: .layer, planes: [Plane(z: 0, body: body)])
            XCTAssertEqual(Self.accepts(final), accepted, "final body \(body.debugDescription)")
            XCTAssertEqual(Self.accepts(final), Self.validates(final), "final body \(body.debugDescription)")
            let first = Document(version: "1", axis: .layer, planes: [Plane(z: 0, body: body), Plane(z: 1, body: "b")])
            XCTAssertEqual(Self.accepts(first), Self.validates(first), "non-final body \(body.debugDescription)")
            let preamble = Document(version: "1", axis: .layer, preamble: body, planes: [Plane(z: 0, body: "b")])
            XCTAssertEqual(Self.accepts(preamble), Self.validates(preamble), "preamble \(body.debugDescription)")
        }
        // G6: an open fence swallows the next directive unless the body is final; the preamble is never final.
        let open = Document(version: "1", axis: .layer, planes: [Plane(z: 0, body: "```"), Plane(z: 1, body: "b")])
        XCTAssertFalse(Self.accepts(open))
        XCTAssertFalse(
            Self.accepts(Document(version: "1", axis: .layer, preamble: "~~~", planes: [Plane(z: 0, body: "")]))
        )
        // G1: an empty preamble collapses to absent.
        XCTAssertFalse(
            Self.accepts(Document(version: "1", axis: .layer, preamble: "", planes: [Plane(z: 0, body: "")]))
        )
    }

    internal func testSegmentRulesAgreeWithTheTextParserOnRandomBodies() throws {
        let fragments = [
            "a", "b", " ", "\t", "\u{A0}", "\u{3000}", "\u{2028}", "\u{200B}", "\u{85}", "\n", "\n", "\r", "```", "~~~",
            "@plane", "@plane ", "@planet", "@plane\t", "#", "\u{FEFF}", "\u{0}", "é", "e\u{301}", "'", "\"",
        ]
        var random = SeededGenerator(seed: 0x5E6_0001)
        var accepted = 0
        for index in 0..<Self.volume(100_000) {
            var body = ""
            for _ in 0..<Int.random(in: 0...8, using: &random) { body += fragments.randomElement(using: &random) ?? "" }
            let document: Document
            switch index % 3 {
            case 0: document = Document(version: "1", axis: .layer, planes: [Plane(z: 0, body: body)])
            case 1:
                document = Document(
                    version: "1",
                    axis: .layer,
                    planes: [Plane(z: 0, body: body), Plane(z: 1, body: "")]
                )
            default: document = Document(version: "1", axis: .layer, preamble: body, planes: [Plane(z: 0, body: "")])
            }
            let binary = Self.accepts(document)
            XCTAssertEqual(binary, Self.validates(document), body.debugDescription)
            if binary { accepted += 1 }
        }
        XCTAssertGreaterThan(accepted, 0)
    }

    internal func testMetricsMatchTheTextWriterAtEveryExampleLimitEdge() throws {
        let examples = StructuredFixtures.root.appendingPathComponent("Examples")
        let names = try FileManager.default.contentsOfDirectory(atPath: examples.path).filter { $0.hasSuffix(".3md") }
        XCTAssertEqual(names.count, 293)
        for name in names.sorted() {
            let document = try DocumentStorageCodec.decode(Data(contentsOf: examples.appendingPathComponent(name)))
            let text = try DocumentStorageCodec.encode(document)
            let binary = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
            let total = text.count
            let lines = text.reduce(1) { $0 + ($1 == 10 ? 1 : 0) }
            // L4: T is the canonical text length.
            XCTAssertNoThrow(
                try DocumentStorageCodec.decode(binary, limits: DocumentDecodeLimits(maximumDecodedBytes: total))
            )
            DocumentStorageTests.assertError(.oversizedOutput) {
                try DocumentStorageCodec.decode(binary, limits: DocumentDecodeLimits(maximumDecodedBytes: total - 1))
            }
            // L5: Lines is the physical line count of the canonical text.
            XCTAssertLessThanOrEqual(lines, DocumentDecodeLimits.standard.maximumLines, name)
            XCTAssertNoThrow(try DocumentStorageCodec.decode(binary, limits: DocumentDecodeLimits(maximumLines: lines)))
            DocumentStorageTests.assertError(.tooManyLines) {
                try DocumentStorageCodec.decode(binary, limits: DocumentDecodeLimits(maximumLines: lines - 1))
            }
            // L1 to L3 and Str2: the smallest accepted record limit equals the text policy's.
            var low = 1
            var high = total
            while low < high {
                let middle = (low + high) / 2
                let limits = try DocumentDecodeLimits(maximumRecordBytes: middle)
                if (try? DocumentStorageCodec.decode(binary, limits: limits)) != nil {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            XCTAssertNoThrow(
                try DocumentStorageCodec.validate(document, limits: DocumentDecodeLimits(maximumRecordBytes: low))
            )
            if low > 1 {
                let below = try DocumentDecodeLimits(maximumRecordBytes: low - 1)
                DocumentStorageTests.assertError(.oversizedRecord) {
                    try DocumentStorageCodec.decode(binary, limits: below)
                }
                XCTAssertThrowsError(try DocumentStorageCodec.validate(document, limits: below), name)
            }
        }
    }

    /// T, Lines, DirLen and the frontmatter lengths against the 2.0 text writer at every limit edge of 10,000
    /// generated documents that the writer accepts (seed 0x3D3D2107): on each side of each edge the binary decode,
    /// the bounded text decode of the canonical text and `validate` give the same outcome.
    internal func testMetricsMatchTheTextWriterAtTheLimitEdgesOfGeneratedDocuments() throws {
        var generator = DocumentGenerator(seed: 0x3D3D_2107)
        var checked = 0
        var edgesChecked = 0
        var disagreements: [String] = []
        while checked < Self.volume(10_000) {
            let document = generator.document()
            guard let binary = try? DocumentStorageCodec.encode(document, format: .binary(compression: .none)) else {
                continue
            }
            checked += 1
            let text = try DocumentStorageCodec.encode(document)
            let total = text.count
            let lines = text.reduce(1) { $0 + ($1 == 10 ? 1 : 0) }
            // The smallest record limit the binary decode accepts; L1 makes it at least 3.
            var low = 1
            var high = total
            while low < high {
                let middle = (low + high) / 2
                let limits = try DocumentDecodeLimits(maximumRecordBytes: middle)
                if (try? DocumentStorageCodec.decode(binary, limits: limits)) != nil {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            var edges: [(name: String, limits: DocumentDecodeLimits, expected: String)] = [
                ("Dmax = T", try DocumentDecodeLimits(maximumDecodedBytes: total), "ok"),
                ("Dmax = T - 1", try DocumentDecodeLimits(maximumDecodedBytes: total - 1), "oversizedOutput"),
                ("Lmax = Lines", try DocumentDecodeLimits(maximumLines: lines), "ok"),
                ("Lmax = Lines - 1", try DocumentDecodeLimits(maximumLines: lines - 1), "tooManyLines"),
                ("R = smallest", try DocumentDecodeLimits(maximumRecordBytes: low), "ok"),
                ("R = smallest - 1", try DocumentDecodeLimits(maximumRecordBytes: low - 1), "oversizedRecord"),
            ]
            let planes = document.planes.count
            if planes > 0 { edges.append(("Pmax = P", try DocumentDecodeLimits(maximumPlanes: planes), "ok")) }
            if planes > 1 {
                edges.append(("Pmax = P - 1", try DocumentDecodeLimits(maximumPlanes: planes - 1), "tooManyPlanes"))
            }
            for edge in edges {
                let limits = edge.limits
                let fromBinary = StructuredFixtures.outcome { try DocumentStorageCodec.decode(binary, limits: limits) }
                let fromText = StructuredFixtures.outcome { try DocumentStorageCodec.decode(text, limits: limits) }
                let validated = (try? DocumentStorageCodec.validate(document, limits: limits)) != nil
                edgesChecked += 1
                if fromBinary != edge.expected || fromText != edge.expected || validated != (edge.expected == "ok") {
                    disagreements.append(
                        "\(checked) \(edge.name): binary \(fromBinary), text \(fromText), validate \(validated), "
                            + "expected \(edge.expected): \(document)"
                    )
                }
            }
        }
        XCTAssertEqual(disagreements.count, 0, disagreements.prefix(5).joined(separator: "\n"))
        XCTAssertGreaterThan(edgesChecked, 6 * Self.volume(10_000))
    }

    /// R9 compares an attribute key longer than 65,536 bytes with its `lowercased()` chunk by chunk, split at scalar
    /// boundaries, and finds an uppercase scalar that straddles a chunk edge (SPEC 11.3.6.5, 11.3.13).
    internal func testLongAttributeKeysAreComparedWithTheirLowercaseAcrossChunkEdges() throws {
        let block = DocumentStorageStructured.block
        let keys = [
            // U+00C9 (C3 89) and U+00E9 (C3 A9) straddle the first chunk edge.
            String(repeating: "a", count: block - 1) + "\u{C9}",
            String(repeating: "a", count: block - 1) + "\u{E9}",
            // U+1E9E (E1 BA 9E) straddles it two bytes in; U+00DF is its lowercase.
            String(repeating: "a", count: block - 2) + "\u{1E9E}x",
            String(repeating: "a", count: block - 2) + "\u{DF}x",
            // A final sigma two chunks in: `lowercased()` maps each scalar on its own.
            String(repeating: "\u{E9}", count: block) + "\u{3A3}",
            String(repeating: "\u{E9}", count: block) + "\u{3C3}",
        ]
        for key in keys {
            var payload: [UInt8] = [0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x01]
            DocumentStorageStructured.appendVariable(key.utf8.count, to: &payload)
            payload += Array(key.utf8) + [0x00, 0x00]
            let file = try StructuredFixtures.container(payload)
            let document = Document(
                version: "1",
                axis: Axis(rawValue: ""),
                planes: [Plane(z: 0, attributes: [key: ""], body: "")]
            )
            let lowercase = key.lowercased().utf8.elementsEqual(key.utf8)
            XCTAssertGreaterThan(key.utf8.count, block)
            if lowercase {
                StructuredFixtures.assertExactlyEqual(try DocumentStorageCodec.decode(file), document, "long key")
                XCTAssertEqual(try DocumentStorageCodec.encode(document, format: .binary(compression: .none)), file)
                XCTAssertNoThrow(try DocumentStorageCodec.validate(document))
            } else {
                Self.assertInvalidDocument { try DocumentStorageCodec.decode(file) }
                Self.assertInvalidDocument {
                    try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
                }
                XCTAssertThrowsError(try DocumentStorageCodec.validate(document))
            }
        }
    }

    internal func testKeysAreOrderedByUTF8BytesWhichIsCodePointOrder() throws {
        let scalars: [Unicode.Scalar] = [
            "a", "B", "z", "\u{E9}", "\u{FF61}", "\u{E000}", "\u{1F600}", "\u{10000}", "~",
        ]
        var random = SeededGenerator(seed: 0x0E_DE12)
        for _ in 0..<2_000 {
            func key() -> String {
                var text = ""
                for _ in 0..<Int.random(in: 1...3, using: &random) {
                    text.unicodeScalars.append(scalars.randomElement(using: &random) ?? "a")
                }
                return text
            }
            let first = key()
            let second = key()
            XCTAssertEqual(
                first.utf8.lexicographicallyPrecedes(second.utf8),
                first.unicodeScalars.map(\.value).lexicographicallyPrecedes(second.unicodeScalars.map(\.value))
            )
        }
        // UTF-16 order would put U+FF61 after U+1F600; byte order puts it first, and the reader enforces that.
        let document = Document(
            version: "1",
            axis: .layer,
            metadata: ["\u{1F600}": "1", "\u{FF61}": "2", "B": "3", "a": "4", "e\u{301}": "5", "z": "6"],
            planes: []
        )
        let file = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        let payload = StructuredFixtures.payload(file)
        let order = ["B", "a", "e\u{301}", "z", "\u{FF61}", "\u{1F600}"].map { Array($0.utf8) }
        var position = payload.firstIndex(of: 0x06).map { $0 + 1 } ?? 0
        for key in order {
            XCTAssertEqual(Int(payload[position]), key.count)
            XCTAssertEqual(Array(payload[(position + 1)..<(position + 1 + key.count)]), key)
            position += 1 + key.count + 2
        }
        StructuredFixtures.assertExactlyEqual(try DocumentStorageCodec.decode(file), document, "byte order")
        // A dictionary built from decomposed and precomposed literals keeps one entry (Swift's writer vector).
        var merged: [String: String] = [:]
        merged["e\u{301}"] = "first"
        merged["\u{E9}"] = "last"
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first.map { Array($0.key.utf8) }, [0x65, 0xCC, 0x81])
        XCTAssertEqual(merged.first?.value, "last")
        XCTAssertNoThrow(
            try DocumentStorageCodec.encode(
                Document(version: "1", axis: .layer, metadata: merged, planes: []),
                format: .binary(compression: .none)
            )
        )
    }

    internal func testCanonicallyEquivalentKeysInOnePayloadMapAreInvalidDocuments() throws {
        // e + U+0301 (65 CC 81) before U+00E9 (C3 A9); K (4B) before U+212A (E2 84 AA).
        let metadata = try StructuredFixtures.container(
            [0x00, 0x01, 0x31, 0x00, 0x02, 0x03, 0x65, 0xCC, 0x81, 0x00, 0x02, 0xC3, 0xA9, 0x00, 0x00]
        )
        Self.assertInvalidDocument { try DocumentStorageCodec.decode(metadata) }
        let attributes = try StructuredFixtures.container(
            [
                0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x02, 0x01, 0x4B, 0x00, 0x03, 0xE2, 0x84, 0xAA, 0x00,
                0x00,
            ]
        )
        Self.assertInvalidDocument { try DocumentStorageCodec.decode(attributes) }
    }

    internal func testUnicodeSkewVectorsFollowTheRuntimeUnicodeData() throws {
        // Single-port vectors outside the Unicode 13.0 set (SPEC 11.3.15), recorded for Unicode 16 and later data.
        guard Unicode.Scalar(0x897)?.properties.age != nil else { throw XCTSkip("Unicode 16 data is unavailable.") }
        let ordered = Array("a\u{316}\u{897}".utf8)
        let reordered = Array("a\u{897}\u{316}".utf8)
        XCTAssertTrue(ordered.lexicographicallyPrecedes(reordered))
        let pair = try StructuredFixtures.container(
            [0x00, 0x01, 0x31, 0x00, 0x02, UInt8(ordered.count)] + ordered + [0x00, UInt8(reordered.count)] + reordered
                + [0x00, 0x00]
        )
        Self.assertInvalidDocument { try DocumentStorageCodec.decode(pair) }
        for (key, accepted) in [("\u{10D50}", false), ("\u{10D70}", true)] {
            let document = Document(
                version: "1",
                axis: .layer,
                planes: [Plane(z: 0, attributes: [key: "v"], body: "")]
            )
            XCTAssertEqual(Self.accepts(document), accepted, key.debugDescription)
            XCTAssertEqual(Self.validates(document), accepted, key.debugDescription)
        }
    }

    internal func testFrozenWhitespaceSetHoldsExactlyNineteenScalars() throws {
        let members: [UInt32] = [
            0x09, 0x20, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009,
            0x200A, 0x200B, 0x202F, 0x205F, 0x3000,
        ]
        XCTAssertEqual(members.count, 19)
        var found: [UInt32] = []
        for value in UInt32(0)...0x10FFFF where ThreeMDWhitespace.contains(value) { found.append(value) }
        XCTAssertEqual(found, members)
        for value in [0x85, 0x0B, 0x0C, 0x180E, 0x2028, 0x2029, 0xFEFF, 0x0A, 0x0D] as [UInt32] {
            XCTAssertFalse(ThreeMDWhitespace.contains(value), String(value, radix: 16))
        }
        for value in members {
            let scalar = String(Character(Unicode.Scalar(value) ?? " "))
            XCTAssertEqual(ThreeMDWhitespace.trimmed(scalar + "x" + scalar), "x")
            XCTAssertEqual(Axis(rawValue: scalar + "Time" + scalar).rawValue, "time")
            let source = "---\n3md: 1\naxis: layer\nkey: " + scalar + "value" + scalar + "\n---\n@plane z=0\nbody\n"
            XCTAssertEqual(try Parser().parse(source).metadata["key"], "value", String(value, radix: 16))
            // Scalar-wise: a combining mark after a W scalar stays.
            XCTAssertEqual(
                Array(ThreeMDWhitespace.trimmed(scalar + "\u{301}a").unicodeScalars.map(\.value)),
                [0x301, 0x61]
            )
        }
        for value in [0x85, 0x0B, 0x0C, 0x180E, 0x2028, 0xFEFF] as [UInt32] {
            let scalar = String(Character(Unicode.Scalar(value) ?? " "))
            XCTAssertEqual(ThreeMDWhitespace.trimmed(scalar + "x" + scalar), scalar + "x" + scalar)
            XCTAssertEqual(Axis(rawValue: scalar + "time").rawValue, scalar + "time")
            // The excluded scalars are content: a kind-2 axis may begin with them.
            let document = Document(version: "1", axis: Axis(rawValue: scalar + "a"), planes: [])
            XCTAssertTrue(Self.accepts(document), String(value, radix: 16))
        }
        XCTAssertTrue(ThreeMDWhitespace.isBlank(""))
        XCTAssertTrue(ThreeMDWhitespace.isBlank("\u{3000}\t \u{200B}"))
        XCTAssertFalse(ThreeMDWhitespace.isBlank("\u{2028}"))
    }

    internal func testContainerInfoReportsRawHeaderFieldsWithoutValidation() throws {
        XCTAssertNil(try DocumentStorageCodec.containerInfo(Data()))
        XCTAssertNil(try DocumentStorageCodec.containerInfo(Data("---\n3md: 1\n---\n".utf8)))
        XCTAssertNil(try DocumentStorageCodec.containerInfo(Data("3MDB".utf8)))
        XCTAssertNil(try DocumentStorageCodec.containerInfo(Data("3mdbin\r".utf8)))
        let file = try StructuredFixtures.data("conformance/structured/worked-document.3mdb")
        for count in 8..<40 {
            DocumentStorageTests.assertError(.invalidContainer) {
                try DocumentStorageCodec.containerInfo(file.prefix(count))
            }
        }
        var changed = file
        changed[8] = 9
        changed[10] = 7
        changed[11] = 200
        changed[12] = 5
        changed[16] = 1
        DocumentStorageTests.write(UInt64(0xDEAD), into: &changed, at: 20)
        DocumentStorageTests.write(UInt64(1) << 40, into: &changed, at: 28)
        let info = try XCTUnwrap(try DocumentStorageCodec.containerInfo(changed.prefix(40)))
        XCTAssertEqual(info.containerVersion, 9)
        XCTAssertEqual(info.payloadKind, DocumentPayloadKind(rawValue: 7))
        XCTAssertEqual(info.payloadKind.description, "reserved(7)")
        XCTAssertFalse(DocumentStorageCodec.supportedPayloadKinds.contains(info.payloadKind))
        XCTAssertEqual(info.compression, 200)
        XCTAssertEqual(info.flags, 5)
        XCTAssertEqual(info.reserved, 1)
        XCTAssertEqual(info.encodedPayloadByteCount, 0xDEAD)
        XCTAssertEqual(info.decodedPayloadByteCount, 1 << 40)
        XCTAssertEqual(info.checksum, 0x8A5B_3B70)
        // A slice with a nonzero start index reads the same header.
        let slice = (Data([1, 2, 3]) + file).dropFirst(3)
        XCTAssertEqual(try DocumentStorageCodec.containerInfo(slice), try DocumentStorageCodec.containerInfo(file))
        XCTAssertEqual(DocumentStorageCodec.supportedPayloadKinds, [.canonicalText, .structuredDocument])
        XCTAssertEqual(DocumentPayloadKind.canonicalText.rawValue, 1)
        XCTAssertEqual(DocumentPayloadKind.structuredDocument.rawValue, 2)
        XCTAssertEqual(DocumentPayloadKind.canonicalText.description, "canonicalText")
        XCTAssertEqual(DocumentPayloadKind.structuredDocument.description, "structuredDocument")
    }

    internal func testWriterCapsTheUncompressedContainerAtTheEncodedLimit() throws {
        let document = Document(version: "1.0", axis: .space, planes: [Plane(z: 0.5, label: "L", body: "Body")])
        let file = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        let exact = try DocumentDecodeLimits(maximumEncodedBytes: file.count)
        XCTAssertEqual(
            try DocumentStorageCodec.encode(document, format: .binary(compression: .none), limits: exact),
            file
        )
        XCTAssertEqual(try DocumentStorageCodec.decode(file, limits: exact), document)
        for maximum in [file.count - 1, 41, 40, 39, 1] {
            let limits = try DocumentDecodeLimits(maximumEncodedBytes: maximum)
            DocumentStorageTests.assertError(.oversizedInput) {
                try DocumentStorageCodec.encode(document, format: .binary(compression: .none), limits: limits)
            }
        }
        // W1b precedes everything else; the text-container writer keeps the 2.0 order (validation first).
        let invalid = Document(version: "", axis: .layer, planes: [])
        let tiny = try DocumentDecodeLimits(maximumEncodedBytes: 39)
        DocumentStorageTests.assertError(.oversizedInput) {
            try DocumentStorageCodec.encode(invalid, format: .binary(compression: .none), limits: tiny)
        }
        Self.assertInvalidDocument { try DocumentStorageCodec.encodeTextContainer(invalid, limits: tiny) }
        // A non-finite coordinate is emitted and then rejected by the self-check, or refused by the cap first.
        let infinite = Document(version: "1", axis: .layer, planes: [Plane(z: .infinity, body: "")])
        Self.assertInvalidDocument { try DocumentStorageCodec.encode(infinite, format: .binary(compression: .none)) }
        DocumentStorageTests.assertError(.oversizedInput) {
            try DocumentStorageCodec.encode(
                infinite,
                format: .binary(compression: .none),
                limits: try DocumentDecodeLimits(maximumEncodedBytes: 50)
            )
        }
        // The structured precedence applies to invalid documents: Phase S fields before Phase L limits.
        let carriageReturn = Document(version: "1", axis: .layer, planes: [Plane(z: 0, body: "a\r")])
        let lowDecoded = try DocumentDecodeLimits(maximumDecodedBytes: 20)
        Self.assertInvalidDocument {
            try DocumentStorageCodec.encode(carriageReturn, format: .binary(compression: .none), limits: lowDecoded)
        }
        DocumentStorageTests.assertError(.oversizedOutput) {
            try DocumentStorageCodec.validate(carriageReturn, limits: lowDecoded)
        }
    }

    internal func testEightyEmptyPlanesDecodeUnderAnEncodedLimitTheirTextWouldExceed() throws {
        let planes = (0..<80).map { Plane(z: Double($0), body: "") }
        let document = Document(version: "1", axis: Axis(rawValue: ""), planes: planes)
        let text = try DocumentStorageCodec.encode(document)
        let file = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        XCTAssertEqual(text.count, 1_056)
        XCTAssertEqual(file.count, 382)
        let limits = try DocumentDecodeLimits(maximumEncodedBytes: 1_000)
        XCTAssertLessThan(file.count, 1_000)
        XCTAssertEqual(try DocumentStorageCodec.decode(file, limits: limits), document)
        XCTAssertEqual(
            try DocumentStorageCodec.encode(document, format: .binary(compression: .none), limits: limits),
            file
        )
        DocumentStorageTests.assertError(.oversizedInput) { try DocumentStorageCodec.encode(document, limits: limits) }
    }

    internal func testDecodedLengthBoundPrecedesTheChecksumAndDecompression() throws {
        let file = try StructuredFixtures.data("conformance/structured/worked-document.3mdb")
        let payload = file.count - 40
        // Kind 2: min(Emax - 40, 2 * Dmax); the CRC is never computed past the bound.
        var corrupt = file
        corrupt[36] ^= 0xFF
        let atBound = try DocumentDecodeLimits(maximumEncodedBytes: file.count, maximumDecodedBytes: (payload + 1) / 2)
        DocumentStorageTests.assertError(.checksumMismatch) {
            try DocumentStorageCodec.decode(corrupt, limits: atBound)
        }
        DocumentStorageTests.assertError(.oversizedOutput) { try DocumentStorageCodec.decode(file, limits: atBound) }
        let belowBound = try DocumentDecodeLimits(maximumDecodedBytes: payload / 2)
        DocumentStorageTests.assertError(.oversizedOutput) {
            try DocumentStorageCodec.decode(corrupt, limits: belowBound)
        }
        DocumentStorageTests.assertError(.checksumMismatch) { try DocumentStorageCodec.decode(corrupt) }
        // Kind 1 keeps its 2.0 bound, Dmax.
        let document = try DocumentStorageCodec.decode(file)
        let textContainer = try DocumentStorageCodec.encodeTextContainer(document)
        let text = try DocumentStorageCodec.encode(document)
        let kind1Limits = try DocumentDecodeLimits(maximumDecodedBytes: text.count - 1)
        DocumentStorageTests.assertError(.oversizedOutput) {
            try DocumentStorageCodec.decode(textContainer, limits: kind1Limits)
        }
    }

    internal func testTextContainerWriterKeepsTheTwoZeroBytesAndHeaderChecks() throws {
        let document = Document(version: "1.0", axis: .layer, planes: [])
        let expected = try StructuredFixtures.container(
            Array("---\n3md: \"1.0\"\naxis: \"layer\"\n---\n".utf8),
            kind: 1
        )
        XCTAssertEqual(try DocumentStorageCodec.encodeTextContainer(document), expected)
        XCTAssertEqual(try DocumentStorageCodec.decode(expected), document)
        // The kind-2 fixed vector of the test plan (53 bytes, CRC 0xAF46E95D).
        let structured = Data(
            StructuredFixtures.hex(
                "336d6462696e0d0a0100020000000000000000000d000000000000000d00000000000000"
                    + "5de946af0003312e30056c617965720000"
            )
        )
        XCTAssertEqual(try DocumentStorageCodec.encode(document, format: .binary(compression: .none)), structured)
        XCTAssertEqual(try DocumentStorageCodec.decode(structured), document)
        XCTAssertEqual(try DocumentStorageCodec.containerInfo(structured)?.checksum, 0xAF46_E95D)
    }

    internal func testDecodeAcceptsDataSlicesWithANonzeroStartIndex() throws {
        let document = Document(
            version: "1.0",
            axis: .space,
            metadata: ["é": "v"],
            planes: [Plane(z: 0.5, label: "雪", attributes: ["kind": "a'b"], body: "Hello\nworld")]
        )
        for file in [
            try DocumentStorageCodec.encode(document, format: .binary(compression: .none)),
            try DocumentStorageCodec.encodeTextContainer(document),
        ] {
            let slice = (Data(repeating: 0xAA, count: 7) + file + Data([0xBB])).dropFirst(7).dropLast()
            XCTAssertNotEqual(slice.startIndex, 0)
            StructuredFixtures.assertExactlyEqual(try DocumentStorageCodec.decode(slice), document, "slice")
            XCTAssertEqual(try DocumentStorageCodec.containerInfo(slice), try DocumentStorageCodec.containerInfo(file))
        }
    }
}

// MARK: - Properties

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension DocumentStorageStructuredTests {
    /// P1 totality, P2 canonical bijection and P3 text agreement over byte mutations of every anchor and of the
    /// kind-2 Examples, with lengths and CRC resealed (seed 0x3D3D2101).
    internal func testMutatedFilesGiveOneTypedOutcomeAndAcceptedOnesAreCanonical() throws {
        var bases: [[UInt8]] = []
        for entry in try StructuredFixtures.manifest().files {
            bases.append(StructuredFixtures.payload(try StructuredFixtures.data(entry.kind2File)))
        }
        let examples = StructuredFixtures.root.appendingPathComponent("Examples")
        for name in try FileManager.default.contentsOfDirectory(atPath: examples.path).sorted()
        where name.hasSuffix(".3md") {
            let document = try DocumentStorageCodec.decode(Data(contentsOf: examples.appendingPathComponent(name)))
            bases.append(
                StructuredFixtures.payload(
                    try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
                )
            )
        }
        var random = SeededGenerator(seed: 0x3D3D_2101)
        var outcomes: [String: Int] = [:]
        for _ in 0..<Self.volume(10_000) {
            let base = bases.randomElement(using: &random) ?? []
            let file = try StructuredFixtures.container(Self.mutate(base, using: &random))
            do {
                let document = try DocumentStorageCodec.decode(file)
                outcomes["ok", default: 0] += 1
                // P2: the accepted bytes are the canonical encoding of their value.
                XCTAssertEqual(try DocumentStorageCodec.encode(document, format: .binary(compression: .none)), file)
                // P3: the value equals the bounded text decode of its canonical text.
                let text = try DocumentStorageCodec.encode(document)
                StructuredFixtures.assertExactlyEqual(try DocumentStorageCodec.decode(text), document, "P3")
            } catch let error as DocumentStorageError {
                outcomes[StructuredFixtures.code(error), default: 0] += 1
            }
        }
        XCTAssertGreaterThan(outcomes["ok"] ?? 0, 100, "\(outcomes)")
        XCTAssertGreaterThan(outcomes.count, 3, "\(outcomes)")
    }

    /// P5: whatever the writer accepts under limits L decodes under L to the normalized document (seed 0x3D3D2105).
    internal func testWriterOutputDecodesUnderTheSameLimitsToTheNormalizedDocument() throws {
        var generator = DocumentGenerator(seed: 0x3D3D_2105)
        var accepted = 0
        for index in 0..<Self.volume(10_000) {
            let document = generator.document()
            let limits = index.isMultiple(of: 2) ? DocumentDecodeLimits.standard : try generator.limits()
            guard
                let file = try? DocumentStorageCodec.encode(
                    document,
                    format: .binary(compression: .none),
                    limits: limits
                )
            else { continue }
            accepted += 1
            let decoded = try DocumentStorageCodec.decode(file, limits: limits)
            StructuredFixtures.assertExactlyEqual(decoded, Self.normalized(document), "P5 \(index)")
        }
        XCTAssertGreaterThan(accepted, 500)
    }

    /// P6: the writer accepts exactly what the 2.1 `validate` accepts, and decodes to the text decode
    /// (seed 0x3D3D2106; 10,000 documents under standard limits and 30,000 under random lowered limits).
    internal func testWriterAcceptanceEqualsValidationAndDecodeEqualsTheTextDecode() throws {
        var generator = DocumentGenerator(seed: 0x3D3D_2106)
        var accepted = 0
        var disagreements: [String] = []
        for index in 0..<Self.volume(40_000) {
            let document = generator.document()
            let limits = index < Self.volume(10_000) ? DocumentDecodeLimits.standard : try generator.limits()
            let binary = try? DocumentStorageCodec.encode(document, format: .binary(compression: .none), limits: limits)
            let valid = Self.validates(document, limits: limits)
            if (binary != nil) != valid {
                disagreements.append("\(index): binary \(binary != nil), validate \(valid): \(document)")
                continue
            }
            guard let binary else { continue }
            accepted += 1
            let decoded = try DocumentStorageCodec.decode(binary, limits: limits)
            let text = try DocumentStorageCodec.decode(DocumentStorageCodec.encode(document))
            StructuredFixtures.assertExactlyEqual(decoded, text, "P6 \(index)")
        }
        XCTAssertEqual(disagreements.count, 0, disagreements.prefix(5).joined(separator: "\n"))
        XCTAssertGreaterThan(accepted, 1_000)
    }

    /// P8: every finite bit pattern takes its canonical form, round-trips bit for bit, and its spelling length is
    /// what Phase L charges (seed 0x3D3D2108; 100,000 random patterns plus the integer and binary32 boundaries).
    internal func testRandomBitPatternsTakeTheirCanonicalFormAndRoundTripBitExactly() throws {
        var random = SeededGenerator(seed: 0x3D3D_2108)
        var values: [Double] = [
            134_217_727, 134_217_728, -134_217_728, -134_217_729, 16_777_216, 16_777_217, 0x1p-126, 0x1p-149,
            Double(Float.greatestFiniteMagnitude), Double(Float.greatestFiniteMagnitude).nextUp, 0x1p53, 0x1p53 + 2,
        ]
        var seen = Set(values.map(\.bitPattern))
        while values.count < Self.volume(100_000) {
            let value = Double(bitPattern: random.next())
            guard value.isFinite, value != 0, seen.insert(value.bitPattern).inserted else { continue }
            values.append(value)
        }
        for start in stride(from: 0, to: values.count, by: 1_000) {
            let chunk = values[start..<min(values.count, start + 1_000)]
            let document = Document(version: "1", axis: .layer, planes: chunk.map { Plane(z: $0, body: "") })
            let file = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
            let decoded = try DocumentStorageCodec.decode(file)
            XCTAssertEqual(decoded.planes.map(\.z.bitPattern), chunk.map(\.bitPattern))
            let text = try DocumentStorageCodec.encode(document)
            XCTAssertNoThrow(
                try DocumentStorageCodec.decode(file, limits: DocumentDecodeLimits(maximumDecodedBytes: text.count))
            )
            DocumentStorageTests.assertError(.oversizedOutput) {
                try DocumentStorageCodec.decode(file, limits: DocumentDecodeLimits(maximumDecodedBytes: text.count - 1))
            }
        }
        for value in values.prefix(12) {
            let form = DocumentStorageStructured.form(of: value)
            XCTAssertEqual(
                form == 1,
                value.rounded(.towardZero) == value && abs(value) <= 134_217_728 && value != 134_217_728
            )
            XCTAssertEqual(form == 2, form != 1 && Double(Float(value)) == value)
        }
    }

    internal static func normalized(_ document: Document) -> Document {
        Document(
            version: document.version,
            axis: document.axis,
            title: document.title,
            metadata: document.metadata,
            preamble: document.preamble,
            planes: document.planes.map { plane in
                Plane(
                    z: plane.z == 0 ? 0 : plane.z,
                    label: plane.label,
                    x: plane.x.map { $0 == 0 ? 0 : $0 },
                    y: plane.y.map { $0 == 0 ? 0 : $0 },
                    attributes: plane.attributes,
                    body: plane.body
                )
            }
        )
    }

    /// One to three mutations of a payload: bit flip, byte set, insert, delete, truncate, span copy or move, Var damage.
    internal static func mutate(_ base: [UInt8], using random: inout SeededGenerator) -> [UInt8] {
        var payload = base
        let interesting: [UInt8] = [
            0x00, 0x0A, 0x0D, 0x20, 0x22, 0x27, 0x3D, 0x3A, 0x40, 0x60, 0x7E, 0x7F, 0x80, 0xC0, 0xED, 0xFF,
        ]
        for _ in 0..<Int.random(in: 1...3, using: &random) {
            let at = payload.isEmpty ? 0 : Int.random(in: 0..<payload.count, using: &random)
            switch Int.random(in: 0...10, using: &random) {
            case 0 where !payload.isEmpty: payload[at] ^= 1 << UInt8.random(in: 0...7, using: &random)
            case 1 where !payload.isEmpty: payload[at] = UInt8.random(in: 0...255, using: &random)
            case 2 where !payload.isEmpty: payload[at] = interesting.randomElement(using: &random) ?? 0
            case 3: payload.insert(UInt8.random(in: 0...255, using: &random), at: at)
            case 4 where !payload.isEmpty:
                payload.removeSubrange(at..<min(payload.count, at + Int.random(in: 1...4, using: &random)))
            case 5: payload.removeSubrange(at..<payload.count)
            case 6 where !payload.isEmpty:
                let from = Int.random(in: 0..<payload.count, using: &random)
                let span = payload[from..<min(payload.count, from + Int.random(in: 1...12, using: &random))]
                payload.insert(contentsOf: Array(span), at: at)
            case 7 where !payload.isEmpty: payload[at] = payload[at] &+ (Bool.random(using: &random) ? 1 : 255)
            case 8 where !payload.isEmpty:
                payload.replaceSubrange(
                    at..<(at + 1),
                    with: [0x80 | UInt8.random(in: 0...127, using: &random), UInt8.random(in: 0...3, using: &random)]
                )
            case 9 where !payload.isEmpty:
                let from = Int.random(in: 0..<payload.count, using: &random)
                let span = Array(payload[from..<min(payload.count, from + Int.random(in: 1...6, using: &random))])
                payload.removeSubrange(from..<(from + span.count))
                payload.insert(contentsOf: span, at: min(at, payload.count))
            default: payload.append(UInt8.random(in: 0...255, using: &random))
            }
        }
        return payload
    }
}

/// An edge-biased document generator for the property tests: W at line edges, fences, `@plane` prefixes, CR and LF,
/// quotes in keys, reserved spellings, equivalent and byte-order-sensitive keys and number boundaries.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
private struct DocumentGenerator {
    private var random: SeededGenerator

    fileprivate init(seed: UInt64) { random = SeededGenerator(seed: seed) }

    private static let versions = ["1", "1.0", "0.1", "", " 1", "1 ", "a\"b", "x\\y", "v\n2", "\u{FEFF}1", "é"]
    private static let axes = [
        "layer", "time", "", "Space", " depth ", "\u{3000}x", "ÅNGSTRÖM", "a b", "a:b", "\u{2028}",
    ]
    private static let titles = [
        "Week", "", " lead", "trail ", "a\"b", "c\\d", "line\nbreak", "cr\rx", "'q'", "\u{A0}x",
    ]
    private static let metadataKeys = [
        "owner", "Owner", "title", "TITLE", "3md", "axis", "a:b", "#c", " k", "k ", "\u{A0}k", "k\u{3000}", "é",
        "e\u{301}", "\u{FF61}", "\u{1F600}", "K", "\u{212A}", "", "9", "10", "a'b", "a\"b", "x=y", "z",
    ]
    private static let values = [
        "v", "", "a\"b", "x\\y", "line\nbreak", "cr\rx", " lead", "trail ", "\u{FEFF}bom", "'q'", "\u{3000}", "雪",
    ]
    private static let attributeKeys = [
        "kind", "Kind", "z", "x", "y", "label", "Label", "a b", "a=b", "a\tb", "a'b", "a\"b", "a''b", "a'", "b'",
        "\"x y\"", "é", "É", "k\u{3000}", "\u{1F600}", "", "id", "3md-id", "\u{212A}", "a'b c'd",
    ]
    private static let numbers: [Double] = [
        0, -0.0, 1, -1, 2, 0.5, 0.1, -2.5, 134_217_727, -134_217_728, 134_217_728, 9_007_199_254_740_992, 1e15, 1e16,
        1e-7, 5e-324, 1e300, .nan, .infinity, -.infinity,
    ]
    private static let labels = ["Mon", "", "a\"b", "\\", "line\nx", " x", "x ", "'q'"]
    private static let fragments = [
        "a", "b", "# H", " ", "\t", "\u{A0}", "\u{3000}", "\u{2028}", "\u{200B}", "\n", "\n", "\n", "\r", "```", "~~~",
        "@plane", "@plane ", "@planet", "#", "\u{FEFF}", "é", "'", "\"",
    ]

    fileprivate mutating func document() -> Document {
        let planeCount = Int.random(in: 0...4, using: &random)
        var planes: [Plane] = []
        for index in 0..<planeCount {
            var attributes: [String: String] = [:]
            for _ in 0..<Int.random(in: 0...3, using: &random) {
                attributes[pick(["kind", "id"], Self.attributeKeys)] = pick(["v", "w"], Self.values)
            }
            planes.append(
                Plane(
                    z: pick([Double(index), Double(index) + 0.5], Self.numbers),
                    label: chance(0.4) ? pick(["Mon"], Self.labels) : nil,
                    x: chance(0.3) ? pick([1, -3], Self.numbers) : nil,
                    y: chance(0.3) ? pick([2, 0.25], Self.numbers) : nil,
                    attributes: attributes,
                    body: segment()
                )
            )
        }
        var metadata: [String: String] = [:]
        for _ in 0..<Int.random(in: 0...3, using: &random) {
            metadata[pick(["owner", "source"], Self.metadataKeys)] = pick(["v", "w"], Self.values)
        }
        return Document(
            version: pick(["1"], Self.versions),
            axis: Axis(rawValue: pick(["layer"], Self.axes)),
            title: chance(0.4) ? pick(["Week"], Self.titles) : nil,
            metadata: metadata,
            preamble: chance(0.3) ? segment() : nil,
            planes: planes
        )
    }

    fileprivate mutating func limits() throws -> DocumentDecodeLimits {
        try DocumentDecodeLimits(
            maximumDecodedBytes: Int.random(in: 20...700, using: &random),
            maximumLines: Int.random(in: 1...40, using: &random),
            maximumPlanes: Int.random(in: 1...5, using: &random),
            maximumRecordBytes: Int.random(in: 1...120, using: &random)
        )
    }

    private mutating func segment() -> String {
        if chance(0.5) { return pick(["Body", "# Title\n\nText", "- a\n- b"], ["", "x"]) }
        var text = ""
        for _ in 0..<Int.random(in: 0...6, using: &random) {
            text += Self.fragments.randomElement(using: &random) ?? ""
        }
        return text
    }

    private mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &random) < probability
    }

    /// A safe value most of the time and an edge value otherwise.
    private mutating func pick<Value>(_ safe: [Value], _ edges: [Value]) -> Value {
        let pool = chance(0.6) ? safe : edges
        return pool[Int.random(in: 0..<pool.count, using: &random)]
    }
}

// MARK: - Compression

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension DocumentStorageStructuredTests {
    #if canImport(Compression)
    internal func testLZFSEStructuredPayloadsRoundTripAndKeepTheDecodedBound() throws {
        let repeated = String(repeating: "A repeated Unicode line 雪.\n", count: 4_096) + "end"
        let documents = [
            Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, body: "small")]),
            Document(
                version: "1.0",
                axis: Axis(rawValue: "temperature"),
                title: "雪 · Unicode",
                metadata: ["é": "v"],
                planes: [Plane(z: -1.25, label: "L", attributes: ["kind": "a'b"], body: repeated)]
            ),
            try DocumentStorageCodec.decode(StructuredFixtures.data("Examples/Extensions/canopy.3md")),
        ]
        for document in documents {
            let compressed = try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse))
            let plain = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
            let info = try XCTUnwrap(try DocumentStorageCodec.containerInfo(compressed))
            XCTAssertEqual(info.payloadKind, .structuredDocument)
            XCTAssertEqual(info.compression, DocumentCompression.lzfse.rawValue)
            XCTAssertEqual(info.decodedPayloadByteCount, UInt64(plain.count - 40))
            XCTAssertEqual(Array(compressed.suffix(4)), [0x62, 0x76, 0x78, 0x24])
            StructuredFixtures.assertExactlyEqual(try DocumentStorageCodec.decode(compressed), document, "lzfse")
            XCTAssertEqual(try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse)), compressed)
            // The uncompressed container must fit Emax: Emax = 40 + n decodes, Emax - 1 is over the D10 bound.
            let exact = try DocumentDecodeLimits(maximumEncodedBytes: max(plain.count, compressed.count))
            XCTAssertEqual(try DocumentStorageCodec.decode(compressed, limits: exact), document)
            if compressed.count < plain.count {
                let small = try DocumentDecodeLimits(maximumEncodedBytes: plain.count - 1)
                DocumentStorageTests.assertError(.oversizedOutput) {
                    try DocumentStorageCodec.decode(compressed, limits: small)
                }
                DocumentStorageTests.assertError(.oversizedInput) {
                    try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse), limits: small)
                }
            }
        }
        let large = try DocumentStorageCodec.encode(documents[1], format: .binary(compression: .lzfse))
        let plain = try DocumentStorageCodec.encode(documents[1], format: .binary(compression: .none))
        XCTAssertLessThan(large.count, plain.count / 10)
        // A lowered Dmax bounds decompression: n <= 2 * Dmax.
        let lowered = try DocumentDecodeLimits(maximumDecodedBytes: (plain.count - 40) / 2 - 1)
        DocumentStorageTests.assertError(.oversizedOutput) { try DocumentStorageCodec.decode(large, limits: lowered) }
    }

    internal func testLZFSEStructuredStreamsMustEndOnceAndMatchTheDeclaredLength() throws {
        let document = Document(
            version: "1.0",
            axis: .layer,
            planes: [Plane(z: 0, body: String(repeating: "a", count: 200_000))]
        )
        let original = try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse))
        let payload = Data(original.dropFirst(40))
        let declared = Int(try XCTUnwrap(try DocumentStorageCodec.containerInfo(original)).decodedPayloadByteCount)
        for size in [declared - 1, declared + 1, 1] {
            var changed = original
            DocumentStorageTests.write(UInt64(size), into: &changed, at: 28)
            try DocumentStorageTests.updateChecksum(&changed)
            DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(changed) }
        }
        let concatenated = try DocumentStorageTests.replacingPayload(original, with: payload + payload)
        DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(concatenated) }
        let trailing = try DocumentStorageTests.replacingPayload(original, with: payload + Data([0]))
        DocumentStorageTests.assertError(.lengthMismatch) { try DocumentStorageCodec.decode(trailing) }
        for count in [1, payload.count / 2, payload.count - 1] {
            let truncated = try DocumentStorageTests.replacingPayload(original, with: Data(payload.prefix(count)))
            XCTAssertThrowsError(try DocumentStorageCodec.decode(truncated), "truncated to \(count)")
        }
    }
    #else
    internal func testLZFSEIsReportedUnavailableAfterTheSelfCheck() throws {
        let document = Document(version: "1.0", axis: .layer, planes: [Plane(z: 0, body: "body")])
        DocumentStorageTests.assertError(.compressionUnavailable(.lzfse)) {
            try DocumentStorageCodec.encode(document, format: .binary(compression: .lzfse))
        }
        let invalid = Document(version: "", axis: .layer, planes: [])
        Self.assertInvalidDocument { try DocumentStorageCodec.encode(invalid, format: .binary(compression: .lzfse)) }
        var file = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        file[11] = 1
        try DocumentStorageTests.updateChecksum(&file)
        DocumentStorageTests.assertError(.compressionUnavailable(.lzfse)) { try DocumentStorageCodec.decode(file) }
    }
    #endif
}

// MARK: - Cancellation, Concurrency and Amplification

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension DocumentStorageStructuredTests {
    internal func testCanceledTasksReturnNoStructuredDocumentOrBytes() async throws {
        let document = Document(version: "1.0", axis: .space, planes: [Plane(z: 0, body: "A bounded document")])
        let file = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        let operations: [@Sendable () throws -> Void] = [
            { _ = try DocumentStorageCodec.encode(document, format: .binary(compression: .none)) },
            { _ = try DocumentStorageCodec.encodeTextContainer(document) },
            { _ = try DocumentStorageCodec.decode(file) },
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

    #if DEBUG
    internal func testCancellationIsCheckedAtEveryStructuredCheckpoint() async throws {
        // Mid-CRC on a 64 MiB input: 1,024 checks of 65,536 bytes; cancel at the 300th.
        let large = try Self.largeContainer(byteCount: 64 * 1_024 * 1_024)
        try await Self.assertCancelled(at: "checksum", occurrence: 300) { _ = try DocumentStorageCodec.decode(large) }
        // Inside a 1 MiB scalar scan.
        let longTitle = Document(
            version: "1",
            axis: .layer,
            title: String(repeating: "t", count: 1 << 20),
            planes: [Plane(z: 0, body: "b")]
        )
        let titled = try DocumentStorageCodec.encode(longTitle, format: .binary(compression: .none))
        try await Self.assertCancelled(at: "scalarScan", occurrence: 3) { _ = try DocumentStorageCodec.decode(titled) }
        // Between UTF-8 chunks of an 8 MiB body.
        let body = Document(
            version: "1",
            axis: .layer,
            planes: [Plane(z: 0, body: String(repeating: "雪", count: (8 << 20) / 3))]
        )
        let bodied = try DocumentStorageCodec.encode(body, format: .binary(compression: .none))
        try await Self.assertCancelled(at: "utf8", occurrence: 10) { _ = try DocumentStorageCodec.decode(bodied) }
        try await Self.assertCancelled(at: "segmentScan", occurrence: 10) {
            _ = try DocumentStorageCodec.decode(bodied)
        }
        // Before plane k of 65,536 (131,077 canonical lines, so the uncancelled outcome is tooManyLines at L5).
        let many = Document(version: "1", axis: .layer, planes: (0..<65_536).map { Plane(z: Double($0), body: "") })
        var writer = StructuredWriter(capacity: DocumentDecodeLimits.standard.maximumEncodedBytes, estimate: 1 << 20)
        try writer.emit(many)
        let planes = try StructuredFixtures.container(Array(writer.bytes.dropFirst(40)))
        try await Self.assertCancelled(at: "plane", occurrence: 40_000) { _ = try DocumentStorageCodec.decode(planes) }
        // In Phase L, and before and after a Phase Q parse.
        try await Self.assertCancelled(at: "phaseL", occurrence: 1) { _ = try DocumentStorageCodec.decode(planes) }
        let quoted = Document(version: "1", axis: .layer, planes: [Plane(z: 0, attributes: ["a''b": "v"], body: "")])
        let marked = try DocumentStorageCodec.encode(quoted, format: .binary(compression: .none))
        let before = try await Self.assertCancelled(at: "phaseQ.before", occurrence: 1) {
            _ = try DocumentStorageCodec.decode(marked)
        }
        XCTAssertEqual(before.phaseQParses, 0)
        let after = try await Self.assertCancelled(at: "phaseQ.after", occurrence: 1) {
            _ = try DocumentStorageCodec.decode(marked)
        }
        XCTAssertEqual(after.phaseQParses, 1)
        // Mid-emission and mid-self-check on encode (the self-check reads planes; emission writes them).
        let emission = try await Self.assertCancelled(at: "emission", occurrence: 30_000) {
            _ = try DocumentStorageCodec.encode(many, format: .binary(compression: .none))
        }
        XCTAssertEqual(emission.count("plane"), 0)
        let selfCheck = try await Self.assertCancelled(at: "plane", occurrence: 30_000) {
            _ = try DocumentStorageCodec.encode(many, format: .binary(compression: .none))
        }
        XCTAssertEqual(selfCheck.count("emission"), 65_536)
        // Every input decodes and encodes identically after a cancelled attempt.
        // 65,536 empty planes are 131,077 lines. A caller-supplied line bound stops them; the default does not.
        let lineCap = try DocumentDecodeLimits(maximumLines: 100_000)
        DocumentStorageTests.assertError(.tooManyLines) {
            try DocumentStorageCodec.decode(planes, limits: lineCap)
        }
        DocumentStorageTests.assertError(.tooManyLines) {
            try DocumentStorageCodec.encode(many, format: .binary(compression: .none), limits: lineCap)
        }
        let fewer = Document(version: "1", axis: .layer, planes: Array(many.planes.prefix(40_000)))
        XCTAssertEqual(
            try DocumentStorageCodec.decode(DocumentStorageCodec.encode(fewer, format: .binary(compression: .none))),
            fewer
        )
        XCTAssertEqual(try DocumentStorageCodec.decode(marked), quoted)
        XCTAssertEqual(try DocumentStorageCodec.decode(bodied), body)
        XCTAssertEqual(try DocumentStorageCodec.decode(titled), longTitle)
        DocumentStorageTests.assertError(.checksumMismatch) { try DocumentStorageCodec.decode(large) }
    }

    /// Runs of short strings charge a byte budget, so no pass reads, compares or builds 65,536 bytes of them without
    /// a cancellation check: Phase S, the equivalence pass, Phase L and materialization (SPEC 11.3.13).
    internal func testShortStringsChargeTheCancellationBudgetInEveryPass() async throws {
        // 200,000 metadata entries with 7-letter keys: Phase S reads them all, then L5 rejects 200,005 lines.
        var payload: [UInt8] = [0x00, 0x01, 0x31, 0x00]
        DocumentStorageStructured.appendVariable(200_000, to: &payload)
        var key = Array("aaaaaaa".utf8)
        for _ in 0..<200_000 {
            payload.append(7)
            payload += key
            payload += [0x01, 0x76]
            StructuredFixtures.increment(&key)
        }
        payload.append(0x00)
        let metadata = try StructuredFixtures.container(payload)
        let lineCap = try DocumentDecodeLimits(maximumLines: 100_000)
        let counting = DocumentStorageProbe()
        let outcome = await Task.detached {
            DocumentStorageProbe.$current.withValue(counting) {
                StructuredFixtures.outcome { try DocumentStorageCodec.decode(metadata, limits: lineCap) }
            }
        }.value
        XCTAssertEqual(outcome, "tooManyLines")
        XCTAssertGreaterThanOrEqual(counting.count("budget"), payload.count / DocumentStorageStructured.block)
        let early = try await Self.assertCancelled(at: "budget", occurrence: 20) {
            _ = try DocumentStorageCodec.decode(metadata)
        }
        XCTAssertEqual(early.count("phaseL"), 0)
        // One plane of 100,000 non-ASCII keys: Phase S, the equivalence pass and materialization each charge.
        let attributes = StructuredFixtures.attributePayload(prefix: [0xC3, 0xA9], width: 5, count: 100_000)
        let plane = try StructuredFixtures.container(attributes)
        let probe = DocumentStorageProbe()
        let decoded = try await Task.detached {
            try DocumentStorageProbe.$current.withValue(probe) { try DocumentStorageCodec.decode(plane) }
        }.value
        XCTAssertEqual(decoded.planes.first?.attributes.count, 100_000)
        let checks = probe.count("budget")
        XCTAssertGreaterThanOrEqual(checks, 3 * (attributes.count / DocumentStorageStructured.block) - 3)
        XCTAssertEqual(probe.count("equivalence"), 2)
        let middle = try await Self.assertCancelled(at: "equivalence", occurrence: 1) {
            _ = try DocumentStorageCodec.decode(plane)
        }
        XCTAssertEqual(middle.count("phaseL"), 0)
        let late = try await Self.assertCancelled(at: "budget", occurrence: checks - 1) {
            _ = try DocumentStorageCodec.decode(plane)
        }
        XCTAssertEqual(late.count("phaseL"), 1)
        XCTAssertEqual(late.count("materialize"), 1)
        // A non-ASCII key longer than 65,536 bytes is compared with its lowercase chunk by chunk.
        let longKey = String(repeating: "\u{E9}", count: 3 * DocumentStorageStructured.block)
        let keyed = Document(version: "1", axis: .layer, planes: [Plane(z: 0, attributes: [longKey: ""], body: "")])
        let keyedFile = try DocumentStorageCodec.encode(keyed, format: .binary(compression: .none))
        try await Self.assertCancelled(at: "keyScan", occurrence: 2) { _ = try DocumentStorageCodec.decode(keyedFile) }
        // Every input decodes identically after a cancelled attempt.
        DocumentStorageTests.assertError(.tooManyLines) {
            try DocumentStorageCodec.decode(metadata, limits: try DocumentDecodeLimits(maximumLines: 100_000))
        }
        XCTAssertEqual(try DocumentStorageCodec.decode(plane).planes.first?.attributes.count, 100_000)
        StructuredFixtures.assertExactlyEqual(try DocumentStorageCodec.decode(keyedFile), keyed, "long key")
    }

    internal func testAmplifiedQuotedKeysAreRejectedByPhaseLBeforeAnyPhaseQParse() async throws {
        // 65,536 planes whose keys contain quotes and whose labels push every directive over R.
        let label = String(repeating: "l", count: 95)
        let planes = (0..<65_536).map { Plane(z: Double($0), label: label, attributes: ["a''b": "v"], body: "") }
        var writer = StructuredWriter(capacity: DocumentDecodeLimits.standard.maximumEncodedBytes, estimate: 8 << 20)
        try writer.emit(Document(version: "1", axis: .layer, planes: planes))
        let file = try StructuredFixtures.container(Array(writer.bytes.dropFirst(40)))
        let limits = try DocumentDecodeLimits(maximumRecordBytes: 100)
        let probe = DocumentStorageProbe()
        let started = ProcessInfo.processInfo.systemUptime
        let outcome = await Task.detached {
            DocumentStorageProbe.$current.withValue(probe) {
                StructuredFixtures.outcome { try DocumentStorageCodec.decode(file, limits: limits) }
            }
        }.value
        XCTAssertEqual(outcome, "oversizedRecord")
        XCTAssertEqual(probe.phaseQParses, 0)
        XCTAssertEqual(probe.count("plane"), 65_536)
        // Generous for unoptimized builds; release builds finish in well under a second.
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 30)
        // Once Phase L passes, each marked plane costs one Phase Q parse, and each succeeds.
        let fewer = Document(version: "1", axis: .layer, planes: Array(planes.prefix(1_000)))
        let accepted = try DocumentStorageCodec.encode(fewer, format: .binary(compression: .none))
        let parses = DocumentStorageProbe()
        let decoded = try await Task.detached {
            try DocumentStorageProbe.$current.withValue(parses) { try DocumentStorageCodec.decode(accepted) }
        }.value
        XCTAssertEqual(decoded, fewer)
        XCTAssertEqual(parses.phaseQParses, 1_000)
    }
    #endif

    internal func testConcurrentTasksEncodeAndDecodeIndependently() async throws {
        let manifest = try StructuredFixtures.manifest()
        var documents: [Document] = []
        var files: [Data] = []
        for entry in manifest.files {
            let file = try StructuredFixtures.data(entry.kind2File)
            files.append(file)
            documents.append(try DocumentStorageCodec.decode(file))
        }
        let inputs = Array(zip(documents, files))
        let mismatches = try await withThrowingTaskGroup(of: Int.self) { group in
            for task in 0..<32 {
                group.addTask {
                    var mismatches = 0
                    for round in 0..<20 {
                        let (document, file) = inputs[(task + round) % inputs.count]
                        let encoded = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
                        let decoded = try DocumentStorageCodec.decode(file)
                        if encoded != file || !StructuredFixtures.exactlyEqual(decoded, document) { mismatches += 1 }
                    }
                    return mismatches
                }
            }
            var total = 0
            for try await count in group { total += count }
            return total
        }
        XCTAssertEqual(mismatches, 0)
    }

    #if DEBUG
    /// Runs `operation` in a detached task whose probe cancels it at checkpoint `site`; returns the probe.
    @discardableResult
    internal static func assertCancelled(
        at site: String,
        occurrence: Int,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: @escaping @Sendable () throws -> Void
    ) async throws -> DocumentStorageProbe {
        let probe = DocumentStorageProbe(cancellingAt: site, occurrence: occurrence)
        let task = Task.detached { try DocumentStorageProbe.$current.withValue(probe) { try operation() } }
        do {
            try await task.value
            XCTFail("The operation finished instead of stopping at \(site) #\(occurrence)", file: file, line: line)
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)", file: file, line: line)
        }
        XCTAssertTrue(probe.didCancel, "Never reached \(site) #\(occurrence)", file: file, line: line)
        XCTAssertEqual(probe.count(site), occurrence, file: file, line: line)
        return probe
    }
    #endif

    /// A kind-2 container of exactly `byteCount` bytes with a valid header and a zero (wrong) checksum.
    internal static func largeContainer(byteCount: Int) throws -> Data {
        var file = Data(count: byteCount)
        let header = try StructuredFixtures.container([0x00])
        file.replaceSubrange(0..<40, with: header.prefix(40))
        DocumentStorageTests.write(UInt64(byteCount - 40), into: &file, at: 20)
        DocumentStorageTests.write(UInt64(byteCount - 40), into: &file, at: 28)
        DocumentStorageTests.write(UInt32(0), into: &file, at: 36)
        return file
    }
}

// MARK: - Memory

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension DocumentStorageStructuredTests {
    /// Test plan section 5: decoding the worst cases grows memory (the heap on Darwin, the resident set on Linux) by
    /// less than three times the input, so the process holds less than four times the input. Phase S keeps no strings
    /// and no map entries; a valid document's result is the only allocation in proportion to its strings.
    internal func testDecodingPeakMemoryGrowthStaysUnderThreeTimesTheInput() throws {
        guard HeapSampler.isAvailable else { throw XCTSkip("This platform reports no memory statistics.") }
        // A 64 MiB sample of the reader's memory behavior. It is not a library size ceiling.
        let encoded = 64 * 1_024 * 1_024
        let standard = try DocumentDecodeLimits(
            maximumEncodedBytes: encoded,
            maximumDecodedBytes: encoded,
            maximumLines: 100_000,
            maximumPlanes: 65_536,
            maximumRecordBytes: 8 * 1_024 * 1_024
        )
        let budget = encoded - DocumentStorageCodec.headerByteCount
        let cases: [(name: String, limits: DocumentDecodeLimits, expected: String, payload: () throws -> [UInt8])] = [
            // One plane with as many 7-letter keys as fit the 64 MiB container (D10 bounds the count).
            (
                "maximum attributes", standard, "oversizedRecord",
                { StructuredFixtures.attributePayload(prefix: [], width: 7, count: (budget - 16) / 9) }
            ),
            // Quote keys, so the plane is marked for Phase Q, which L3 never reaches. The reader's memory is linear in
            // the input, so these two cases use 8 MiB to keep unoptimized test builds fast.
            (
                "quote keys", standard, "oversizedRecord",
                { StructuredFixtures.attributePayload(prefix: [0x27], width: 6, count: (budget / 8 - 16) / 9) }
            ),
            // Non-ASCII keys, so the equivalence pass hashes and sorts every key.
            (
                "non-ASCII keys", standard, "oversizedRecord",
                { StructuredFixtures.attributePayload(prefix: [0xC3, 0xA9], width: 5, count: (budget / 8 - 16) / 9) }
            ),
            // The most planes, each with a body: L4 rejects the canonical text.
            (
                "maximum planes", standard, "oversizedOutput",
                {
                    StructuredFixtures.planesPayload(budget: budget, planes: 65_536)
                }
            ),
            // One 8 MiB body, decoded into its document.
            (
                "8 MiB body", standard, "ok",
                {
                    var payload: [UInt8] = [0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00]
                    DocumentStorageStructured.appendVariable(standard.maximumRecordBytes, to: &payload)
                    payload.append(contentsOf: repeatElement(0x78, count: standard.maximumRecordBytes))
                    return payload
                }
            ),
            // 65,536 planes whose quote keys and labels push every directive over R.
            (
                "amplification", try DocumentDecodeLimits(maximumRecordBytes: 100), "oversizedRecord",
                {
                    let label = String(repeating: "l", count: 95)
                    let planes = (0..<65_536).map {
                        Plane(z: Double($0), label: label, attributes: ["a''b": "v"], body: "")
                    }
                    var writer = StructuredWriter(capacity: standard.maximumEncodedBytes, estimate: 8 << 20)
                    try writer.emit(Document(version: "1", axis: .layer, planes: planes))
                    return Array(writer.bytes.dropFirst(DocumentStorageCodec.headerByteCount))
                }
            ),
        ]
        for testCase in cases {
            let file = try StructuredFixtures.container(testCase.payload())
            XCTAssertLessThanOrEqual(file.count, standard.maximumEncodedBytes, testCase.name)
            let limits = testCase.limits
            let (result, growth) = HeapSampler.peakGrowth {
                Result { try DocumentStorageCodec.decode(file, limits: limits) }
            }
            XCTAssertEqual(StructuredFixtures.outcome { try result.get() }, testCase.expected, testCase.name)
            XCTAssertLessThan(growth, 3 * file.count, "\(testCase.name): \(growth) bytes for \(file.count)")
        }
    }
}

// MARK: - Helpers

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension DocumentStorageStructuredTests {
    internal static func readVariable(_ bytes: [UInt8], maximumBytes: Int = 10) throws -> Int {
        try bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { throw DocumentStorageError.lengthMismatch }
            var position = 0
            return try DocumentStorageStructured.readVariable(
                base,
                &position,
                buffer.count,
                maximumBytes: maximumBytes
            )
        }
    }

    /// The CRC-32/ISO-HDLC definition, one bit at a time.
    internal static func bytewiseChecksum<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320 }
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// A kind-2 file whose version holds `version` and whose other fields are minimal.
    internal static func versionContainer(_ version: [UInt8]) throws -> Data {
        var payload: [UInt8] = [0x00]
        DocumentStorageStructured.appendVariable(version.count, to: &payload)
        payload += version + [0x00, 0x00, 0x00]
        return try StructuredFixtures.container(payload)
    }

    /// A kind-2 file with one plane at z = 0 whose body holds `body`.
    internal static func bodyContainer(_ body: [UInt8]) throws -> Data {
        var payload: [UInt8] = [0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00]
        DocumentStorageStructured.appendVariable(body.count, to: &payload)
        payload += body
        return try StructuredFixtures.container(payload)
    }

    /// Whether the kind-2 writer accepts the document.
    internal static func accepts(_ document: Document, limits: DocumentDecodeLimits = .standard) -> Bool {
        (try? DocumentStorageCodec.encode(document, format: .binary(compression: .none), limits: limits)) != nil
    }

    /// Whether the 2.1 `validate` accepts the document.
    internal static func validates(_ document: Document, limits: DocumentDecodeLimits = .standard) -> Bool {
        (try? DocumentStorageCodec.validate(document, limits: limits)) != nil
    }

    internal static func assertInvalidDocument<Value>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Value
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case .invalidDocument = error as? DocumentStorageError else {
                return XCTFail("Expected invalidDocument, got \(error)", file: file, line: line)
            }
        }
    }

    /// The CI volume of a property test.
    internal static func volume(_ count: Int) -> Int { count }
}

/// SplitMix64: a small seeded generator, so every property run is reproducible from its recorded seed.
internal struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    internal init(seed: UInt64) { state = seed }

    internal mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Measures how far memory grows while an operation runs (test plan section 5).
///
/// On Darwin a dedicated thread samples the bytes every malloc zone holds in use. On Linux the kernel's resident
/// high-water mark is reset through `/proc/self/clear_refs` and read back from `/proc/self/status`, which gives the
/// exact peak resident set.
///
/// `@unchecked Sendable` is justified: `running` and `highest` are read and written only while holding `lock`.
internal final class HeapSampler: @unchecked Sendable {
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private var running = true
    private var highest = 0

    /// Whether this platform reports the memory the measurement needs.
    internal static var isAvailable: Bool {
        #if canImport(Darwin)
        return true
        #elseif os(Linux)
        return resetResidentPeak() && residentStatus() != nil
        #else
        return false
        #endif
    }

    /// Runs `operation` and measures the memory it adds at its peak.
    /// - Parameter operation: The work to measure; its value is still alive at the last measurement.
    /// - Returns: The value and the highest level above the level before the operation: heap bytes in use on
    ///   Darwin, resident bytes on Linux.
    internal static func peakGrowth<Value>(_ operation: () -> Value) -> (value: Value, growth: Int) {
        #if canImport(Darwin)
        let sampler = HeapSampler()
        let baseline = heapInUse()
        sampler.highest = baseline
        Thread { sampler.sample() }.start()
        sampler.started.wait()
        let value = operation()
        let last = heapInUse()
        sampler.lock.lock()
        sampler.running = false
        sampler.lock.unlock()
        sampler.finished.wait()
        sampler.lock.lock()
        defer { sampler.lock.unlock() }
        return (value, max(sampler.highest, last) - baseline)
        #else
        _ = resetResidentPeak()
        let baseline = residentStatus()?.current ?? 0
        let value = operation()
        let peak = residentStatus()?.peak ?? 0
        return (value, peak - baseline)
        #endif
    }

    #if canImport(Darwin)
    /// The bytes every malloc zone holds allocated and not yet freed.
    private static func heapInUse() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
    }

    private func sample() {
        started.signal()
        var sampling = true
        while sampling {
            let now = Self.heapInUse()
            lock.lock()
            highest = max(highest, now)
            sampling = running
            lock.unlock()
            // A pause keeps the sampler from contending for the allocator's locks; the reader's peaks last far longer.
            if sampling { usleep(200) }
        }
        finished.signal()
    }
    #else
    /// Resets the kernel's resident high-water mark to the current resident set.
    private static func resetResidentPeak() -> Bool {
        guard let handle = FileHandle(forWritingAtPath: "/proc/self/clear_refs") else { return false }
        defer { try? handle.close() }
        return (try? handle.write(contentsOf: Data("5".utf8))) != nil
    }

    /// The resident set now (`VmRSS`) and its high-water mark (`VmHWM`), in bytes.
    private static func residentStatus() -> (current: Int, peak: Int)? {
        guard let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else { return nil }
        func kilobytes(_ name: String) -> Int? {
            for line in status.split(separator: "\n") where line.hasPrefix(name + ":") {
                let fields = line.dropFirst(name.count + 1).split { $0 == " " || $0 == "\t" }
                return fields.first.flatMap { Int($0) }
            }
            return nil
        }
        guard let current = kilobytes("VmRSS"), let peak = kilobytes("VmHWM") else { return nil }
        return (current * 1_024, peak * 1_024)
    }
    #endif
}

// MARK: - Fixtures

/// Shared fixture access for the structured payload tests.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal enum StructuredFixtures {
    /// The repository root, three levels above this file.
    internal static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    internal static func data(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    internal static func manifest() throws -> GoldenManifest {
        try JSONDecoder().decode(GoldenManifest.self, from: data("conformance/structured/manifest.json"))
    }

    /// The bounded text decode of the case's canonical text; a composition case yields its profile envelope.
    internal static func expectedDocument(_ entry: GoldenManifest.Entry) throws -> Document {
        switch entry.set {
        case "worked":
            let name = entry.id
            return try XCTUnwrap(workedDocuments[name], "missing worked example \(name)")
        default:
            let source = try data(entry.sourceFile)
            if entry.kind == "composition" {
                return try DocumentCompositionCodec.document(for: DocumentCompositionCodec.decode(source))
            }
            let canonical = try DocumentStorageCodec.encode(DocumentStorageCodec.decode(source))
            return try DocumentStorageCodec.decode(canonical)
        }
    }

    /// The limits a composition envelope is stored under (SPEC 12.2).
    internal static func profileLimits() throws -> DocumentDecodeLimits {
        let profile = DocumentCompositionLimits.standard.maximumProfileBytes
        return try DocumentDecodeLimits(
            maximumEncodedBytes: profile,
            maximumDecodedBytes: profile,
            maximumPlanes: 1,
            maximumRecordBytes: profile
        )
    }

    internal static let workedDocuments: [String: Document] = [
        "worked-document": Document(
            version: "1.0",
            axis: .time,
            title: "Week",
            metadata: ["owner": "ops"],
            planes: [
                Plane(z: 0, label: "Mon", body: "# Standup"),
                Plane(z: 1.5, label: "Tue", x: -2, attributes: ["kind": "note"], body: "Ship it"),
            ]
        ),
        "worked-numbers": Document(
            version: "1.0",
            axis: .layer,
            planes: [Plane(z: 0.1, x: 0.5, y: 268_435_456, attributes: ["note": "say \"hi\""], body: "")]
        ),
        "worked-keys": Document(
            version: "1",
            axis: Axis(rawValue: ""),
            metadata: ["z": "1", "e\u{301}": "2"],
            planes: [Plane(z: -3, attributes: ["b": "x", "a": "y"], body: "")]
        ),
    ]

    /// The stable code of a storage outcome: `ok` or the `DocumentStorageError` case name.
    internal static func outcome(_ operation: () throws -> Document) -> String {
        do {
            _ = try operation()
            return "ok"
        } catch {
            return code(error)
        }
    }

    internal static func code(_ error: Error) -> String {
        guard let error = error as? DocumentStorageError else { return "foreign:\(error)" }
        switch error {
        case .invalidLimits: return "invalidLimits"
        case .oversizedInput: return "oversizedInput"
        case .oversizedOutput: return "oversizedOutput"
        case .tooManyLines: return "tooManyLines"
        case .tooManyPlanes: return "tooManyPlanes"
        case .oversizedRecord: return "oversizedRecord"
        case .invalidUTF8: return "invalidUTF8"
        case .invalidText: return "invalidText"
        case .invalidDocument: return "invalidDocument"
        case .invalidContainer: return "invalidContainer"
        case .unsupportedVersion: return "unsupportedVersion"
        case .unsupportedPayloadKind: return "unsupportedPayloadKind"
        case .unsupportedCompression: return "unsupportedCompression"
        case .unsupportedFlags: return "unsupportedFlags"
        case .nonzeroReserved: return "nonzeroReserved"
        case .lengthMismatch: return "lengthMismatch"
        case .checksumMismatch: return "checksumMismatch"
        case .compressionUnavailable: return "compressionUnavailable"
        case .compressionFailed: return "compressionFailed"
        }
    }

    /// Byte-exact comparison: `Document ==` treats canonically equivalent strings as equal.
    internal static func assertExactlyEqual(
        _ actual: Document,
        _ expected: Document,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(exactlyEqual(actual, expected), "\(message): \(actual) != \(expected)", file: file, line: line)
    }

    internal static func exactlyEqual(_ first: Document, _ second: Document) -> Bool {
        func bytes(_ value: String?) -> [UInt8]? { value.map { Array($0.utf8) } }
        func map(_ value: [String: String]) -> [[UInt8]: [UInt8]] {
            var result: [[UInt8]: [UInt8]] = [:]
            for (key, value) in value { result[Array(key.utf8)] = Array(value.utf8) }
            return result
        }
        guard bytes(first.version) == bytes(second.version),
            bytes(first.axis.rawValue) == bytes(second.axis.rawValue), bytes(first.title) == bytes(second.title),
            bytes(first.preamble) == bytes(second.preamble), map(first.metadata) == map(second.metadata),
            first.metadata.count == second.metadata.count, first.planes.count == second.planes.count
        else { return false }
        for (left, right) in zip(first.planes, second.planes) {
            guard left.z.bitPattern == right.z.bitPattern, left.x?.bitPattern == right.x?.bitPattern,
                left.y?.bitPattern == right.y?.bitPattern, bytes(left.label) == bytes(right.label),
                bytes(left.body) == bytes(right.body), map(left.attributes) == map(right.attributes),
                left.attributes.count == right.attributes.count
            else { return false }
        }
        return true
    }

    #if canImport(CryptoKit)
    internal static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    #endif

    internal static func hex(_ source: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var iterator = source.utf8.makeIterator()
        func digit(_ value: UInt8) -> UInt8 {
            switch value {
            case 48...57: return value - 48
            case 97...102: return value - 87
            default: return value &- 55
            }
        }
        while let high = iterator.next(), let low = iterator.next() { bytes.append(digit(high) << 4 | digit(low)) }
        return bytes
    }

    /// A complete uncompressed kind-2 container around `payload`, with lengths and CRC sealed.
    internal static func container(_ payload: [UInt8], kind: UInt8 = 2) throws -> Data {
        var header = Data("3mdbin\r\n".utf8)
        header.append(contentsOf: [1, 0, kind, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        withUnsafeBytes(of: UInt64(payload.count).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt64(payload.count).littleEndian) { header.append(contentsOf: $0) }
        let checksum = try DocumentStorageChecksum.checksum(header: header, payload: Data(payload))
        withUnsafeBytes(of: checksum.littleEndian) { header.append(contentsOf: $0) }
        header.append(contentsOf: payload)
        return header
    }

    /// The payload bytes of a container.
    internal static func payload(_ container: Data) -> [UInt8] {
        Array(container.dropFirst(DocumentStorageCodec.headerByteCount))
    }

    /// A one-plane payload with `count` attributes whose keys are `prefix` and then `width` letters counting up from
    /// "a…a", so they are strictly increasing; values and the body are empty.
    internal static func attributePayload(prefix: [UInt8], width: Int, count: Int) -> [UInt8] {
        var head: [UInt8] = [0x00, 0x01, 0x31, 0x00, 0x00, 0x01, 0x01, 0x00]
        DocumentStorageStructured.appendVariable(count, to: &head)
        let entry = 2 + prefix.count + width
        var payload = [UInt8](repeating: 0, count: head.count + count * entry + 1)
        payload.replaceSubrange(0..<head.count, with: head)
        var key = [UInt8](repeating: 0x61, count: width)
        payload.withUnsafeMutableBufferPointer { buffer in
            var offset = head.count
            for _ in 0..<count {
                buffer[offset] = UInt8(prefix.count + width)
                offset += 1
                for byte in prefix {
                    buffer[offset] = byte
                    offset += 1
                }
                for byte in key {
                    buffer[offset] = byte
                    offset += 1
                }
                // The empty value's length byte is already zero.
                offset += 1
                increment(&key)
            }
        }
        return payload
    }

    /// `planes` bodies of `x`, filling `budget` payload bytes.
    internal static func planesPayload(budget: Int, planes: Int) -> [UInt8] {
        let body = budget / planes - 8
        var payload: [UInt8] = [0x00, 0x01, 0x31, 0x00, 0x00]
        payload.reserveCapacity(budget)
        DocumentStorageStructured.appendVariable(planes, to: &payload)
        for z in 0..<planes {
            payload.append(0x01)
            DocumentStorageStructured.appendVariable(z << 1, to: &payload)
            payload.append(0x00)
            DocumentStorageStructured.appendVariable(body, to: &payload)
            payload.append(contentsOf: repeatElement(0x78, count: body))
        }
        return payload
    }

    /// Counts a key of lowercase letters up by one, carrying from the last letter.
    internal static func increment(_ key: inout [UInt8]) {
        var index = key.count - 1
        while index >= 0 {
            guard key[index] == 0x7A else {
                key[index] += 1
                return
            }
            key[index] = 0x61
            index -= 1
        }
    }
}

/// `conformance/structured/manifest.json`.
internal struct GoldenManifest: Decodable {
    internal let schema: String
    internal let files: [Entry]

    internal struct Entry: Decodable {
        internal let id: String
        internal let set: String
        internal let kind: String
        internal let sourceFile: String
        internal let textContainerFile: String?
        internal let kind2File: String
        internal let bytes: Int
        internal let payloadBytes: Int
        internal let canonicalBytes: Int
        internal let sha256: String
        internal let crc32: String
        internal let planes: Int
        internal let compositionEnvelope: Bool
    }
}

/// `conformance/structured/vectors.json`.
private struct VectorFixture: Decodable {
    fileprivate let schema: String
    fileprivate let vectors: [Vector]

    fileprivate struct Vector: Decodable {
        fileprivate let name: String
        fileprivate let file: String
        fileprivate let rule: String
        fileprivate let expected: String
        fileprivate let limits: Limits?
        fileprivate let requiresNoLZFSE: Bool?
    }

    fileprivate struct Limits: Decodable {
        fileprivate let maximumEncodedBytes: Int?
        fileprivate let maximumDecodedBytes: Int?
        fileprivate let maximumLines: Int?
        fileprivate let maximumPlanes: Int?
        fileprivate let maximumRecordBytes: Int?

        fileprivate func decodeLimits() throws -> DocumentDecodeLimits {
            let standard = DocumentDecodeLimits.standard
            return try DocumentDecodeLimits(
                maximumEncodedBytes: maximumEncodedBytes ?? standard.maximumEncodedBytes,
                maximumDecodedBytes: maximumDecodedBytes ?? standard.maximumDecodedBytes,
                maximumLines: maximumLines ?? standard.maximumLines,
                maximumPlanes: maximumPlanes ?? standard.maximumPlanes,
                maximumRecordBytes: maximumRecordBytes ?? standard.maximumRecordBytes
            )
        }
    }
}

/// `conformance/structured/sizes.json`.
private struct SizeFixture: Decodable {
    fileprivate let examples: Totals
    fileprivate let large: [String: Large]
    fileprivate let perFile: [File]

    fileprivate struct Totals: Decodable {
        fileprivate let canonical: Int
        fileprivate let kind2: Int
    }

    fileprivate struct Large: Decodable {
        fileprivate let canonical: Int
        fileprivate let kind2: Int
    }

    fileprivate struct File: Decodable {
        fileprivate let file: String
        fileprivate let canonical: Int
        fileprivate let kind2: Int
    }
}

/// `conformance/extensions/numeric-powers.json`.
private struct NumericPowers: Decodable {
    fileprivate let schema: String
    fileprivate let vectors: [Vector]

    fileprivate struct Vector: Decodable {
        fileprivate let bitPattern: String
        fileprivate let formatted: String
        fileprivate let name: String
    }
}
