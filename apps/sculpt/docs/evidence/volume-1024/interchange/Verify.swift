import CryptoKit
import Darwin
import Dispatch
import Foundation

// Compile alongside the unchanged pinned engine's Sources/ThreeMDInterop/Protocol.swift.
// This development evidence driver invokes existing public adapters; it changes no library or catalog.
@main
private struct Verify {
    @MainActor
    static func main() async {
        do {
            guard CommandLine.arguments.count == 7,
                CommandLine.arguments[1] == "--worlds", CommandLine.arguments[2].hasPrefix("/"),
                CommandLine.arguments[3] == "--output", CommandLine.arguments[4].hasPrefix("/"),
                CommandLine.arguments[5] == "--source-revision",
                CommandLine.arguments[6].utf8.count == 40,
                CommandLine.arguments[6].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            else {
                throw InterchangeFailure.invalid(
                    "Usage: Verify --worlds /absolute/worlds --output /absolute/interchange --source-revision 40-lowercase-hex"
                )
            }
            try await StudyInterchange(
                worlds: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true),
                output: URL(fileURLWithPath: CommandLine.arguments[4], isDirectory: true),
                sourceRevision: CommandLine.arguments[6]
            ).run()
        } catch {
            FileHandle.standardError.write(Data("World interchange failed: \(error)\n".utf8))
            exit(1)
        }
    }
}

