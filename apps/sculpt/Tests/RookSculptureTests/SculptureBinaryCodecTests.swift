import Foundation
import Testing

@testable import RookSculpture

#if canImport(CryptoKit)
import CryptoKit
#endif


@Test func sha256MatchesThePublishedEmptyAndABCVectors() {
    #expect(
        SculptureSHA256.hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    )
    #expect(
        SculptureSHA256.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
}

#if canImport(CryptoKit)
@Test func sha256MatchesCryptoKit() {
    let samples = [Data(), Data("abc".utf8), Data(repeating: 0xAB, count: 100_000)]
    for sample in samples {
        #expect(SculptureSHA256.hash(sample) == Data(SHA256.hash(data: sample)))
    }
}
#endif

@Test func compactRoundTripPreservesEveryGlyphRectangularDimensionsAndTitle() throws {
    let glyphs = Sculpture.palette + [Sculpture.empty]
    let layers = (0..<4).map { z in (0..<30).map { glyphs[($0 + z) % glyphs.count] } }
    let sculpture = try Sculpture(title: "Binary \"study\" \\ 2026", width: 10, height: 3, layers: layers)
    let first = try SculptureBinaryCodec.encode(sculpture)
    #expect(try SculptureBinaryCodec.decode(first) == sculpture)
    #expect(try SculptureBinaryCodec.encode(sculpture) == first)
    #expect(Array(first.prefix(8)) == [0x33, 0x4D, 0x44, 0x42, 0x0D, 0x0A, 0x1A, 0x0A])
    #expect(binaryUInt16(first, at: 8) == 1)
    #expect(first[10] == 1 && first[11] == 0)
    #expect(first.count < SculptureBinaryCodec.maximumBytes)
}

@Test func documentCodecAutodetectsFormatsAndLeavesReadableEncodingUnchanged() throws {
    let sculpture = Sculpture.orb()
    let readable = try SculptureDocumentCodec.encode(sculpture, format: .readable)
    let compact = try SculptureDocumentCodec.encode(sculpture, format: .compact)
    #expect(readable == SculptureCodec.encode(sculpture))
    #expect(SculptureDocumentCodec.format(of: readable) == .readable)
    #expect(SculptureDocumentCodec.format(of: compact) == .compact)
    #expect(try SculptureDocumentCodec.decode(readable) == sculpture)
    #expect(try SculptureDocumentCodec.decode(compact) == sculpture)
    #expect(SculptureStorageFormat.readable.fileExtension == "3md")
    #expect(SculptureStorageFormat.compact.fileExtension == "3mdb")
    #expect(SculptureDocumentCodec.maximumBytes == SculptureBinaryCodec.maximumBytes)
    #expect(
        try JSONDecoder().decode(
            SculptureStorageFormat.self,
            from: JSONEncoder().encode(SculptureStorageFormat.compact)
        ) == .compact
    )
    var prefixed = Data([0, 1, 2])
    prefixed.append(compact)
    let slice = prefixed.dropFirst(3)
    #expect(try SculptureDocumentCodec.decode(slice) == sculpture)
}

@Test func compactMaximumFilledVolumeRoundTripsWithExactDimensionsAndOccupancy() throws {
    let sculpture = try Sculpture(
        title: String(repeating: "M", count: 80),
        width: 256,
        height: 256,
        layers: Array(repeating: Array(repeating: UInt8(35), count: 65_536), count: 256)
    )
    let encoded = try SculptureBinaryCodec.encode(sculpture)
    #expect(encoded.count < SculptureBinaryCodec.maximumBytes)
    let decoded = try SculptureBinaryCodec.decode(encoded)
    #expect(decoded.title == sculpture.title)
    #expect(decoded.width == 256 && decoded.height == 256 && decoded.depth == 256)
    #expect(decoded.occupiedCount == 16_777_216)
    let allVoxelsMatch = decoded.layers.allSatisfy { $0.count == 65_536 && $0.allSatisfy { $0 == 35 } }
    #expect(allVoxelsMatch)
    #expect(decoded.glyph(at: SculptureCell(x: 255, y: 255, z: 255)) == 35)
}

