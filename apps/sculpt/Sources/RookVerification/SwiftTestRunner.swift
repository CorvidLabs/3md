import Foundation

/// Retained execution and verification evidence for one owned test command.
public struct SwiftTestRunResult: Codable, Equatable, Sendable {
    /// The exact executable used by the child process.
    public let executable: String
    /// Arguments passed without shell interpretation.
    public let arguments: [String]
    /// Directory from which the child command ran.
    public let workingDirectory: String
    /// Retained combined standard output and standard error.
    public let logPath: String
    /// Retained structured assessment path.
    public let receiptPath: String
    /// Actual shell-compatible child status, including128+signal where applicable.
    public let upstreamExitCode: Int32
    /// The signal reported by Foundation when termination was signal-driven.
    public let terminationSignal: Int32?
    /// Completion and issue assessment of the actual child log.
    public let assessment: TestLogAssessment

    /// Preserve a real child failure; reject incomplete/issue-bearing exit0 logs.
    public var exitCode: Int32 {
        upstreamExitCode != 0 ? upstreamExitCode : assessment.passed ? 0 : 1
    }
}

/// Errors that prevent retaining or interpreting trustworthy verification evidence.
public enum SwiftTestRunnerError: Error, Equatable, Sendable {
    /// Refuses replacing a previous raw log or receipt.
    case retainedEvidenceExists(String)
    /// The log exceeded the parser's bounded input policy.
    case oversizedLog(Int)
    /// Output is preserved but cannot be interpreted as UTF-8 Swift Testing output.
    case invalidLogEncoding(String)
    /// The raw log could not be created for the child process.
    case cannotCreateLog(String)
}

/// Runs a child and validates its actual status and complete Swift Testing output.
public enum SwiftTestRunner {
    /// Execute a command with argument arrays, preserving raw output and a receipt.
    ///
    /// The production CLI supplies the pinned Swift executable and complete test
    /// arguments. Verification tests use only owned synthetic Swift programs.
    public static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        logDirectory: URL,
        expectedTests: Int? = nil
    ) throws -> SwiftTestRunResult {
        let manager = FileManager.default
        try manager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let log = logDirectory.appendingPathComponent("swift-test.log")
        let receipt = logDirectory.appendingPathComponent("swift-test-result.json")
        guard !manager.fileExists(atPath: log.path), !manager.fileExists(atPath: receipt.path) else {
            throw SwiftTestRunnerError.retainedEvidenceExists(logDirectory.path)
        }
        guard manager.createFile(atPath: log.path, contents: nil) else {
            throw SwiftTestRunnerError.cannotCreateLog(log.path)
        }
        let output = try FileHandle(forWritingTo: log)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            try output.close()
        } catch {
            try? output.close()
            throw error
        }
        let size = try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= SwiftTestLog.maximumLogBytes else {
            throw SwiftTestRunnerError.oversizedLog(size)
        }
        let raw = try Data(contentsOf: log)
        guard raw.count <= SwiftTestLog.maximumLogBytes else {
            throw SwiftTestRunnerError.oversizedLog(raw.count)
        }
        guard let text = String(data: raw, encoding: .utf8) else {
            throw SwiftTestRunnerError.invalidLogEncoding(log.path)
        }
        let signal = process.terminationReason == .uncaughtSignal ? process.terminationStatus : nil
        let status = signal.map { 128 + $0 } ?? process.terminationStatus
        let assessment = SwiftTestLog.assess(
            text,
            upstreamExitCode: status,
            expectedTests: expectedTests
        )
        let result = SwiftTestRunResult(
            executable: executable.path,
            arguments: arguments,
            workingDirectory: workingDirectory.path,
            logPath: log.path,
            receiptPath: receipt.path,
            upstreamExitCode: status,
            terminationSignal: signal,
            assessment: assessment
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: receipt, options: .atomic)
        return result
    }
}