@MainActor
private final class StudyInterchange {
    private let engine = URL(fileURLWithPath: "/private/tmp/sculpt-cross-language-20261005", isDirectory: true)
    private let worlds: URL
    private let output: URL
    private let sourceRevision: String
    private let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
        "sculpt-volume-interchange-\(UUID())",
        isDirectory: true
    )
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maximumLineBytes = 32 * 1_024 * 1_024
    private let maximumTranscriptBytes = 128 * 1_024 * 1_024
    private let maximumStderrBytes = 2 * 1_024 * 1_024
    private var sequence = 0
    private var log: FileHandle?

    init(worlds: URL, output: URL, sourceRevision: String) {
        self.worlds = worlds
        self.output = output
        self.sourceRevision = sourceRevision
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func run() async throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try requireAbsent(output.appendingPathComponent("receipt.json"))
        log = try newFile(output.appendingPathComponent("run.log"))
        defer { try? log?.close() }
        try FileManager.default.createDirectory(
            at: temporary,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try report("Protocol I/O evidence: \(temporary.path)")
        let artifacts = try verifyEngines()
        let adapters = [
            Adapter(
                name: "Swift",
                executable: engine.appendingPathComponent(".build/debug/threemd-interchange"),
                arguments: ["--adapter"]
            ),
            Adapter(
                name: "TypeScript-Node",
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["node", engine.appendingPathComponent("js/scripts/interchange.mjs").path]
            ),
            Adapter(
                name: "Rust",
                executable: engine.appendingPathComponent("rust/target/debug/examples/interchange"),
                arguments: []
            ),
        ]
        let nodeVersion = String(
            decoding: try await execute(
                adapters[1],
                arguments: ["node", "--version"],
                input: Data(),
                label: "node-version"
            ),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let cases = try ["solid-1024", "landscape-1024"].map(loadWorld)
        var baselines: [String: InterchangeResponse] = [:]
        var pairCounts: [String: Int] = [:]
        var producerImports = 0
        var producerRecords: [ProducerRecord] = []
        let clock = ContinuousClock()
        let started = clock.now
        do {
            for producer in adapters {
                for item in cases {
                    for (seedFormat, seed) in [("text", item.text), ("binary-none", item.binary)] {
                        let label = "\(item.id) \(seedFormat) \(producer.name)"
                        let request = InterchangeRequest(kind: "composition", bytesHex: seed.hex)
                        let reply = try await exchange([request], with: producer, label: label + " produce")[0]
                        producerImports += 1
                        try complete(reply, label: label)
                        guard reply.canonicalHex == item.text.hex, reply.binaryHex == item.binary.hex else {
                            throw InterchangeFailure.invalid("\(label): original frozen canonical/binary bytes changed")
                        }
                        if let baseline = baselines[item.id] {
                            try equivalent(baseline, reply, label: label + " producer parity")
                        } else {
                            baselines[item.id] = reply
                        }
                        producerRecords.append(
                            ProducerRecord(
                                world: item.id,
                                inputFormat: seedFormat,
                                language: producer.name,
                                canonicalSHA256: digest(try Data(hex: try required(reply.canonicalHex))),
                                binarySHA256: digest(try Data(hex: try required(reply.binaryHex))),
                                adoptedSHA256: digest(try Data(hex: try required(reply.adoptedHex))),
                                revisionSHA256: digest(try Data(hex: try required(reply.revisionHex))),
                                editedSHA256: digest(try Data(hex: try required(reply.editedHex)))
                            )
                        )
                        let formats = ["canonical", "binary-none", "adopted", "edited"]
                        let payloads = try [reply.canonicalHex, reply.binaryHex, reply.adoptedHex, reply.editedHex].map(
                            required
                        )
                        let requests = payloads.map { InterchangeRequest(kind: "composition", bytesHex: $0) }
                        var consumedBaseline: [InterchangeResponse]?
                        for consumer in adapters {
                            let responses = try await exchange(
                                requests,
                                with: consumer,
                                label: label + " to " + consumer.name
                            )
                            for index in requests.indices {
                                let transferLabel = "\(label) -> \(consumer.name) \(formats[index])"
                                let consumed = responses[index]
                                try complete(consumed, label: transferLabel)
                                if index < 2 {
                                    try equivalent(reply, consumed, label: transferLabel)
                                } else if consumed.canonicalHex != requests[index].bytesHex {
                                    throw InterchangeFailure.invalid(
                                        "\(transferLabel): identity/edit bytes changed on reimport"
                                    )
                                }
                                if let consumedBaseline {
                                    try equivalent(
                                        consumedBaseline[index],
                                        consumed,
                                        label: transferLabel + " consumer parity"
                                    )
                                }
                                pairCounts["\(producer.name) -> \(consumer.name)", default: 0] += 1
                            }
                            if consumedBaseline == nil { consumedBaseline = responses }
                        }
                        try report(
                            "PASS \(label): all three consumers imported canonical, binary, adopted and edited outputs"
                        )
                    }
                }
            }
            guard producerImports == 12, pairCounts.count == 9,
                pairCounts.values.allSatisfy({ $0 == 16 }), pairCounts.values.reduce(0, +) == 144
            else { throw InterchangeFailure.invalid("Incomplete mandatory world/format/language coverage") }
            let receipt = Receipt(
                schema: "sculpt-volume-world-interchange-1",
                passed: true,
                suppliedSculptSourceRevision: sourceRevision,
                engineCheckoutRevision: "1eb8ed2a3dd1b5db3c4b9cb64e38c451f7b8c44b",
                portableCoreRevision: "9dfbdb649891a95f27e7590e9e6ddc72b9e58d08",
                engineRelationship:
                    "Read-only git diff between these revisions was empty for public Swift/TypeScript/Rust sources and the three adapters before this run.",
                engineArtifacts: artifacts,
                nodeVersion: nodeVersion,
                protocol: "3md-interchange-1",
                compression: "none; Apple LZFSE excluded",
                cases: 2,
                seedInputs: 4,
                producerImports: producerImports,
                producerConsumerPairs: 9,
                transferImports: 144,
                pairCounts: pairCounts,
                maximumLineBytes: maximumLineBytes,
                maximumTranscriptBytes: maximumTranscriptBytes,
                maximumStderrBytes: maximumStderrBytes,
                childDeadlineSeconds: 120,
                elapsedSeconds: seconds(started.duration(to: clock.now)),
                fixtureFiles: cases.flatMap(\.files),
                producerResults: producerRecords,
                protocolIOEvidence: temporary.path,
                notes: [
                    "Both original portable text and original uncompressed binary seed each world through every producer.",
                    "Each producer's canonical text and binary must exactly equal the generated original files, including opaque Sculpt metadata and JSON strings.",
                    "All nine pairs import canonical, binary, identity-adopted and deterministically edited outputs; exact semantic values, revisions and stale-patch rejection are checked.",
                    "Exact Unicode comparison and duplicate/equivalent protocol JSON key rejection use the unchanged pinned Protocol.swift.",
                    "ThreeMD runtimes preserve Sculpt world JSON as opaque content; this check does not implement or interpret the Sculpt schema in Node or Rust.",
                    "The adapter's deterministic root-plane edit is a ThreeMD transaction test; its edited body is not asserted to remain a valid Sculpt world.",
                    "This focused development evidence does not rerun or modify the existing 429-case catalog, raise production limits, or establish new product capabilities.",
                ]
            )
            let formatted = JSONEncoder()
            formatted.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try formatted.encode(receipt)
            try Task.checkCancellation()
            let file = try newFile(output.appendingPathComponent("receipt.json"))
            defer { try? file.close() }
            try file.write(contentsOf: data + Data([10]))
            try file.synchronize()
            try report(
                "PASS two worlds, four original inputs, 12 producer imports, 144 transfer imports across nine pairs"
            )
        } catch {
            try? report("FAIL \(error)")
            throw error
        }
    }

    private func verifyEngines() throws -> [Artifact] {
        let expected = [
            (".build/debug/threemd-interchange", "ce409974e5cb7667e347f9d59f7eeb497b4db4c0a6d19e65d0d08bc3225d136a"),
            ("js/dist/index.js", "55f7942ac0e20740e2dad042dad99824ec75afcfeac6958bde7b1db7dbdb14f1"),
            (
                "rust/target/debug/examples/interchange",
                "e58d03abdaa9f9ffaa190de28aa80f5e03d114dfdd914f5f0f8888c47ecf23ef"
            ),
            (
                "Sources/ThreeMDInterop/Protocol.swift",
                "dee56abb50c4979d4c02b9cc6002b216324f8135472192be1648025b44073d2e"
            ),
            (
                "Sources/ThreeMDInterop/SwiftAdapter.swift",
                "58b76c2a50adbb07f2c15fa21d82fac2f85125198687adb3f52eb66225bb998c"
            ),
            ("Sources/ThreeMDInterop/main.swift", "0c7246e953b5de12dc3ae66bc1fe69c69c06d10eb9ac75b8b525d8c5f5f6fe86"),
            ("js/scripts/interchange.mjs", "897fe27483ae006926c522e4e160cfbaf7172400c198de6edcd7c094269849be"),
            ("rust/examples/interchange.rs", "eb10126ad7bb8763fdceecf2c171524cbe75eefee791ff1baa597a279e6b2da9"),
        ]
        return try expected.map { path, hash in
            let url = engine.appendingPathComponent(path)
            let data = try boundedFile(url, maximum: 8 * 1_024 * 1_024)
            let actual = digest(data)
            guard actual == hash else { throw InterchangeFailure.invalid("Pinned engine artifact changed: \(path)") }
            return Artifact(path: url.path, bytes: data.count, sha256: actual)
        }
    }

    private func loadWorld(_ id: String) throws -> WorldCase {
        let textURL = worlds.appendingPathComponent(id + ".portable.3md")
        let binaryURL = worlds.appendingPathComponent(id + ".portable.3mdb")
        let text = try boundedFile(textURL, maximum: 8 * 1_024 * 1_024)
        let binary = try boundedFile(binaryURL, maximum: 8 * 1_024 * 1_024)
        guard !text.isEmpty, !binary.isEmpty else { throw InterchangeFailure.invalid("Empty study world") }
        return WorldCase(
            id: id,
            text: text,
            binary: binary,
            files: [
                Artifact(path: textURL.path, bytes: text.count, sha256: digest(text)),
                Artifact(path: binaryURL.path, bytes: binary.count, sha256: digest(binary)),
            ]
        )
    }

    private func complete(_ reply: InterchangeResponse, label: String) throws {
        guard reply.ok, reply.error == nil, reply.semantic != nil, reply.staleRejected == true,
            reply.revisionHex == reply.adoptedHex
        else { throw InterchangeFailure.invalid("\(label): incomplete/failed response \(reply.error ?? "")") }
        for field in [reply.canonicalHex, reply.binaryHex, reply.adoptedHex, reply.revisionHex, reply.editedHex] {
            let value = try required(field)
            guard !value.isEmpty, value.utf8.count.isMultiple(of: 2), value.utf8.count <= maximumLineBytes,
                value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            else { throw InterchangeFailure.invalid("\(label): malformed protocol hex") }
        }
    }

    private func equivalent(_ expected: InterchangeResponse, _ actual: InterchangeResponse, label: String) throws {
        guard actual.ok, actual.semantic == expected.semantic,
            actual.canonicalHex == expected.canonicalHex, actual.binaryHex == expected.binaryHex,
            actual.adoptedHex == expected.adoptedHex, actual.revisionHex == expected.revisionHex,
            actual.editedHex == expected.editedHex, actual.staleRejected == true
        else { throw InterchangeFailure.invalid("\(label): exact semantic/canonical/revision/edit parity failed") }
    }

    private func exchange(_ requests: [InterchangeRequest], with adapter: Adapter, label: String) async throws
        -> [InterchangeResponse]
    {
        guard (1...4).contains(requests.count) else { throw InterchangeFailure.invalid("Invalid bounded batch") }
        var input = Data()
        for request in requests {
            let line = try encoder.encode(request)
            guard line.count <= maximumLineBytes else {
                throw InterchangeFailure.invalid("Protocol request line limit")
            }
            input.append(line); input.append(10)
        }
        let data = try await execute(adapter, arguments: adapter.arguments, input: input, label: label)
        guard data.last == 10 else { throw InterchangeFailure.invalid("Incomplete response transcript: \(label)") }
        let lines = data.split(separator: 10, omittingEmptySubsequences: false).dropLast()
        guard lines.count == requests.count else { throw InterchangeFailure.invalid("Missing/extra reply: \(label)") }
        return try lines.map { bytes in
            let line = Data(bytes)
            guard !line.isEmpty, line.count <= maximumLineBytes else {
                throw InterchangeFailure.invalid("Invalid response line")
            }
            try validateInterchangeJSON(line)
            return try decoder.decode(InterchangeResponse.self, from: line)
        }
    }

    private func execute(_ adapter: Adapter, arguments: [String], input: Data, label: String) async throws -> Data {
        try Task.checkCancellation()
        guard input.count <= maximumTranscriptBytes else { throw InterchangeFailure.invalid("Input transcript limit") }
        sequence += 1
        let stem = "\(sequence)-\(adapter.name)"
        let inputURL = temporary.appendingPathComponent(stem + ".input.jsonl")
        let outputURL = temporary.appendingPathComponent(stem + ".output.jsonl")
        let stderrURL = temporary.appendingPathComponent(stem + ".stderr.txt")
        let source = try newFile(inputURL)
        try source.write(contentsOf: input)
        try source.close()
        let reader = try existingFile(inputURL)
        let writer = try newFile(outputURL)
        let errors = try newFile(stderrURL)
        defer { try? reader.close(); try? writer.close(); try? errors.close() }
        let process = Process()
        process.executableURL = adapter.executable
        process.arguments = arguments
        process.currentDirectoryURL = engine
        process.standardInput = reader; process.standardOutput = writer; process.standardError = errors
        try process.run()
        do {
            let started = DispatchTime.now().uptimeNanoseconds
            while process.isRunning {
                try Task.checkCancellation()
                guard DispatchTime.now().uptimeNanoseconds - started < 120_000_000_000 else {
                    throw InterchangeFailure.invalid("Child deadline: \(label)")
                }
                try budget(writer, maximum: maximumTranscriptBytes)
                try budget(errors, maximum: maximumStderrBytes)
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            try await stop(process)
            throw error
        }
        process.waitUntilExit()
        try budget(writer, maximum: maximumTranscriptBytes)
        try budget(errors, maximum: maximumStderrBytes)
        guard process.terminationStatus == 0 else {
            throw InterchangeFailure.invalid("\(label): child exit \(process.terminationStatus); see \(stderrURL.path)")
        }
        return try boundedFile(outputURL, maximum: maximumTranscriptBytes)
    }

    private func stop(_ process: Process) async throws {
        guard process.isRunning else { process.waitUntilExit(); return }
        process.terminate()
        let started = DispatchTime.now().uptimeNanoseconds
        while process.isRunning, !Task.isCancelled, DispatchTime.now().uptimeNanoseconds - started < 250_000_000 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        let killed = DispatchTime.now().uptimeNanoseconds
        while process.isRunning, DispatchTime.now().uptimeNanoseconds - killed < 1_000_000_000 {
            await Task.detached { try? await Task.sleep(for: .milliseconds(10)) }.value
        }
        guard !process.isRunning else { throw InterchangeFailure.invalid("Owned child did not exit after kill") }
        process.waitUntilExit()
    }

    private func boundedFile(_ url: URL, maximum: Int) throws -> Data {
        let file = try existingFile(url)
        defer { try? file.close() }
        try budget(file, maximum: maximum)
        var data = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount: min(65_536, maximum - data.count + 1)) ?? Data()
            guard !chunk.isEmpty else { return data }
            guard chunk.count <= maximum - data.count else {
                throw InterchangeFailure.invalid("File limit: \(url.path)")
            }
            data.append(chunk)
        }
    }

    private func budget(_ file: FileHandle, maximum: Int) throws {
        var info = stat()
        guard fstat(file.fileDescriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
            info.st_size >= 0, info.st_size <= maximum
        else { throw InterchangeFailure.invalid("Regular-file/transcript size limit") }
    }

    private func existingFile(_ url: URL) throws -> FileHandle {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func newFile(_ url: URL) throws -> FileHandle {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func requireAbsent(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 { throw InterchangeFailure.invalid("Existing evidence refused: \(url.path)") }
        guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func required(_ value: String?) throws -> String {
        guard let value else { throw InterchangeFailure.invalid("Missing mandatory protocol field") }
        return value
    }

    private func report(_ message: String) throws {
        print(message)
        try log?.write(contentsOf: Data((message + "\n").utf8))
    }

    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private struct Adapter { let name: String; let executable: URL; let arguments: [String] }
    private struct WorldCase { let id: String; let text: Data; let binary: Data; let files: [Artifact] }
    private struct Artifact: Codable { let path: String; let bytes: Int; let sha256: String }
    private struct ProducerRecord: Codable {
        let world: String; let inputFormat: String; let language: String
        let canonicalSHA256: String; let binarySHA256: String; let adoptedSHA256: String
        let revisionSHA256: String; let editedSHA256: String
    }
    private struct Receipt: Codable {
        let schema: String; let passed: Bool; let suppliedSculptSourceRevision: String
        let engineCheckoutRevision: String; let portableCoreRevision: String; let engineRelationship: String
        let engineArtifacts: [Artifact]; let nodeVersion: String; let `protocol`: String; let compression: String
        let cases: Int; let seedInputs: Int; let producerImports: Int; let producerConsumerPairs: Int
        let transferImports: Int; let pairCounts: [String: Int]
        let maximumLineBytes: Int; let maximumTranscriptBytes: Int; let maximumStderrBytes: Int
        let childDeadlineSeconds: Int; let elapsedSeconds: Double
        let fixtureFiles: [Artifact]; let producerResults: [ProducerRecord]
        let protocolIOEvidence: String; let notes: [String]
    }
}
