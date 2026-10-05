import Foundation
import ThreeMD

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

    private func exchange(_ requests: [InterchangeRequest], with adapter: Adapter, phase: String) async throws
        -> [InterchangeResponse]
    {
        let stem = temporary.appendingPathComponent("\(adapter.name)-\(phase)")
        var input = Data()
        for request in requests {
            let line = try encoder.encode(request)
            guard line.count <= 32 * 1024 * 1024 else { throw InterchangeFailure.invalid("Protocol request too large") }
            input.append(line); input.append(10)
        }
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
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning {
            if Date() >= deadline { process.terminate(); throw InterchangeFailure.invalid("\(adapter.name) timeout") }
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > maximumTranscriptBytes {
                process.terminate(); throw InterchangeFailure.invalid("\(adapter.name) oversized output")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard process.terminationStatus == 0 else {
            let detail = try String(contentsOf: errorURL, encoding: .utf8)
            throw InterchangeFailure.invalid("\(adapter.name) failed: \(detail.prefix(2000))")
        }
        let output = try Data(contentsOf: outputURL)
        guard output.count <= maximumTranscriptBytes, output.last == 10 else {
            throw InterchangeFailure.invalid("\(adapter.name) incomplete/oversized transcript")
        }
        let lines = output.split(separator: 10)
        guard lines.count == requests.count else {
            throw InterchangeFailure.invalid(
                "\(adapter.name) silently skipped requests: \(lines.count)/\(requests.count)"
            )
        }
        return try lines.map { try decoder.decode(InterchangeResponse.self, from: Data($0)) }
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

do {
    if CommandLine.arguments.contains("--adapter") {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        while let line = readLine() {
            guard line.utf8.count <= 32 * 1024 * 1024 else {
                throw InterchangeFailure.invalid("Adapter input too large")
            }
            let request = try decoder.decode(InterchangeRequest.self, from: Data(line.utf8))
            guard request.schema == "3md-interchange-1" else {
                throw InterchangeFailure.invalid("Unknown protocol schema")
            }
            let response = try swiftInterchange(request)
            print(String(decoding: try encoder.encode(response), as: UTF8.self))
        }
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