@Test func sparseCompactStorageIsSubstantiallySmallerThanRawVoxels() throws {
    var sculpture = try Sculpture(
        title: "Sparse space",
        width: 64,
        height: 64,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: 4096), count: 64)
    )
    sculpture.paint(SculptureCell(x: 0, y: 0, z: 0), glyph: 35)
    sculpture.paint(SculptureCell(x: 32, y: 32, z: 32), glyph: 64)
    sculpture.paint(SculptureCell(x: 63, y: 63, z: 63), glyph: 111)
    let compact = try SculptureBinaryCodec.encode(sculpture)
    #expect(compact.count < 262_144 / 20)
    #expect(try SculptureBinaryCodec.decode(compact) == sculpture)
}

@Test func compactRejectsEmptyIncompleteAndCorruptedHeaders() throws {
    let valid = try SculptureBinaryCodec.encode(.orb())
    for count in [0, 7, 8, 27, 59] {
        #expect(throws: SculptureBinaryCodecError.invalidHeader) {
            try SculptureBinaryCodec.decode(Data(valid.prefix(count)))
        }
    }
    for offset in [0, 7, 11] {
        var malformed = valid
        malformed[offset] ^= 0x80
        #expect(throws: SculptureBinaryCodecError.invalidHeader) { try SculptureBinaryCodec.decode(malformed) }
    }
    var future = valid
    binaryWrite(UInt16(2), into: &future, at: 8)
    #expect(throws: SculptureBinaryCodecError.unsupportedVersion(2)) { try SculptureBinaryCodec.decode(future) }
    var algorithm = valid
    algorithm[10] = 2
    #expect(throws: SculptureBinaryCodecError.unsupportedCompression(2)) { try SculptureBinaryCodec.decode(algorithm) }
}

@Test func compactBoundsDimensionsTitleAndDeclaredCountsBeforeDecompression() throws {
    let valid = try SculptureBinaryCodec.encode(.orb())
    let invalidDimensions: [UInt16] = [0, 257, .max]
    for offset in [12, 14, 16] {
        for dimension in invalidDimensions {
            var malformed = valid
            binaryWrite(dimension, into: &malformed, at: offset)
            #expect(throws: SculptureError.invalidDimensions) { try SculptureBinaryCodec.decode(malformed) }
        }
    }
    let invalidTitleCounts: [UInt16] = [0, 81, .max]
    for count in invalidTitleCounts {
        var malformed = valid
        binaryWrite(count, into: &malformed, at: 18)
        #expect(throws: SculptureError.invalidTitle) { try SculptureBinaryCodec.decode(malformed) }
    }
    var invalidTitle = valid
    invalidTitle[60] = 10
    #expect(throws: SculptureError.invalidTitle) { try SculptureBinaryCodec.decode(invalidTitle) }
    let invalidPayloadCounts: [UInt32] = [0, 16_777_217, .max]
    for count in invalidPayloadCounts {
        var malformed = valid
        binaryWrite(count, into: &malformed, at: 20)
        #expect(throws: SculptureBinaryCodecError.invalidLength) { try SculptureBinaryCodec.decode(malformed) }
        binaryWrite(count, into: &malformed, at: 24)
        #expect(throws: SculptureBinaryCodecError.invalidLength) { try SculptureBinaryCodec.decode(malformed) }
    }
    #expect(throws: SculptureError.oversizedFile) {
        try SculptureBinaryCodec.decode(Data(repeating: 0, count: SculptureBinaryCodec.maximumBytes + 1))
    }
    #expect(throws: SculptureBinaryCodecError.invalidHeader) {
        try SculptureBinaryCodec.decode(Data(repeating: 0, count: SculptureBinaryCodec.maximumBytes))
    }
}

