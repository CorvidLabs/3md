import CryptoKit
import Foundation
import Testing

@testable import RookTool

private final class StudyCancellationGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var reached = false
    private var released = false

    func stopAtEncode(_ message: String) {
        guard message == "encode: starting" else { return }
        condition.lock()
        reached = true
        condition.broadcast()
        while !released { condition.wait() }
        condition.unlock()
    }

    var hasReachedEncode: Bool {
        condition.lock()
        defer { condition.unlock() }
        return reached
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class StudyStagingReplacement: @unchecked Sendable {
    let parent: URL
    let phase: String
    private(set) var replacement: URL?
    private(set) var failure: (any Error)?

    init(parent: URL, phase: String) { self.parent = parent; self.phase = phase }

    func replace(_ message: String) {
        guard message == "\(phase): starting" else { return }
        do {
            let entries = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            guard let staging = entries.first(where: { $0.lastPathComponent.hasPrefix(".volume-study-") }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            try FileManager.default.moveItem(at: staging, to: parent.appendingPathComponent("moved-staging"))
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            try Data("Foreign content".utf8).write(to: staging.appendingPathComponent("sentinel"))
            replacement = staging
        } catch { failure = error }
    }
}

@Suite("Dense volume study reduced fixtures", .serialized)
struct SculptureVolumeStudyTests {
    @Test func strictCLIRequiresAbsoluteNewOutputAndExplicitDenseOptIn() throws {
        #expect(SculptureVolumeStudy.denseEdge == 1_024 && SculptureVolumeStudy.denseBytes == 1_073_741_824)
        let valid = ["--output", "/private/tmp/new-volume-study", "--dense-1024"]
        #expect(try SculptureVolumeStudy.outputDirectory(valid).path == "/private/tmp/new-volume-study")
        for arguments in [
            [], ["--dense-1024"], ["--output", "relative", "--dense-1024"],
            ["--output", "/", "--dense-1024"], valid + ["--force"], ["--output", "/tmp/dense", "--dense-1024\0"],
        ] {
            #expect(throws: (any Error).self) { try SculptureVolumeStudy.outputDirectory(arguments) }
        }
        #if DEBUG
        #expect(throws: (any Error).self) {
            try SculptureVolumeStudy.run(arguments: valid, workingDirectory: URL(fileURLWithPath: "/"))
        }
        #endif
    }

    @Test func reducedDenseStudyTouchesHashesStreamsAndComparesEveryByte() throws {
        let parent = try folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let output = parent.appendingPathComponent("study")
        let receipt = try SculptureVolumeStudy.measure(
            edge: 16,
            output: output,
            minimumFreeReserveBytes: 0,
            memory: sufficientMemory,
            progress: { _ in }
        )
        #expect(receipt.rawBytes == 4_096 && receipt.initializedBytes == 4_096 && receipt.decodedBytes == 4_096)
        let expected = digest(Data(repeating: 1, count: 4_096))
        #expect(receipt.rawSHA256 == expected && receipt.decodedSHA256 == expected)
        let encoded = try Data(contentsOf: output.appendingPathComponent(receipt.artifact))
        #expect(receipt.encodedBytes == encoded.count && receipt.encodedSHA256 == digest(encoded))
        #expect(receipt.artifact == "dense-16.voxels.lzfse")
        #expect(receipt.phases.map(\.name) == ["allocate", "fill", "hash", "encode", "decode-verify", "release"])
        #expect(receipt.phases.allSatisfy { $0.elapsedSeconds >= 0 })
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("receipt.json")))
                as? [String: Any]
        )
        #expect(json["schema"] as? String == "sculpt-dense-volume-study-1")
        let memory = try #require(json["memoryBeforeGuard"] as? [String: Any])
        #expect(memory["physicalFootprintBytes"] is NSNull && memory["processLimitRemainingBytes"] is NSNull)
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["study"])
    }

    @Test func resourceGuardRefusesBeforeCreatingOutputAndHonorsKernelProcessLimit() throws {
        let parent = try folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let output = parent.appendingPathComponent("refused")
        let insufficient = memory(free: 4_095)
        #expect(throws: (any Error).self) {
            try SculptureVolumeStudy.measure(
                edge: 16,
                output: output,
                minimumFreeReserveBytes: 0,
                memory: { insufficient },
                progress: { _ in }
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
        #expect(throws: (any Error).self) {
            try SculptureVolumeStudy.guardResources(payloadBytes: 4_096, reserve: 1, memory: memory(free: 4_096))
        }
        #expect(throws: (any Error).self) {
            try SculptureVolumeStudy.guardResources(
                payloadBytes: 4_096,
                reserve: 0,
                memory: memory(free: 10_000, process: 4_095)
            )
        }
        #expect(throws: (any Error).self) {
            try SculptureVolumeStudy.guardResources(
                payloadBytes: 4_096,
                reserve: UInt64.max,
                memory: sufficientMemory()
            )
        }
        #expect(throws: (any Error).self) {
            try SculptureVolumeStudy.guardResources(payloadBytes: 4_096, reserve: 0, memory: memory(free: nil))
        }
        try SculptureVolumeStudy.guardResources(payloadBytes: 4_096, reserve: 0, memory: memory(free: 4_096))
        #if DEBUG
        #expect(throws: (any Error).self) {
            try SculptureVolumeStudy.measure(edge: 1_024, output: output, memory: sufficientMemory, progress: { _ in })
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
        #endif
    }

    @Test func reduced64CubePatternCrossesEachBlockAxisAndHasAnIndependentDigest() throws {
        let parent = try folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let receipt = try SculptureVolumeStudy.measure(
            edge: 64,
            output: parent.appendingPathComponent("pattern"),
            minimumFreeReserveBytes: 0,
            memory: sufficientMemory,
            progress: { _ in }
        )
        var expected = Data()
        expected.reserveCapacity(64 * 64 * 64)
        for z in 0..<64 {
            for y in 0..<64 {
                for x in 0..<64 {
                    expected.append(UInt8(1 + ((x / 32) * 17 + (y / 32) * 31 + (z / 32) * 47) % 254))
                }
            }
        }
        #expect(Set(expected) == Set([1, 18, 32, 48, 49, 65, 79, 96]))
        #expect(receipt.rawBytes == expected.count && receipt.initializedBytes == expected.count)
        #expect(receipt.rawSHA256 == digest(expected) && receipt.decodedSHA256 == digest(expected))
    }

    @Test func stagingReplacementBeforeEncodingOrPublicationPreservesForeignContent() throws {
        for phase in ["encode", "release"] {
            let parent = try folder()
            defer { try? FileManager.default.removeItem(at: parent) }
            let output = parent.appendingPathComponent("study")
            let hook = StudyStagingReplacement(parent: parent, phase: phase)
            #expect(throws: (any Error).self) {
                try SculptureVolumeStudy.measure(
                    edge: 16,
                    output: output,
                    minimumFreeReserveBytes: 0,
                    memory: sufficientMemory,
                    progress: hook.replace
                )
            }
            #expect(hook.failure == nil)
            let replacement = try #require(hook.replacement)
            #expect(
                try Data(contentsOf: replacement.appendingPathComponent("sentinel")) == Data("Foreign content".utf8)
            )
            #expect(try FileManager.default.contentsOfDirectory(atPath: replacement.path) == ["sentinel"])
            #expect(!FileManager.default.fileExists(atPath: output.path))
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: parent.appendingPathComponent("moved-staging").path)
                    .isEmpty
            )
        }
    }

    @Test func newOutputGuardPreservesExistingDirectoriesAndSymbolicLinks() throws {
        let parent = try folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let existing = parent.appendingPathComponent("existing")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        let sentinel = existing.appendingPathComponent("sentinel")
        try Data("Keep".utf8).write(to: sentinel)
        let link = parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: existing)
        for destination in [existing, link] {
            #expect(throws: (any Error).self) {
                try SculptureVolumeStudy.measure(
                    edge: 16,
                    output: destination,
                    minimumFreeReserveBytes: 0,
                    memory: sufficientMemory,
                    progress: { _ in }
                )
            }
        }
        #expect(try Data(contentsOf: sentinel) == Data("Keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).sorted() == ["existing", "link"])
    }

    @Test func streamingVerificationRejectsCorruptionTruncationConcatenationAndLengthMismatch() throws {
        let parent = try folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        var raw = Data(count: 2 * SculptureVolumeStudy.chunkBytes + 17)
        raw.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            var state: UInt32 = 0x6D2B_79F5
            for index in bytes.indices {
                state ^= state << 13
                state ^= state >> 17
                state ^= state << 5
                bytes[index] = UInt8(truncatingIfNeeded: state)
            }
        }
        try raw.withUnsafeBytes { bytes in
            let source = try #require(bytes.baseAddress)
            let original = parent.appendingPathComponent("original.voxels.lzfse")
            let facts = try SculptureVolumeStudy.encode(source, byteCount: bytes.count, output: original)
            #expect(facts.bytes > 2 * SculptureVolumeStudy.chunkBytes)
            let decoded = try SculptureVolumeStudy.verify(
                original,
                expected: source,
                byteCount: bytes.count,
                encoded: facts
            )
            #expect(decoded.bytes == bytes.count && decoded.sha256 == digest(raw))
            // The incompressible file spans multiple POSIX reads through the same fixed scratch allocation.
            #expect(decoded.readBufferBytes == SculptureVolumeStudy.chunkBytes)
            #expect(decoded.maximumReadBytes == SculptureVolumeStudy.chunkBytes && decoded.readCalls >= 6)
            let data = try Data(contentsOf: original)
            var changed = data
            changed[changed.count / 2] ^= 0x5A
            let corruptions = [changed, Data(data.dropLast()), data + data, data + Data([0x62, 0x76, 0x78, 0x24])]
            for (index, value) in corruptions.enumerated() {
                let file = parent.appendingPathComponent("corrupt-\(index)")
                try value.write(to: file)
                let revised = SculptureVolumeStudy.Encoded(bytes: value.count, sha256: digest(value))
                #expect(throws: (any Error).self) {
                    try SculptureVolumeStudy.verify(file, expected: source, byteCount: bytes.count, encoded: revised)
                }
            }
            #expect(throws: (any Error).self) {
                try SculptureVolumeStudy.verify(original, expected: source, byteCount: bytes.count - 1, encoded: facts)
            }
            let wrong = SculptureVolumeStudy.Encoded(bytes: facts.bytes, sha256: String(repeating: "0", count: 64))
            #expect(throws: (any Error).self) {
                try SculptureVolumeStudy.verify(original, expected: source, byteCount: bytes.count, encoded: wrong)
            }
        }
    }

    @Test func cancellationAfterAllocationCleansStagingAndPublishesNothing() async throws {
        let parent = try folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let output = parent.appendingPathComponent("cancelled")
        let gate = StudyCancellationGate()
        let task = Task.detached {
            try SculptureVolumeStudy.measure(
                edge: 32,
                output: output,
                minimumFreeReserveBytes: 0,
                memory: sufficientMemory,
                progress: gate.stopAtEncode
            )
        }
        for _ in 0..<100_000 where !gate.hasReachedEncode { await Task.yield() }
        #expect(gate.hasReachedEncode)
        task.cancel()
        gate.release()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch {
            #expect(error is CancellationError)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookVolumeStudy-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }
    private func memory(free: UInt64?, process: UInt64? = nil) -> SculptureVolumeStudy.MemorySample {
        .init(
            systemFreeBytes: free,
            residentBytes: nil,
            residentPeakBytes: nil,
            physicalFootprintBytes: nil,
            physicalFootprintPeakBytes: nil,
            processLimitRemainingBytes: process
        )
    }
    private func sufficientMemory() -> SculptureVolumeStudy.MemorySample { memory(free: 1 << 34) }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
