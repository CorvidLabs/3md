import Foundation
import Testing

@testable import RookVerification

private let completeSummary = "✔ Test run with 121 tests in 0 suites passed after 2.259 seconds.\n"
private let testStart = "◇ Test run started.\n↳ Testing Library Version: 1902\n"

private func executeFixture(output: String, status: Int32) throws -> SwiftTestRunResult {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("rook-swift-runner-fixture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let program = root.appendingPathComponent("Fixture.swift")
    let source = """
        import Foundation
        import Darwin
        FileHandle.standardOutput.write(Data(\(String(reflecting: output)).utf8))
        exit(\(status))
        """
    try source.write(to: program, atomically: true, encoding: .utf8)
    return try SwiftTestRunner.run(
        executable: URL(fileURLWithPath: "/usr/bin/swift"),
        arguments: [program.path],
        workingDirectory: root,
        logDirectory: root.appendingPathComponent("evidence"),
        expectedTests: 121
    )
}

@Test func runnerAcceptsCompleteSwiftChild() throws {
    let result = try executeFixture(output: testStart + completeSummary, status: 0)
    #expect(result.exitCode == 0)
    #expect(result.assessment.passed)
    let log = try String(contentsOfFile: result.logPath, encoding: .utf8)
    #expect(log == testStart + completeSummary)
    let decoded = try JSONDecoder().decode(
        SwiftTestRunResult.self,
        from: Data(contentsOf: URL(fileURLWithPath: result.receiptPath))
    )
    #expect(decoded == result)
}

@Test func runnerRejectsPrematureSwiftChildExitZero() throws {
    let result = try executeFixture(output: testStart, status: 0)
    #expect(result.upstreamExitCode == 0)
    #expect(result.exitCode == 1)
    #expect(!result.assessment.passed)
}

@Test func runnerRejectsSwiftChildRecordedIssueAtExitZero() throws {
    let issue = "✘ Test controlledFixture() recorded an issue at Fixture.swift:1:1\n"
    let result = try executeFixture(output: testStart + issue, status: 0)
    #expect(result.upstreamExitCode == 0)
    #expect(result.exitCode == 1)
    #expect(!result.assessment.failureLines.isEmpty)
}

@Test func runnerPreservesActualSwiftChildExitSeven() throws {
    let result = try executeFixture(output: testStart + completeSummary, status: 7)
    #expect(result.upstreamExitCode == 7)
    #expect(result.exitCode == 7)
    #expect(!result.assessment.passed)
}

@Test func runnerDoesNotOverwriteRetainedEvidence() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("rook-swift-runner-retained-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let log = root.appendingPathComponent("swift-test.log")
    try "retained".write(to: log, atomically: true, encoding: .utf8)
    #expect(throws: SwiftTestRunnerError.retainedEvidenceExists(root.path)) {
        try SwiftTestRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["--version"],
            workingDirectory: root,
            logDirectory: root
        )
    }
    #expect(try String(contentsOf: log, encoding: .utf8) == "retained")
}