@Test func compactChecksumProtectsBothMetadataAndVoxelContent() throws {
    let sculpture = try Sculpture(title: "Shapes", width: 2, height: 3, layers: [Array("#@*+ox".utf8)])
    let valid = try SculptureBinaryCodec.encode(sculpture)
    var checksum = valid
    checksum[28] ^= 1
    #expect(throws: SculptureBinaryCodecError.checksumMismatch) { try SculptureBinaryCodec.decode(checksum) }
    var title = valid
    title[60] = UInt8(ascii: "T")
    #expect(throws: SculptureBinaryCodecError.checksumMismatch) { try SculptureBinaryCodec.decode(title) }
    var reshaped = valid
    binaryWrite(UInt16(3), into: &reshaped, at: 12)
    binaryWrite(UInt16(2), into: &reshaped, at: 14)
    #expect(throws: SculptureBinaryCodecError.checksumMismatch) { try SculptureBinaryCodec.decode(reshaped) }
    let alteredVoxels = Data("#@*+oo".utf8)
    var alteredPayload = valid
    let payload = try SculptureBinaryCodec.compressedPayload(for: alteredVoxels)
    // Keep the original checksum while replacing an otherwise valid compressed stream.
    binaryWrite(UInt32(payload.count), into: &alteredPayload, at: 24)
    alteredPayload = Data(alteredPayload.prefix(60 + Int(binaryUInt16(valid, at: 18))))
    alteredPayload.append(payload)
    #expect(throws: SculptureBinaryCodecError.checksumMismatch) { try SculptureBinaryCodec.decode(alteredPayload) }
}

@Test func compactRejectsTruncationTrailingBytesAndConcatenatedStreamsEvenWithCorrectChecksums() throws {
    let sculpture = try Sculpture(title: "One", width: 1, height: 1, layers: [[35]])
    let valid = try SculptureBinaryCodec.encode(sculpture)
    let payload = binaryPayload(valid)
    let voxels = Data([35])
    for count in 0..<payload.count {
        let truncated = binaryRepack(valid, voxels: voxels, payload: Data(payload.prefix(count)))
        #expect(throws: (any Error).self) { try SculptureBinaryCodec.decode(truncated) }
    }
    var plainTrailing = valid
    plainTrailing.append(0)
    #expect(throws: SculptureBinaryCodecError.invalidLength) { try SculptureBinaryCodec.decode(plainTrailing) }
    var trailingPayload = payload
    trailingPayload.append(0)
    let trailing = binaryRepack(valid, voxels: voxels, payload: trailingPayload)
    #expect(throws: SculptureBinaryCodecError.invalidLength) { try SculptureBinaryCodec.decode(trailing) }
    var combinedPayload = payload
    combinedPayload.append(payload)
    let combined = binaryRepack(valid, voxels: voxels, payload: combinedPayload)
    #expect(throws: SculptureBinaryCodecError.invalidLength) { try SculptureBinaryCodec.decode(combined) }
}

@Test func compactRejectsConcatenationAfterDrainingFourBufferedOutputChunks() throws {
    let sculpture = try Sculpture(
        title: "Buffered prefix",
        width: 64,
        height: 64,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: 4096), count: 64)
    )
    let valid = try SculptureBinaryCodec.encode(sculpture)
    let payload = binaryPayload(valid)
    var combinedPayload = payload
    combinedPayload.append(payload)
    let combined = binaryRepack(
        valid,
        voxels: Data(repeating: Sculpture.empty, count: 4 * 65_536),
        payload: combinedPayload
    )
    // The first stream expands to four output chunks despite all compressed input fitting in one small buffer.
    #expect(payload.count < 65_536)
    #expect(throws: SculptureBinaryCodecError.invalidLength) { try SculptureBinaryCodec.decode(combined) }
}

