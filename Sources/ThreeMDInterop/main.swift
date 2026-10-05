import Dispatch
import Foundation
import ThreeMD

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private struct Catalog: Decodable {
    let schema: String
    let numericVectors: String
    let cases: [Fixture]

    struct Fixture: Decodable {
        let id: String
        let kind: String
        let sourceFile: String
        let canonicalFile: String?
        let binaryFile: String?
        let formats: [String]
        let expectedError: String?
    }
}

private struct NumericCatalog: Decodable {
    let schema: String
    let vectors: [Vector]
    struct Vector: Decodable { let name: String; let bitPattern: String; let formatted: String }
}

private struct CheckCase {
    let id: String
    let request: InterchangeRequest
    let formats: [String]
    let expectedCanonical: String?
    let expectedBinary: String?
    let expectedError: String?
    let expectedZBits: String?
    var expectedSemantic: JSONValue?
}

private struct Transfer {
    let id: String
    let producer: String
    let format: String
    let request: InterchangeRequest
    let expected: InterchangeResponse
    let compareOriginal: Bool
}

private struct Adapter {
    let name: String
    let executable: String
    let arguments: [String]
}

@available(macOS 10.15, *)
private final class InterchangeCoordinator {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("3md-interchange-\(UUID())")
    private let maximumTranscriptBytes = 256 * 1024 * 1024

    func run() async throws {
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        encoder.outputFormatting = [.sortedKeys]
        let cases = try loadCases()
        let executable = CommandLine.arguments[0]
        let adapters = [
            Adapter(name: "Swift", executable: executable, arguments: ["--adapter"]),
            Adapter(
                name: "TypeScript-Node",
                executable: "/usr/bin/env",
                arguments: ["node", "js/scripts/interchange.mjs"]
            ),
            Adapter(
                name: "Rust",
                executable: root.appendingPathComponent("rust/target/debug/examples/interchange").path,
                arguments: []
            ),
        ]
        try checkExactJSONRegression()
        try await checkAdapterBounds(adapters[0])
        #if canImport(Darwin) || canImport(Glibc)
        try await checkWatchdog(executable)
        #endif
        var producers: [[InterchangeResponse]] = []
        for adapter in adapters {
            let replies = try await exchange(cases.map(\.request), with: adapter, phase: "produce")
            for (item, reply) in zip(cases, replies) { try checkProduced(item, reply, language: adapter.name) }
            producers.append(replies)
        }
        guard let baseline = producers.first else { throw InterchangeFailure.invalid("No producers") }
        for (index, producer) in producers.enumerated() {
            for (item, pair) in zip(cases, zip(baseline, producer)) where item.expectedError == nil {
                try equivalent(pair.0, pair.1, label: "\(item.id) producer \(adapters[index].name)")
            }
        }
        var transfers: [Transfer] = []
        for (producerIndex, output) in producers.enumerated() {
            for (item, reply) in zip(cases, output) where item.expectedError == nil {
                for format in item.formats + ["adopted", "edited"] {
                    let hex: String?
                    switch format {
                    case "canonical": hex = reply.canonicalHex
                    case "binary": hex = reply.binaryHex
                    case "legacy": hex = reply.legacyHex
                    case "adopted": hex = reply.adoptedHex
                    case "edited": hex = reply.editedHex
                    default: throw InterchangeFailure.invalid("Unknown mandatory format \(format)")
                    }
                    guard let hex else { throw InterchangeFailure.invalid("Missing \(item.id) \(format)") }
                    transfers.append(
                        Transfer(
                            id: item.id,
                            producer: adapters[producerIndex].name,
                            format: format,
                            request: .init(kind: item.request.kind, bytesHex: hex),
                            expected: reply,
                            compareOriginal: format != "adopted" && format != "edited"
                        )
                    )
                }
            }
        }
        var pairCounts: [String: Int] = [:]
        for adapter in adapters {
            let replies = try await exchange(transfers.map(\.request), with: adapter, phase: "consume")
            for (item, reply) in zip(transfers, replies) {
                let label = "\(item.id) \(item.producer) -> \(adapter.name) \(item.format)"
                guard reply.ok else { throw InterchangeFailure.invalid("\(label): \(reply.error ?? "missing error")") }
                if item.compareOriginal {
                    try equivalent(item.expected, reply, label: label)
                } else {
                    guard reply.canonicalHex == item.request.bytesHex else {
                        throw InterchangeFailure.invalid("\(label): identity/edit canonical bytes changed on import")
                    }
                }
                pairCounts["\(item.producer) -> \(adapter.name)", default: 0] += 1
            }
        }
        guard pairCounts.count == 9 else { throw InterchangeFailure.invalid("Missing producer/consumer pair") }
        let receipt: [String: JSONValue] = [
            "schema": .string("3md-interchange-receipt-1"), "cases": .number(Double(cases.count)),
            "producerConsumerPairs": .number(9), "imports": .number(Double(transfers.count * adapters.count)),
            "pairCounts": .object(pairCounts.mapValues { .number(Double($0)) }),
            "compression": .string("none; optional Apple LZFSE excluded"), "passed": .bool(true),
        ]
        let data = try encoder.encode(JSONValue.object(receipt))
        try data.write(to: temporary.appendingPathComponent("receipt.json"), options: .atomic)
        print(String(decoding: data, as: UTF8.self))
        print("Interchange evidence: \(temporary.path)")
    }

