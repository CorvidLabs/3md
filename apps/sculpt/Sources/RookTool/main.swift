import Darwin
import Foundation
import RookTooling
import RookVerification

private enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case wrongVersion(String, String)

    var description: String {
        switch self {
        case .usage(let message): return message
        case .wrongVersion(let executable, let received):
            return "Refusing unexpected tool version at \(executable): \(received)"
        }
    }
}

private func write(_ text: String, to handle: FileHandle = .standardOutput) {
    handle.write(Data(text.utf8))
}

private func requireVersion(
    executable: String,
    expected: String,
    contains: Bool = false,
    directory: URL
) throws {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["--version"]
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let actual = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = contains ? actual.contains(expected + " ") : actual == expected
    guard process.terminationReason == .exit, process.terminationStatus == 0, matches else {
        throw CLIError.wrongVersion(executable, actual)
    }
}

private func evidenceDirectory(arguments: [String], root: URL) throws -> URL {
    if arguments.isEmpty {
        return root.appendingPathComponent(".build/verification/\(UUID().uuidString)")
    }
    guard arguments.count == 2, arguments[0] == "--log-directory", arguments[1].hasPrefix("/") else {
        throw CLIError.usage("Only --log-directory /absolute/path is accepted for verification commands.")
    }
    return URL(fileURLWithPath: arguments[1], isDirectory: true)
}

private func report(_ result: SwiftTestRunResult) throws -> Int32 {
    write(String(decoding: try Data(contentsOf: URL(fileURLWithPath: result.logPath)), as: UTF8.self))
    write("\nRetained test log: \(result.logPath)\nTest receipt: \(result.receiptPath)\n")
    if !result.assessment.passed {
        for issue in result.assessment.issues {
            write("Verification rejected: \(issue.message)\n", to: .standardError)
        }
    }
    return result.exitCode
}

private func test(harness: Bool, arguments: [String], root: URL) throws -> Int32 {
    let evidence = try evidenceDirectory(arguments: arguments, root: root)
    write("Swift test evidence: \(evidence.path)\n")
    // AppKit hosts share process-wide editors and responders. Run the complete
    // suite sequentially so async fixtures cannot steal one another's native input.
    let childArguments =
        harness
        ? ["test", "--no-parallel", "--filter", "RookVerificationTests|RookToolingTests"]
        : ["test", "--no-parallel"]
    let result = try SwiftTestRunner.run(
        executable: URL(fileURLWithPath: "/usr/bin/swift"),
        arguments: childArguments,
        workingDirectory: root,
        logDirectory: evidence
    )
    return try report(result)
}

/// Fixed failing fixtures prove the same runner rejects misleading upstream success.
/// The real test command has no executor, filter, or status override.
private func probe(arguments: [String], root: URL) throws -> Int32 {
    guard let mode = arguments.first else {
        throw CLIError.usage("test-probe requires incomplete, issue, or nonzero.")
    }
    let output: String
    let status: Int32
    switch mode {
    case "incomplete":
        output = "◇ Test run started.\n↳ Testing Library Version: 1902\n"
        status = 0
    case "issue":
        output =
            "✘ Test syntheticProbe() recorded an issue: synthetic failure.\n"
            + "✔ Test run with 1 test in 0 suites passed after 0.001 seconds.\n"
        status = 0
    case "nonzero":
        output = "✔ Test run with 1 test in 0 suites passed after 0.001 seconds.\n"
        status = 7
    default:
        throw CLIError.usage("Unknown test-probe mode: \(mode)")
    }
    let owned = FileManager.default.temporaryDirectory
        .appendingPathComponent("rook-swift-probe-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
    let source = owned.appendingPathComponent("Fixture.swift")
    let program = """
        import Darwin
        import Foundation
        FileHandle.standardOutput.write(Data(\(String(reflecting: output)).utf8))
        exit(\(status))
        """
    try program.write(to: source, atomically: true, encoding: .utf8)
    let trailingArguments = Array(arguments.dropFirst())
    let evidence =
        trailingArguments.isEmpty
        ? owned.appendingPathComponent("evidence", isDirectory: true)
        : try evidenceDirectory(arguments: trailingArguments, root: root)
    let result = try SwiftTestRunner.run(
        executable: URL(fileURLWithPath: "/usr/bin/swift"),
        arguments: [source.path],
        workingDirectory: owned,
        logDirectory: evidence
    )
    return try report(result)
}

private func run() async -> Int32 {
    do {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            throw CLIError.usage(
                "Usage: RookTool test|test-harness|format|intent|spec|boundaries|release-fixture|package|run|build|examples|blockhaven|math-ladder|sculpture|volume-study|volume-worlds"
            )
        }
        let remaining = Array(arguments.dropFirst())
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if command == "volume-study" {
            FileHandle.standardOutput.write(try SculptureVolumeStudy.run(arguments: remaining, workingDirectory: root))
            return 0
        }
        if command == "volume-worlds" {
            FileHandle.standardOutput.write(try SculptureVolumeStudyWorldExport.run(arguments: remaining))
            return 0
        }
        if command == "sculpture" {
            let data: Data
            if remaining.first == "portable" {
                data = try SculpturePortableTool.run(arguments: Array(remaining.dropFirst()), workingDirectory: root)
            } else if remaining.first == "reference" {
                data = try SculptureReferenceModelTool.run(
                    arguments: Array(remaining.dropFirst()),
                    workingDirectory: root
                )
            } else if remaining.first == "math" {
                data = try await SculptureMathExampleExport.write(
                    arguments: Array(remaining.dropFirst()),
                    workingDirectory: root
                )
            } else {
                data = try SculptureCommandTool.run(arguments: remaining, workingDirectory: root)
            }
            FileHandle.standardOutput.write(data)
            return 0
        }
        try requireVersion(executable: "/opt/homebrew/bin/fledge", expected: "fledge 1.7.2", directory: root)
        if ["test", "test-harness", "test-probe"].contains(command) {
            try requireVersion(
                executable: "/usr/bin/swift",
                expected: "Apple Swift version 6.3.3",
                contains: true,
                directory: root
            )
        }
        switch command {
        case "test": return try test(harness: false, arguments: remaining, root: root)
        case "test-harness": return try test(harness: true, arguments: remaining, root: root)
        case "test-probe": return try probe(arguments: remaining, root: root)
        case "examples":
            guard remaining.isEmpty else { throw CLIError.usage("examples does not accept arguments.") }
            try await SculptureExampleExport.generate(in: root)
            return 0
        case "blockhaven":
            guard remaining.isEmpty else { throw CLIError.usage("blockhaven does not accept arguments.") }
            try await SculptureExampleExport.generateBlockhaven(in: root)
            return 0
        case "math-ladder":
            guard remaining.isEmpty else { throw CLIError.usage("math-ladder does not accept arguments.") }
            try await SculptureMathExampleExport.generate(in: root)
            return 0
        default:
            guard let native = ToolingCommand(rawValue: command) else {
                throw CLIError.usage("Unknown RookTool command: \(command)")
            }
            return try await RookTooling.run(command: native, arguments: remaining, workingDirectory: root)
        }
    } catch {
        write("RookTool failed: \(failureDescription(error))\n", to: .standardError)
        return 1
    }
}

/// Prefers a tool or library error's readable explanation over its enum spelling.
private func failureDescription(_ error: any Error) -> String {
    if let localized = error as? any LocalizedError, let description = localized.errorDescription {
        return description
    }
    return String(describing: error)
}

exit(await run())