@Test func compactDecompressionRejectsExpansionBeyondTheDeclaredVolumeAndShortOutput() throws {
    let single = try SculptureBinaryCodec.encode(Sculpture(title: "One", width: 1, height: 1, layers: [[35]]))
    let expansion = Data([35, 35])
    let oversized = binaryRepack(
        single,
        voxels: expansion,
        payload: try SculptureBinaryCodec.compressedPayload(for: expansion)
    )
    #expect(throws: SculptureBinaryCodecError.invalidLength) { try SculptureBinaryCodec.decode(oversized) }
    let double = try SculptureBinaryCodec.encode(Sculpture(title: "Two", width: 2, height: 1, layers: [[35, 35]]))
    let short = Data([35])
    let incomplete = binaryRepack(
        double,
        voxels: short,
        payload: try SculptureBinaryCodec.compressedPayload(for: short)
    )
    #expect(throws: SculptureBinaryCodecError.invalidLength) { try SculptureBinaryCodec.decode(incomplete) }
    let invalidGlyph = Data([33])
    let malformed = binaryRepack(
        single,
        voxels: invalidGlyph,
        payload: try SculptureBinaryCodec.compressedPayload(for: invalidGlyph)
    )
    #expect(throws: SculptureError.invalidGlyph) { try SculptureBinaryCodec.decode(malformed) }
}

@Test func malformedCompressedStreamsFailWithoutUnboundedOutputOrNoProgressLoops() throws {
    let valid = try SculptureBinaryCodec.encode(Sculpture(title: "Fuzz", width: 1, height: 1, layers: [[35]]))
    var seed: UInt64 = 0x3ADB_2026
    for length in 1...96 {
        let bytes = (0..<length).map { _ -> UInt8 in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return UInt8(truncatingIfNeeded: seed >> 32)
        }
        var payload = Data(bytes)
        // No valid LZFSE block begins with zero. Vary the remainder of each malformed stream deterministically.
        payload[0] = 0
        let malformed = binaryRepack(valid, voxels: Data([35]), payload: payload)
        #expect(throws: (any Error).self) { try SculptureBinaryCodec.decode(malformed) }
    }
}

@Test(arguments: ["encode", "decode"]) func compactCodecCancellationDoesNotReturnPartialData(operation: String)
    async throws
{
    let sculpture = Sculpture.orb()
    let encoded = try SculptureBinaryCodec.encode(sculpture)
    let barrier = BinaryCodecCancellationBarrier()
    let task = Task {
        await barrier.wait()
        if operation == "encode" {
            _ = try SculptureBinaryCodec.encode(sculpture)
        } else {
            _ = try SculptureBinaryCodec.decode(encoded)
        }
    }
    task.cancel()
    await barrier.release()
    await #expect(throws: CancellationError.self) { try await task.value }
}

private func binaryUInt16(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
}

private func binaryWrite<T: FixedWidthInteger>(_ value: T, into data: inout Data, at offset: Int) {
    var value = value.littleEndian
    withUnsafeBytes(of: &value) { bytes in data.replaceSubrange(offset..<(offset + bytes.count), with: bytes) }
}

private func binaryPayload(_ data: Data) -> Data {
    Data(data.dropFirst(60 + Int(binaryUInt16(data, at: 18))))
}

/// Creates independently checksummed adversarial records, so decoder refusal cannot rely on a stale checksum.
private func binaryRepack(_ original: Data, voxels: Data, payload: Data) -> Data {
    let title = Data(original.dropFirst(60).prefix(Int(binaryUInt16(original, at: 18))))
    var header = Data(original.prefix(28))
    binaryWrite(UInt32(payload.count), into: &header, at: 24)
    var material = Data()
    material.append(header)
    material.append(title)
    material.append(voxels)
    header.append(SculptureSHA256.hash(material))
    header.append(title)
    header.append(payload)
    return header
}

private actor BinaryCodecCancellationBarrier {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}