    private func loadCases() throws -> [CheckCase] {
        let catalog: Catalog = try read("conformance/interchange/manifest.json")
        guard catalog.schema == "3md-interchange-catalog-1", !catalog.cases.isEmpty else {
            throw InterchangeFailure.invalid("Unsupported or empty catalog")
        }
        var ids: Set<String> = []
        var cases: [CheckCase] = []
        for fixture in catalog.cases {
            guard ids.insert(fixture.id).inserted, ["document", "composition"].contains(fixture.kind) else {
                throw InterchangeFailure.invalid("Duplicate/invalid mandatory catalog ID \(fixture.id)")
            }
            guard fixture.expectedError != "adapterFailure" else {
                throw InterchangeFailure.invalid("Catalog cannot accept an unclassified adapterFailure")
            }
            let bytes = try readBytes(fixture.sourceFile)
            cases.append(
                CheckCase(
                    id: fixture.id,
                    request: .init(kind: fixture.kind, bytesHex: bytes.hex),
                    formats: fixture.formats,
                    expectedCanonical: try fixture.canonicalFile.map { try readBytes($0).hex },
                    expectedBinary: try fixture.binaryFile.map { try readBytes($0).hex },
                    expectedError: fixture.expectedError,
                    expectedZBits: nil
                )
            )
        }
        let legacyFiles = try FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent("conformance").path
        )
        .filter { $0.hasSuffix(".json") }.sorted()
        guard !legacyFiles.isEmpty else { throw InterchangeFailure.invalid("Legacy corpus missing") }
        for file in legacyFiles {
            let value: JSONValue = try read("conformance/\(file)")
            guard case .object(let vector) = value, case .string(let source) = vector["source"] else {
                throw InterchangeFailure.invalid("Unknown mandatory legacy fixture \(file)")
            }
            let invalid: Bool
            if case .string = vector["error"] {
                invalid = true
            } else if vector["expected"] != nil || vector["links"] != nil {
                invalid = false
            } else {
                throw InterchangeFailure.invalid("Legacy fixture has no expectation: \(file)")
            }
            cases.append(
                CheckCase(
                    id: "legacy-json-\(file)",
                    request: .init(kind: "document", bytesHex: Data(source.utf8).hex),
                    formats: invalid ? [] : ["canonical", "binary", "legacy"],
                    expectedCanonical: nil,
                    expectedBinary: nil,
                    expectedError: invalid ? "invalidText" : nil,
                    expectedZBits: nil,
                    expectedSemantic: try vector["expected"].map(expectedDocument)
                )
            )
        }
        let numbers: NumericCatalog = try read(catalog.numericVectors)
        guard numbers.schema == "3md-canonical-numbers-1", !numbers.vectors.isEmpty else {
            throw InterchangeFailure.invalid("Unsupported/empty numeric catalog")
        }
        for vector in numbers.vectors {
            guard let bits = UInt64(vector.bitPattern, radix: 16), Double(bitPattern: bits).isFinite else {
                throw InterchangeFailure.invalid("Invalid numeric vector \(vector.name)")
            }
            let source = "---\n3md: \"1.1\"\naxis: \"layer\"\n---\n\n@plane z=\(vector.formatted)\nnumber\n"
            cases.append(
                CheckCase(
                    id: "number-\(vector.name)",
                    request: .init(kind: "document", bytesHex: Data(source.utf8).hex),
                    formats: ["canonical", "binary", "legacy"],
                    expectedCanonical: Data(source.utf8).hex,
                    expectedBinary: nil,
                    expectedError: nil,
                    expectedZBits: normalizedBits(bits)
                )
            )
        }
        var seed: UInt64 = 0x3_6d64_2026_1005
        for index in 0..<256 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let bits = seed & 0xffef_ffff_ffff_ffff
            let number = Double(bitPattern: bits)
            guard number.isFinite else { throw InterchangeFailure.invalid("Generated nonfinite number") }
            let document = Document(
                version: "1.1",
                axis: .space,
                planes: [.init(z: number, x: -number, y: 0, body: "generated \(index)")]
            )
            let text = try DocumentStorageCodec.encode(document)
            cases.append(
                CheckCase(
                    id: "generated-number-\(index)",
                    request: .init(kind: "document", bytesHex: text.hex),
                    formats: ["canonical", "binary", "legacy"],
                    expectedCanonical: text.hex,
                    expectedBinary: nil,
                    expectedError: nil,
                    expectedZBits: normalizedBits(bits)
                )
            )
        }
        guard Set(cases.map(\.id)).count == cases.count else {
            throw InterchangeFailure.invalid("Duplicate runtime case ID")
        }
        for item in cases {
            if item.expectedError == nil {
                guard Set(item.formats).count == item.formats.count,
                    Set(item.formats).isSuperset(of: ["canonical", "binary"]),
                    Set(item.formats).isSubset(of: ["canonical", "binary", "legacy"])
                else {
                    throw InterchangeFailure.invalid("Invalid format coverage \(item.id)")
                }
            }
        }
        return cases
    }

    private func expectedDocument(_ value: JSONValue) throws -> JSONValue {
        guard case .object(let document) = value, case .array(let sourcePlanes) = document["planes"] else {
            throw InterchangeFailure.invalid("Legacy expected document malformed")
        }
        var result = document
        result["title"] = result["title"] ?? .null
        result["preamble"] = result["preamble"] ?? .null
        result["metadata"] = result["metadata"] ?? .object([:])
        result["planes"] = .array(
            try sourcePlanes.map { source in
                guard case .object(let plane) = source else {
                    throw InterchangeFailure.invalid("Expected plane malformed")
                }
                var normalized = plane
                for key in ["z", "x", "y"] {
                    switch plane[key] {
                    case .number(let number): normalized["\(key)Bits"] = .string(normalizedBits(number.bitPattern))
                    case .null, nil: normalized["\(key)Bits"] = .null
                    default: throw InterchangeFailure.invalid("Expected coordinate malformed")
                    }
                    normalized.removeValue(forKey: key)
                }
                normalized["label"] = normalized["label"] ?? .null
                normalized["attributes"] = normalized["attributes"] ?? .object([:])
                return .object(normalized)
            }
        )
        return .object(result)
    }

    private func normalizedBits(_ bits: UInt64) -> String {
        let normalized = Double(bitPattern: bits) == 0 ? UInt64(0) : bits
        return String(repeating: "0", count: max(0, 16 - String(normalized, radix: 16).count))
            + String(normalized, radix: 16)
    }

    private func checkProduced(_ item: CheckCase, _ reply: InterchangeResponse, language: String) throws {
        let label = "\(item.id) \(language)"
        if let error = item.expectedError {
            guard !reply.ok, reply.error == error else {
                throw InterchangeFailure.invalid("\(label): expected \(error), got \(reply.error ?? "success")")
            }
            return
        }
        guard reply.ok, reply.error == nil, reply.canonicalHex != nil, reply.binaryHex != nil,
            reply.adoptedHex != nil, reply.editedHex != nil, reply.semantic != nil, reply.staleRejected == true,
            reply.revisionHex == reply.adoptedHex
        else {
            throw InterchangeFailure.invalid("\(label): invalid/incomplete producer response \(reply.error ?? "")")
        }
        if let expected = item.expectedCanonical, reply.canonicalHex != expected {
            throw InterchangeFailure.invalid("\(label): fixed canonical bytes differ")
        }
        if let expected = item.expectedBinary, reply.binaryHex != expected {
            throw InterchangeFailure.invalid("\(label): fixed binary bytes differ")
        }
        if let expected = item.expectedSemantic, reply.semantic != expected {
            throw InterchangeFailure.invalid("\(label): frozen fixture semantics changed")
        }
        if let bits = item.expectedZBits {
            guard case .object(let document) = reply.semantic,
                case .array(let planes) = document["planes"], let first = planes.first,
                case .object(let plane) = first, plane["zBits"] == .string(bits)
            else {
                throw InterchangeFailure.invalid("\(label): numeric bit pattern changed")
            }
        }
        if item.request.kind == "document", !DocumentStorageCodec.isBinary(try Data(hex: item.request.bytesHex)),
            reply.rawCanonicalHex != reply.canonicalHex
        {
            throw InterchangeFailure.invalid("\(label): raw parser and bounded codec disagree")
        }
    }

    private func equivalent(_ expected: InterchangeResponse, _ actual: InterchangeResponse, label: String) throws {
        guard actual.ok, actual.semantic == expected.semantic else {
            throw InterchangeFailure.invalid("\(label): semantic content differs")
        }
        let fields: [(String, String?, String?)] = [
            ("canonical", expected.canonicalHex, actual.canonicalHex), ("binary", expected.binaryHex, actual.binaryHex),
            ("adopted", expected.adoptedHex, actual.adoptedHex), ("revision", expected.revisionHex, actual.revisionHex),
            ("edited", expected.editedHex, actual.editedHex),
        ]
        for (field, first, second) in fields where first != second {
            throw InterchangeFailure.invalid("\(label): \(field) bytes differ")
        }
        guard actual.staleRejected == true else { throw InterchangeFailure.invalid("\(label): stale patch accepted") }
    }

    private func exchange(_ requests: [InterchangeRequest], with adapter: Adapter, phase: String, rawInput: Data? = nil)
        async throws
        -> [InterchangeResponse]
    {
        let stem = temporary.appendingPathComponent("\(adapter.name)-\(phase)")
        var input = Data()
        for request in requests {
            let line = try encoder.encode(request)
            guard line.count <= 32 * 1024 * 1024 else { throw InterchangeFailure.invalid("Protocol request too large") }
            input.append(line); input.append(10)
        }
        if let rawInput { input = rawInput }
        guard input.count <= maximumTranscriptBytes else {
            throw InterchangeFailure.invalid("Input transcript too large")
        }
        let inputURL = stem.appendingPathExtension("input.jsonl")
        let outputURL = stem.appendingPathExtension("output.jsonl")
        let errorURL = stem.appendingPathExtension("stderr.txt")
        try input.write(to: inputURL)
        try Data().write(to: outputURL); try Data().write(to: errorURL)
        let inputHandle = try FileHandle(forReadingFrom: inputURL)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer { try? inputHandle.close(); try? outputHandle.close(); try? errorHandle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adapter.executable)
        process.arguments = adapter.arguments
        process.currentDirectoryURL = root
        process.standardInput = inputHandle; process.standardOutput = outputHandle; process.standardError = errorHandle
        try process.run()
        do {
            let started = DispatchTime.now().uptimeNanoseconds
            while process.isRunning {
                guard DispatchTime.now().uptimeNanoseconds - started < 120_000_000_000 else {
                    throw InterchangeFailure.invalid("\(adapter.name) timeout")
                }
                try transcriptBudget(outputURL, maximum: maximumTranscriptBytes)
                try transcriptBudget(errorURL, maximum: 2 * 1024 * 1024)
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        } catch {
            try await stop(process)
            throw error
        }
        try transcriptBudget(outputURL, maximum: maximumTranscriptBytes)
        try transcriptBudget(errorURL, maximum: 2 * 1024 * 1024)
        guard process.terminationStatus == 0 else {
            let detailHandle = try FileHandle(forReadingFrom: errorURL)
            defer { detailHandle.closeFile() }
            let detail = String(decoding: detailHandle.readData(ofLength: 2000), as: UTF8.self)
            throw InterchangeFailure.invalid("\(adapter.name) failed: \(detail)")
        }
        let output = try Data(contentsOf: outputURL)
        guard output.count <= maximumTranscriptBytes, output.last == 10 else {
            throw InterchangeFailure.invalid("\(adapter.name) incomplete/oversized transcript")
        }
        let lines = output.split(separator: 10, omittingEmptySubsequences: false).dropLast()
        guard lines.count == requests.count else {
            throw InterchangeFailure.invalid(
                "\(adapter.name) silently skipped requests: \(lines.count)/\(requests.count)"
            )
        }
        return try lines.map {
            let data = Data($0)
            try validateInterchangeJSON(data)
            return try decoder.decode(InterchangeResponse.self, from: data)
        }
    }

    private func transcriptBudget(_ url: URL, maximum: Int) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= maximum else {
            throw InterchangeFailure.invalid("Transcript exceeded budget: \(url.lastPathComponent)")
        }
    }

    private func stop(_ process: Process) async throws {
        guard process.isRunning else { return }
        process.terminate()
        let started = DispatchTime.now().uptimeNanoseconds
        while process.isRunning, !Task.isCancelled, DispatchTime.now().uptimeNanoseconds - started < 250_000_000 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        if process.isRunning {
            #if canImport(Darwin) || canImport(Glibc)
            _ = kill(process.processIdentifier, SIGKILL)
            #else
            throw InterchangeFailure.invalid("Development watchdog hard stop unavailable on this platform")
            #endif
        }
        let killed = DispatchTime.now().uptimeNanoseconds
        while process.isRunning, DispatchTime.now().uptimeNanoseconds - killed < 1_000_000_000 {
            // Cancellation must not interrupt reaping the child it just stopped.
            await Task.detached { try? await Task.sleep(nanoseconds: 10_000_000) }.value
        }
        guard !process.isRunning else {
            throw InterchangeFailure.invalid("Development child failed to exit after kill")
        }
        process.waitUntilExit()
    }

    private func checkExactJSONRegression() throws {
        try validateInterchangeJSON(Data("{\"metadata\":{\"e\\u0301\":\"last\"}}".utf8))
        for source in ["{\"metadata\":{\"e\\u0301\":\"last\",\"é\":\"last\"}}", "{\"ok\":true,\"ok\":true}"] {
            do {
                try validateInterchangeJSON(Data(source.utf8))
            } catch { continue }
            throw InterchangeFailure.invalid("Exact semantic-key regression was not rejected")
        }
    }

    private func checkAdapterBounds(_ adapter: Adapter) async throws {
        let source = "---\n3md: 1.1\n---\n@plane z=0\n" + String(repeating: "x", count: 3 * 1024 * 1024) + "\n"
        let replies = try await exchange(
            [
                .init(kind: "document", bytesHex: "zz"),
                .init(kind: "document", bytesHex: Data(source.utf8).hex),
                .init(kind: "document", bytesHex: Data("---\n3md: 1.1\n---\n".utf8).hex),
            ],
            with: adapter,
            phase: "bounds"
        )
        guard replies.count == 3, replies[0].error == "adapterFailure", replies[1].error == "adapterFailure",
            replies[2].ok
        else {
            throw InterchangeFailure.invalid("Swift protocol bounds/recovery regression")
        }
        let valid = InterchangeRequest(kind: "document", bytesHex: Data("---\n3md: 1.1\n---\n".utf8).hex)
        var input = Data("{bad json}\n".utf8)
        input.append(Data(repeating: 120, count: 32 * 1024 * 1024 + 1)); input.append(10)
        input.append(try encoder.encode(valid)); input.append(10)
        let inputReplies = try await exchange(
            [valid, valid, valid],
            with: adapter,
            phase: "input-bounds",
            rawInput: input
        )
        guard inputReplies[0].error == "adapterFailure", inputReplies[1].error == "adapterFailure", inputReplies[2].ok
        else {
            throw InterchangeFailure.invalid("Swift oversized/malformed request recovery regression")
        }
    }

    private func checkWatchdog(_ executable: String) async throws {
        let readyURL = temporary.appendingPathComponent("watchdog-ready.txt")
        try Data().write(to: readyURL)
        let ready = try FileHandle(forWritingTo: readyURL)
        defer { ready.closeFile() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--watchdog-probe"]
        process.standardOutput = ready
        try process.run()
        do {
            let started = DispatchTime.now().uptimeNanoseconds
            while try Data(contentsOf: readyURL).isEmpty {
                guard process.isRunning, DispatchTime.now().uptimeNanoseconds - started < 5_000_000_000 else {
                    throw InterchangeFailure.invalid("Watchdog probe failed to become ready")
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try await stop(process)
            guard !process.isRunning else {
                throw InterchangeFailure.invalid("Watchdog failed to reap TERM-resistant child")
            }
        } catch {
            try await stop(process)
            throw error
        }
        let adapter = Adapter(
            name: "watchdog-stderr",
            executable: executable,
            arguments: ["--watchdog-probe", "--stderr-overflow"]
        )
        do {
            _ = try await exchange([.init(kind: "document", bytesHex: "")], with: adapter, phase: "stderr-bounds")
        } catch let failure as InterchangeFailure {
            guard failure.description.contains("Transcript exceeded budget") else { throw failure }
            return
        }
        throw InterchangeFailure.invalid("Watchdog failed to limit stderr")
    }

    private func read<Value: Decodable>(_ path: String) throws -> Value {
        try decoder.decode(Value.self, from: readBytes(path))
    }

    private func readBytes(_ path: String) throws -> Data {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw InterchangeFailure.invalid("Fixture path escapes repository")
        }
        let bytes = try Data(contentsOf: root.appendingPathComponent(path))
        guard bytes.count <= 8 * 1024 * 1024 else { throw InterchangeFailure.invalid("Fixture too large") }
        return bytes
    }
}

private func runSwiftAdapter() {
    let maximum = 32 * 1024 * 1024
    var line = Data()
    var oversized = false
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    func emit(_ input: Data?) {
        var output = Data("{\"ok\":false,\"error\":\"adapterFailure\"}".utf8)
        if let input {
            do {
                try validateInterchangeJSON(input)
                let request = try decoder.decode(InterchangeRequest.self, from: input)
                guard request.schema == "3md-interchange-1" else { throw InterchangeFailure.invalid("Unknown schema") }
                let candidate = try encoder.encode(swiftInterchange(request))
                if candidate.count <= maximum { output = candidate }
            } catch { /* The bounded failure record preserves the next request. */  }
        }
        output.append(10)
        FileHandle.standardOutput.write(output)
    }
    while true {
        let chunk = FileHandle.standardInput.readData(ofLength: 8192)
        if chunk.isEmpty { break }
        let fragments = chunk.split(separator: 10, omittingEmptySubsequences: false)
        for (index, fragment) in fragments.enumerated() {
            if !oversized {
                if fragment.count > maximum - line.count {
                    oversized = true; line.removeAll(keepingCapacity: false)
                } else {
                    line.append(contentsOf: fragment)
                }
            }
            if index < fragments.count - 1 {
                emit(oversized ? nil : line)
                line.removeAll(keepingCapacity: true); oversized = false
            }
        }
    }
    if oversized || !line.isEmpty { emit(oversized ? nil : line) }
}

do {
    if CommandLine.arguments.contains("--watchdog-probe") {
        #if canImport(Darwin) || canImport(Glibc)
        guard #available(macOS 10.15, *) else { throw InterchangeFailure.invalid("Watchdog probe runtime unavailable") }
        signal(SIGTERM, SIG_IGN)
        FileHandle.standardOutput.write(Data("ready\n".utf8))
        if CommandLine.arguments.contains("--stderr-overflow") {
            FileHandle.standardError.write(Data(repeating: 120, count: 2 * 1024 * 1024 + 1))
        }
        while true { try await Task.sleep(nanoseconds: 100_000_000) }
        #else
        throw InterchangeFailure.invalid("Watchdog probe unsupported")
        #endif
    } else if CommandLine.arguments.contains("--adapter") {
        runSwiftAdapter()
    } else {
        guard #available(macOS 10.15, *) else {
            throw InterchangeFailure.invalid("Development gate needs macOS 10.15+")
        }
        try await InterchangeCoordinator().run()
    }
} catch {
    FileHandle.standardError.write(Data("Interchange failed: \(error)\n".utf8))
    exit(1)
}
